module AgentServer

using HTTP, WebSockets, JSON3, Logging, UUIDs, Dates
using ..Loop
using ..History
using ..Confirmation
using ..ToolRegistry

export start_server

# ── Configuración del servidor ───────────────────────────────────────────────
const DEFAULT_PORT = 9000
const DEFAULT_HOST = "0.0.0.0"

# ── Sesiones activas ─────────────────────────────────────────────────────────
const SESSIONS = Dict{String, AgentLoop}()
const SESSIONS_LOCK = ReentrantLock()

# ── Entrada al servidor ──────────────────────────────────────────────────────
function start_server(;
    host :: String = DEFAULT_HOST,
    port :: Int    = DEFAULT_PORT,
    key  :: String = "sk-phaimat-agent",
)
    @info "paipermc agent server starting on ws://$(host):$(port)"

    WebSockets.listen(host, UInt16(port)) do ws
        handle_connection(ws, key)
    end
end

# ── Manejo de una conexión WebSocket ─────────────────────────────────────────
function handle_connection(ws::WebSocket, server_key::String)
    session_id = string(uuid4())
    loop_ref   = Ref{Union{AgentLoop, Nothing}}(nothing)

    @info "New connection" session_id

    try
        while isopen(ws)
            raw = receive(ws)
            isempty(raw) && continue

            msg = try
                JSON3.read(raw, Dict{String,Any})
            catch
                send_error(ws, session_id, "Invalid JSON")
                continue
            end

            msg_type = get(msg, "type", "")

            if msg_type == "session_start"
                handle_session_start!(ws, msg, session_id, server_key, loop_ref)

            elseif msg_type == "user_message"
                handle_user_message!(ws, msg, session_id, loop_ref)

            elseif msg_type == "confirm_response"
                handle_confirm_response!(msg, session_id, loop_ref)

            elseif msg_type == "ping"
                send_msg(ws, Dict("type" => "pong", "session_id" => session_id))

            else
                send_error(ws, session_id, "Unknown message type: $msg_type")
            end
        end
    catch e
        e isa WebSockets.WebSocketClosedError && return
        @error "WebSocket error" session_id exception=e
    finally
        lock(SESSIONS_LOCK) do
            delete!(SESSIONS, session_id)
        end
        @info "Connection closed" session_id
    end
end

# ── Handlers de mensajes ─────────────────────────────────────────────────────
function handle_session_start!(ws, msg, session_id, server_key, loop_ref)
    # Autenticación simple por key
    client_key = get(msg, "key", "")
    if client_key != server_key
        send_msg(ws, Dict(
            "type"       => "error",
            "session_id" => session_id,
            "message"    => "Authentication failed",
            "code"       => 401,
        ))
        return
    end

    project_root   = get(msg, "project_root", pwd())
    model_override = get(msg, "model", nothing)
    verbose        = get(msg, "verbose", false)

    # Resolver nombre del proyecto desde papermind.toml si existe
    project_name = _read_project_name(project_root)

    config = AgentLoopConfig(
        session_id,
        project_root,
        model_override === "auto" ? nothing : model_override,
        verbose,
        false,
    )

    # Canal para confirmaciones pendientes
    confirm_channel = Channel{ConfirmResponse}(1)

    callbacks = ClientCallbacks(
        # on_token
        token -> send_msg(ws, Dict(
            "type"       => "token",
            "session_id" => session_id,
            "content"    => token,
        )),
        # on_tool_start
        (tool, args) -> send_msg(ws, Dict(
            "type"       => "tool_start",
            "session_id" => session_id,
            "tool"       => tool,
            "args"       => args,
        )),
        # on_tool_result
        (tool, summary) -> send_msg(ws, Dict(
            "type"       => "tool_result",
            "session_id" => session_id,
            "tool"       => tool,
            "summary"    => summary,
        )),
        # on_agent_swap
        (from, to, eta) -> send_msg(ws, Dict(
            "type"        => "agent_changed",
            "session_id"  => session_id,
            "from"        => from,
            "to"          => to,
            "eta_seconds" => eta,
        )),
        # on_confirm — bloquea hasta recibir respuesta del cliente
        req -> begin
            send_msg(ws, Dict(
                "type"       => "confirm_request",
                "session_id" => session_id,
                "request_id" => req.id,
                "action"     => string(req.action),
                "message"    => req.message,
                "files"      => [Dict("path" => f.path, "diff" => f.diff)
                                 for f in req.files],
                "metadata"   => req.metadata,
            ))
            # Esperar respuesta con timeout
            resp = try
                fetch(timedwait(() -> isready(confirm_channel),
                                CONFIRM_TIMEOUT))
                take!(confirm_channel)
            catch
                ConfirmResponse(req.id, :no)  # timeout → cancelar
            end
            resp
        end,
        # on_done
        () -> send_msg(ws, Dict(
            "type"       => "done",
            "session_id" => session_id,
        )),
        # on_error
        msg -> send_msg(ws, Dict(
            "type"       => "error",
            "session_id" => session_id,
            "message"    => msg,
        )),
    )

    tools = build_registry(project_root)
    loop  = AgentLoop(config, callbacks, tools)
    loop_ref[] = loop

    lock(SESSIONS_LOCK) do
        SESSIONS[session_id] = loop
    end

    # Guardar canal de confirmación en el loop (extensión simple)
    # TODO: mover a campo dedicado en AgentLoop
    loop.tool_registry["__confirm_channel__"] =
        (_, _) -> (put!(confirm_channel, ConfirmResponse("", :yes)); "ok")

    send_msg(ws, Dict(
        "type"        => "session_ready",
        "session_id"  => session_id,
        "agent"       => loop.active_agent,
        "project"     => project_name,
        "project_root" => project_root,
    ))

    @info "Session started" session_id project=project_name agent=loop.active_agent
