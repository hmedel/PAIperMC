using REPL, Sockets, JSON3

export start

# ── Colores ANSI ─────────────────────────────────────────────────────────────
const RESET  = "\033[0m"
const BOLD   = "\033[1m"
const DIM    = "\033[2m"
const GREEN  = "\033[32m"
const CYAN   = "\033[36m"
const YELLOW = "\033[33m"
const RED    = "\033[31m"

# ── Estado del REPL ──────────────────────────────────────────────────────────
mutable struct ReplState
    agent        :: String
    project_name :: String
    project_root :: String
    model        :: Union{String, Nothing}
    verbose      :: Bool
    ws           :: Union{Any, Nothing}   # WebSocket al agent server
    session_id   :: String
    running      :: Bool
end

# ── Prompt dinámico ───────────────────────────────────────────────────────────
function make_prompt(state::ReplState) :: String
    "$(CYAN)paiper$(RESET) $(DIM)[$(state.agent)]$(RESET) " *
    "$(state.project_name) $(BOLD)>$(RESET) "
end

# ── Entry point ───────────────────────────────────────────────────────────────
function start(;
    project_root :: String = pwd(),
    model        :: Union{String, Nothing} = nothing,
    verbose      :: Bool = false,
    server_host  :: String = "100.64.0.22",
    server_port  :: Int    = 9000,
    server_key   :: String = get(ENV, "PAIPERMC_AGENT_KEY", "sk-phaimat-agent"),
)
    project_name = _read_project_name(project_root)

    state = ReplState(
        "writer", project_name, project_root,
        model, verbose, nothing, "", true,
    )

    println("\n$(BOLD)paipermc$(RESET) v0.1.0 — $(project_name)")
    println("$(DIM)Connecting to agent server at $(server_host):$(server_port)...$(RESET)")

    # Conectar al agent server
    ws = _connect(server_host, server_port, server_key, project_root, model, state)

    if isnothing(ws)
        println("$(RED)Could not connect to agent server.$(RESET)")
        println("$(DIM)Start it with: paipermc serve$(RESET)")
        return
    end

    state.ws = ws
    println("$(GREEN)Connected.$(RESET) Type /help for commands.\n")

    # Loop principal del REPL
    while state.running
        # Mostrar prompt
        print(make_prompt(state))
        flush(stdout)

        # Leer input
        line = try readline(stdin) catch; nothing end
        (isnothing(line) || line == "") && continue

        line = strip(line)
        isempty(line) && continue

        # Slash commands
        if startswith(line, "/")
            handle_slash_command!(state, line)
            continue
        end

        # Mensaje al agente
        send_message!(state, line)
    end

    println("\n$(DIM)Goodbye.$(RESET)")
end

# ── Slash commands ────────────────────────────────────────────────────────────
function handle_slash_command!(state::ReplState, line::String)
    parts = split(line)
    cmd   = parts[1]
    args  = length(parts) > 1 ? join(parts[2:end], " ") : ""

    if cmd == "/help"
        print_help()

    elseif cmd == "/agent"
        isempty(args) && (println("Usage: /agent <name>"); return)
        send_json!(state, Dict("type" => "set_agent", "agent" => args))
        state.agent = args
        println("$(DIM)Agent set to: $(args)$(RESET)")

    elseif cmd == "/model"
        isempty(args) && (println("Usage: /model <name>"); return)
        state.model = args
        println("$(DIM)Model override: $(args)$(RESET)")

    elseif cmd == "/search"
        isempty(args) && (println("Usage: /search <query>"); return)
        send_message!(state, "Search literature: $args")

    elseif cmd == "/file"
        isempty(args) && (println("Usage: /file <path>"); return)
        send_message!(state, "Read and summarize file: $args")

    elseif cmd == "/context"
        send_json!(state, Dict("type" => "get_context"))

    elseif cmd == "/history"
        send_json!(state, Dict("type" => "get_history"))

    elseif cmd == "/clear"
        send_json!(state, Dict("type" => "clear_context"))
        println("$(DIM)Context cleared.$(RESET)")

    elseif cmd == "/status"
        send_json!(state, Dict("type" => "ping"))

    elseif cmd == "/verbose"
        state.verbose = !state.verbose
        println("$(DIM)Verbose: $(state.verbose)$(RESET)")

    elseif cmd in ("/exit", "/quit", "/q")
        state.running = false

    else
        println("$(YELLOW)Unknown command: $(cmd). Type /help for available commands.$(RESET)")
    end
end

