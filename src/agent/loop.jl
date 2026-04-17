module Loop

using Logging, Dates, UUIDs
using ..Definitions
using ..Gateway
using ..History
using ..Router
using ..Confirmation

export AgentLoop, AgentLoopConfig, run!, stop!

# ── Configuración del loop ───────────────────────────────────────────────────
struct AgentLoopConfig
    session_id    :: String
    project_root  :: String
    model_override :: Union{String, Nothing}
    verbose       :: Bool
    no_confirm    :: Bool   # skip confirmations (scripting mode)
end

# ── Callbacks del cliente ────────────────────────────────────────────────────
# El loop no sabe si está en CLI, REPL o WebSocket.
# Usa callbacks para comunicarse con el cliente.
struct ClientCallbacks
    on_token       :: Function   # (token::String) → nothing
    on_tool_start  :: Function   # (tool::String, args::Dict) → nothing
    on_tool_result :: Function   # (tool::String, summary::String) → nothing
    on_agent_swap  :: Function   # (from::String, to::String, eta_s::Int) → nothing
    on_confirm     :: Function   # (req::ConfirmRequest) → ConfirmResponse
    on_done        :: Function   # () → nothing
    on_error       :: Function   # (msg::String) → nothing
end

# ── Estado del loop ──────────────────────────────────────────────────────────
mutable struct AgentLoop
    config      :: AgentLoopConfig
    history     :: ConversationHistory
    callbacks   :: ClientCallbacks
    active_agent :: String
    tool_registry :: Dict{String, Function}
    running     :: Bool
end

# ── Constructor ──────────────────────────────────────────────────────────────
function AgentLoop(
    config    :: AgentLoopConfig,
    callbacks :: ClientCallbacks,
    tools     :: Dict{String, Function},
) :: AgentLoop

    # Agente y system prompt inicial
    initial_agent = something(config.model_override, "writer")
    haskey(AGENTS, initial_agent) || (initial_agent = "writer")
    agent_cfg = AGENTS[initial_agent]

    history = ConversationHistory(agent_cfg.system_prompt)

    AgentLoop(config, history, callbacks, initial_agent, tools, false)
end

# ── Run — procesa un mensaje del usuario ─────────────────────────────────────
"""
Ejecuta el loop agentico para un mensaje de usuario.
El loop continúa hasta que el modelo no emite más tool calls.
"""
function run!(loop::AgentLoop, user_message::String)
    loop.running = true

    try
        # 1. Routing — seleccionar agente
        route = route_agent(
            user_message,
            nothing,                    # active_file — TODO: pasar desde cliente
            loop.config.model_override,
            loop.active_agent,
        )

        if route.swap
            @info "Agent swap: $(loop.active_agent) → $(route.agent)"
            loop.callbacks.on_agent_swap(loop.active_agent, route.agent, 4)

            # Actualizar system prompt si cambia el agente
            if haskey(AGENTS, route.agent)
                loop.history.system_prompt = AGENTS[route.agent].system_prompt
            end
            loop.active_agent = route.agent
        end

        # 2. Añadir mensaje del usuario al historial
        push_user!(loop.history, user_message)
        trim_to_limit!(loop.history)

        # 3. Loop agentico
        max_iterations = 10
        iteration = 0

        while iteration < max_iterations && loop.running
            iteration += 1
            messages = to_messages(loop.history)

            # Preparar tool specs para este modelo
            tool_specs = _build_tool_specs(loop.tool_registry)

            # Llamada al modelo con streaming
            response_content = Ref{String}("")
            response_tools   = Ref{Vector{ToolCall}}(ToolCall[])

            response = stream_completion(
                route.model,
                messages,
                token -> loop.callbacks.on_token(token);
                tools = tool_specs,
            )

            response_content[] = response.content
            response_tools[]   = response.tool_calls

            # Sin tool calls → respuesta final
            if isempty(response_tools[])
                push_assistant!(loop.history, response_content[])
                loop.callbacks.on_done()
                break
            end

            # Con tool calls → ejecutar herramientas
            push_assistant!(loop.history, response_content[])

            for tc in response_tools[]
                _execute_tool_call!(loop, tc)
                loop.running || break
            end
        end

        iteration >= max_iterations && @warn "Loop alcanzó máximo de iteraciones"

    catch e
        msg = sprint(showerror, e)
        @error "AgentLoop error" exception=e
        loop.callbacks.on_error(msg)
    finally
        loop.running = false
    end
end

function stop!(loop::AgentLoop)
    loop.running = false
end

# ── Ejecución de tool calls ──────────────────────────────────────────────────
function _execute_tool_call!(loop::AgentLoop, tc::ToolCall)
    tool_fn = get(loop.tool_registry, tc.name, nothing)

    if isnothing(tool_fn)
        @warn "Tool desconocido: $(tc.name)"
        push_tool!(loop.history, tc.name, "Error: tool '$(tc.name)' not found")
        return
    end

    # Notificar inicio
    loop.callbacks.on_tool_start(tc.name, tc.arguments)

    # Verificar si requiere confirmación
    action = _tool_to_action(tc.name)
    if !isnothing(action) && !loop.config.no_confirm
        req = build_confirm_request(
            action,
            "paipermc wants to run: $(tc.name)",
            metadata = tc.arguments,
        )
        resp = loop.callbacks.on_confirm(req)

        if resp.answer ∈ (:no, :skip)
            push_tool!(loop.history, tc.name, "User declined: $(tc.name) was not executed")
            loop.callbacks.on_tool_result(tc.name, "skipped by user")
            return
        end
    end

    # Ejecutar la herramienta
    result = try
        tool_fn(tc.arguments, loop.config.project_root)
    catch e
        "Tool error: $(sprint(showerror, e))"
    end

    result_str = string(result)
    push_tool!(loop.history, tc.name, result_str)

    summary = length(result_str) > 120 ? result_str[1:120] * "…" : result_str
    loop.callbacks.on_tool_result(tc.name, summary)
end

# ── Helpers ──────────────────────────────────────────────────────────────────
function _tool_to_action(tool_name::String) :: Union{ConfirmAction, Nothing}
    tool_name == "write_file"       && return WRITE_FILE
    tool_name == "fetch_paper"      && return FETCH_PAPER
    tool_name == "index_pdf"        && return INDEX_PDF
    tool_name == "lean_compile"     && return LEAN_COMPILE
    tool_name == "call_external"    && return CALL_EXTERNAL
    tool_name == "search_external"  && return SEARCH_EXTERNAL
    nothing  # lectura y búsqueda local: autónomas
end

"""
Construye las specs de tools en formato OpenAI para enviar al modelo.
"""
function _build_tool_specs(registry::Dict{String, Function}) :: Vector{Dict}
    # Definiciones de tools — en producción esto viene de tools/registry.jl
    # Por ahora retornamos vacío para no sobrecargar el contexto inicial
    # El registry.jl inyectará las specs completas
    Dict[]
end

end # module