end

function handle_user_message!(ws, msg, session_id, loop_ref)
    isnothing(loop_ref[]) && begin
        send_error(ws, session_id, "No active session — send session_start first")
        return
    end

    content = get(msg, "content", "")
    isempty(content) && return

    # Ejecutar en tarea separada para no bloquear el reader del WebSocket
    @async begin
        try
            run!(loop_ref[], content)
        catch e
            @error "Error in agent loop" exception=e
            send_msg(ws, Dict(
                "type"       => "error",
                "session_id" => session_id,
                "message"    => sprint(showerror, e),
            ))
        end
    end
end

function handle_confirm_response!(msg, session_id, loop_ref)
    isnothing(loop_ref[]) && return

    answer_str = get(msg, "answer", "n")
    answer = answer_str == "y"   ? :yes  :
             answer_str == "s"   ? :skip :
             answer_str == "e"   ? :edit : :no

    request_id = get(msg, "request_id", "")
    resp = ConfirmResponse(request_id, answer)

    # Enviar al canal de confirmación del loop
    channel_fn = get(loop_ref[].tool_registry, "__confirm_channel__", nothing)
    isnothing(channel_fn) && return

    # El canal real está capturado en el closure del callback on_confirm
    # Aquí necesitamos una referencia directa — TODO: refactor en v0.2
    # Por ahora usamos un dict global de canales por session
    _deliver_confirm(session_id, resp)
end

# ── Canal global de confirmaciones por sesión ────────────────────────────────
const CONFIRM_CHANNELS = Dict{String, Channel{ConfirmResponse}}()

function _register_confirm_channel!(session_id::String, ch::Channel{ConfirmResponse})
    CONFIRM_CHANNELS[session_id] = ch
end

function _deliver_confirm(session_id::String, resp::ConfirmResponse)
    ch = get(CONFIRM_CHANNELS, session_id, nothing)
    isnothing(ch) && return
    isready(ch) && return  # ya hay una respuesta pendiente
    put!(ch, resp)
end

# ── Helpers ──────────────────────────────────────────────────────────────────
function send_msg(ws::WebSocket, data::Dict)
    try
        send(ws, JSON3.write(data))
    catch
        # conexión cerrada — ignorar
    end
end

function send_error(ws::WebSocket, session_id::String, message::String)
    send_msg(ws, Dict(
        "type"       => "error",
        "session_id" => session_id,
        "message"    => message,
    ))
end

function _read_project_name(root::String) :: String
    toml_path = joinpath(root, "papermind.toml")
    isfile(toml_path) || return basename(root)
    try
        cfg = TOML.parsefile(toml_path)
        get(get(cfg, "project", Dict()), "name", basename(root))
    catch
        basename(root)
    end
end

end # module AgentServer
