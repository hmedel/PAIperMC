module Main

using ArgParse, Logging
using ..AgentServer
using ..Gateway
using ..SearchLiterature

export julia_main

# ── Parseo de argumentos ─────────────────────────────────────────────────────
function parse_args_paipermc(args::Vector{String})
    s = ArgParseSettings(
        prog        = "paipermc",
        description = "AI research platform for scientific papers",
        version     = "0.1.0",
        add_version = true,
    )

    @add_arg_table! s begin
        "command"
            help     = "Command or prompt (omit for interactive REPL)"
            nargs    = '?'
            default  = nothing

        "--model", "-m"
            help    = "Override model (writer, mathematician, claude-opus-4-5, ...)"
            default = nothing

        "--flow", "-f"
            help    = "Run named pipeline (research, literature, review, verify)"
            default = nothing

        "--mode"
            help    = "Flow sub-mode (style, argument, gaps, exhaustive)"
            default = nothing

        "--project", "-p"
            help    = "Project root directory"
            default = nothing

        "--remote", "-r"
            help   = "Run agent on xolotl via SSH"
            action = :store_true

        "--no-confirm"
            help   = "Skip confirmation prompts (scripting mode)"
            action = :store_true

        "--verbose"
            help   = "Show agent reasoning, tool calls, and model swaps"
            action = :store_true

        "--serve"
            help   = "Start MCP server for Emacs (stdio mode)"
            action = :store_true

        "--port"
            help    = "Agent server port (server mode only)"
            arg_type = Int
            default  = 9000

        "--host"
            help    = "Agent server host (server mode only)"
            default  = "0.0.0.0"

        "--key"
            help    = "Agent server authentication key"
            default  = get(ENV, "PAIPERMC_AGENT_KEY", "sk-phaimat-agent")
    end

    parse_args(args, s)
end

# ── Entry point principal ────────────────────────────────────────────────────
function julia_main() :: Cint
    args = parse_args_paipermc(ARGS)

    # Configurar nivel de logging
    args["verbose"] && global_logger(ConsoleLogger(stderr, Logging.Debug))

    # Resolver project root
    project_root = _resolve_project_root(args["project"])

    # Configurar gateway
    litellm_host = get(ENV, "PAIPERMC_LITELLM_HOST", "http://100.64.0.22:8088")
    litellm_key  = get(ENV, "PAIPERMC_LITELLM_KEY", "sk-phaimat-local")
    Gateway.set_host!(litellm_host)
    Gateway.set_key!(litellm_key)

    # Configurar literature-svc
    lit_host = get(ENV, "PAIPERMC_LITERATURE_HOST", "http://100.64.0.22:8081")
    SearchLiterature.set_host!(lit_host)

    # Despacho de comandos
    cmd = args["command"]

    if args["serve"]
        # Modo MCP stdio para Emacs
        include("../mcp/server.jl")
        MCPServer.start_stdio()
        return 0
    end

    if !isnothing(args["flow"])
        return run_flow(args["flow"], args, project_root)
    end

    if !isnothing(cmd)
        if cmd == "serve"
            # Modo servidor WebSocket
            @info "Starting paipermc agent server..."
            AgentServer.start_server(
                host = args["host"],
                port = args["port"],
                key  = args["key"],
            )
            return 0

        elseif cmd == "status"
            return cmd_status(litellm_host, lit_host)

        elseif cmd == "models"
            return cmd_models(litellm_host, litellm_key)

        elseif cmd == "research"
            return run_flow("research", args, project_root)

        elseif cmd == "review"
            return run_flow("review", args, project_root)

        else
            # One-shot: enviar como mensaje al agente
            return run_oneshot(cmd, args, project_root)
        end
    end

    # Sin comando → REPL interactivo
    run_repl(args, project_root)
    return 0
end

# ── One-shot ─────────────────────────────────────────────────────────────────
function run_oneshot(prompt::String, args::Dict, project_root::String) :: Cint
    include("../cli/connection.jl")
    Connection.run_oneshot(
        prompt,
        project_root = project_root,
        model        = args["model"],
        verbose      = args["verbose"],
        no_confirm   = args["no-confirm"],
    )
    return 0
end

# ── REPL ─────────────────────────────────────────────────────────────────────
function run_repl(args::Dict, project_root::String) :: Nothing
    include("../cli/repl.jl")
    REPL_Module.start(
        project_root = project_root,
        model        = args["model"],
        verbose      = args["verbose"],
    )
end

# ── Flows ─────────────────────────────────────────────────────────────────────
function run_flow(flow::String, args::Dict, project_root::String) :: Cint
    @info "Running flow: $flow"
    # Los flows se implementan en Fase C
    println("Flow '$flow' — Fase C (coming soon)")
    return 0
end

# ── Comandos de información ───────────────────────────────────────────────────
function cmd_status(litellm_host::String, lit_host::String) :: Cint
    println("\npaipermc status\n")

    _check_service("LiteLLM", litellm_host * "/health")
    _check_service("literature-svc", lit_host * "/health")
    _check_service("Ollama", "http://100.64.0.22:11434/api/tags")

    println()
    return 0
end

function cmd_models(litellm_host::String, key::String) :: Cint
    using HTTP, JSON3
    try
        resp = HTTP.get(
            litellm_host * "/v1/models",
            ["Authorization" => "Bearer $key"];
            readtimeout = 10,
        )
        data = JSON3.read(resp.body)
        println("\nAvailable models:\n")
        for m in data["data"]
            println("  $(m["id"])")
        end
        println()
    catch e
        println("Error fetching models: $(sprint(showerror, e))")
        return 1
    end
    return 0
end

function _check_service(name::String, url::String)
    try
        using HTTP
        resp = HTTP.get(url; readtimeout=5, connect_timeout=3)
        resp.status < 400 ? println("  ● $name  OK") :
                            println("  ✗ $name  HTTP $(resp.status)")
    catch
        println("  ✗ $name  unreachable")
    end
end

# ── Resolución de project root ───────────────────────────────────────────────
function _resolve_project_root(explicit::Union{String,Nothing}) :: String
    !isnothing(explicit) && return abspath(explicit)

    # Buscar papermind.toml en directorio actual y padres
    dir = pwd()
    while true
        isfile(joinpath(dir, "papermind.toml")) && return dir
        parent = dirname(dir)
        parent == dir && break
        dir = parent
    end

    # Default: directorio actual
    pwd()
end

end # module Main