function print_help()
    println("""
$(BOLD)paipermc REPL commands$(RESET)

  $(CYAN)/agent$(RESET)  <name>    Switch agent (writer, mathematician, literature,
                    researcher, reviewer-style, reviewer-argument,
                    reviewer-gaps, lean)
  $(CYAN)/model$(RESET)  <name>    Override model for this session
  $(CYAN)/search$(RESET) <query>   Search literature
  $(CYAN)/file$(RESET)   <path>    Load file into context
  $(CYAN)/context$(RESET)          Show current context summary
  $(CYAN)/history$(RESET)          Show conversation history
  $(CYAN)/clear$(RESET)            Reset context and history
  $(CYAN)/status$(RESET)           Check agent server status
  $(CYAN)/verbose$(RESET)          Toggle verbose mode
  $(CYAN)/exit$(RESET)             Exit REPL
""")
end

# ── Enviar mensaje al agente y mostrar respuesta ──────────────────────────────
function send_message!(state::ReplState, content::String)
    isnothing(state.ws) && (println("$(RED)Not connected$(RESET)"); return)

    send_json!(state, Dict(
        "type"       => "user_message",
        "session_id" => state.session_id,
        "content"    => content,
        "model"      => state.model,
    ))

    # Leer respuesta en streaming hasta "done"
    print("\n")
    while true
        raw = try receive_json!(state) catch; nothing end
        isnothing(raw) && break

        msg_type = get(raw, "type", "")

        if msg_type == "token"
            print(get(raw, "content", ""))
            flush(stdout)

        elseif msg_type == "tool_start" && state.verbose
            tool = get(raw, "tool", "?")
            print("\n$(DIM)[tool: $(tool)]$(RESET) ")

        elseif msg_type == "tool_result" && state.verbose
            summary = get(raw, "summary", "")
            println("$(DIM)→ $(summary)$(RESET)")

        elseif msg_type == "agent_changed"
            from = get(raw, "from", "?")
            to   = get(raw, "to", "?")
            eta  = get(raw, "eta_seconds", 0)
            println("\n$(DIM)[switching agent: $(from) → $(to) (~$(eta)s)]$(RESET)")
            state.agent = to

        elseif msg_type == "confirm_request"
            handle_confirm_in_repl!(state, raw)

        elseif msg_type == "done"
            println("\n")
            break

        elseif msg_type == "error"
            println("\n$(RED)Error: $(get(raw, "message", "unknown"))$(RESET)\n")
            break

        elseif msg_type == "pong"
            println("$(GREEN)● server OK$(RESET)")
            break
        end
    end
end

# ── Confirmación interactiva en el REPL ──────────────────────────────────────
function handle_confirm_in_repl!(state::ReplState, msg::Dict)
    println("\n$(BOLD)  paipermc wants to $(get(msg, "message", "perform action"))$(RESET)")

    files = get(msg, "files", [])
    for f in files
        println("  ┌─ $(f["path"]) " * "─"^max(0, 50-length(f["path"])))
        diff_lines = split(get(f, "diff", ""), '\n')
        for line in diff_lines[1:min(15, end)]
            color = startswith(line, "+") ? GREEN :
                    startswith(line, "-") ? RED    : DIM
            println("  │ $(color)$(line)$(RESET)")
        end
        println("  └" * "─"^52)
    end

    print("\n  $(BOLD)Allow?$(RESET) [y/n/s(kip)] ")
    flush(stdout)

    answer = try strip(readline(stdin)) catch; "n" end
    answer = isempty(answer) ? "n" : string(answer[1])

    send_json!(state, Dict(
        "type"       => "confirm_response",
        "session_id" => state.session_id,
        "request_id" => get(msg, "request_id", ""),
        "answer"     => answer,
    ))
end

# ── WebSocket helpers ─────────────────────────────────────────────────────────
function _connect(host, port, key, project_root, model, state) :: Union{Any, Nothing}
    # Stub — conexión real implementada en cli/connection.jl
    # Retorna nothing si no puede conectar
    nothing
end

function send_json!(state::ReplState, data::Dict)
    isnothing(state.ws) && return
    # send(state.ws, JSON3.write(data))  # implementado en connection.jl
end

function receive_json!(state::ReplState) :: Union{Dict, Nothing}
    isnothing(state.ws) && return nothing
    # raw = receive(state.ws)
    # JSON3.read(raw, Dict{String,Any})
    nothing
end

# ── Helpers ───────────────────────────────────────────────────────────────────
function _read_project_name(root::String) :: String
    toml = joinpath(root, "papermind.toml")
    isfile(toml) || return basename(root)
    try
        using TOML
        cfg = TOML.parsefile(toml)
        get(get(cfg, "project", Dict()), "name", basename(root))
    catch
        basename(root)
    end
end
