#!/usr/bin/env bash
# Sobreescribe todos los archivos fuente con versiones limpias
# Sin módulos anidados, sin end huérfanos, sin conflictos de nombres
cd ~/Projects/PAIperMC/paipermc

# ── project/config.jl ────────────────────────────────────────────────────────
cat > src/project/config.jl << 'EOF'
# project/config.jl

struct ProjectConfig
    name         :: String
    main         :: String
    journal      :: String
    style        :: String
    language     :: String
    bib          :: String
    server_host  :: String
    server_port  :: Int
    server_key   :: String
    lean_dir     :: String
    sources      :: Vector{String}
end

function load_config(root::String) :: ProjectConfig
    toml_path = joinpath(root, "papermind.toml")
    isfile(toml_path) || return _default_config(root)
    cfg = TOML.parsefile(toml_path)
    p = get(cfg, "project",    Dict())
    s = get(cfg, "server",     Dict())
    l = get(cfg, "literature", Dict())
    f = get(cfg, "formal",     Dict())
    ProjectConfig(
        get(p, "name",     basename(root)),
        get(p, "main",     "main.tex"),
        get(p, "journal",  ""),
        get(p, "style",    ""),
        get(p, "language", "en"),
        get(l, "bib",      "refs.bib"),
        get(s, "host",     "100.64.0.22"),
        get(s, "port",     9000),
        get(s, "key",      "sk-phaimat-agent"),
        get(f, "lean_dir", ".paipermc/lean"),
        get(l, "sources",  ["local", "arxiv"]),
    )
end

function find_project_root(start::String = pwd()) :: String
    dir = abspath(start)
    while true
        isfile(joinpath(dir, "papermind.toml")) && return dir
        parent = dirname(dir)
        parent == dir && break
        dir = parent
    end
    start
end

function _default_config(root::String) :: ProjectConfig
    ProjectConfig(
        basename(root), "main.tex", "", "", "en", "refs.bib",
        "100.64.0.22", 9000, "sk-phaimat-agent",
        ".paipermc/lean", ["local", "arxiv"],
    )
end
EOF

# ── project/workspace.jl ─────────────────────────────────────────────────────
cat > src/project/workspace.jl << 'EOF'
# project/workspace.jl — stub
EOF

# ── project/scaffold.jl ──────────────────────────────────────────────────────
cat > src/project/scaffold.jl << 'EOF'
# project/scaffold.jl — stub
EOF

# ── models/definitions.jl ────────────────────────────────────────────────────
cat > src/models/definitions.jl << 'EOF'
# models/definitions.jl

struct ModelConfig
    name             :: String
    ollama_name      :: String
    provider         :: Symbol
    context_size     :: Int
    requires_confirm :: Bool
end

struct AgentConfig
    name          :: String
    model         :: String
    system_prompt :: String
    description   :: String
end

const MODELS = Dict{String,ModelConfig}(
    "writer"           => ModelConfig("writer",           "qwen2.5:7b-instruct-q4_K_M",  :local,     32768, false),
    "mathematician"    => ModelConfig("mathematician",    "qwen2-math:7b-instruct",        :local,     4096,  false),
    "literature"       => ModelConfig("literature",       "mistral-small:22b",             :local,     32768, false),
    "researcher"       => ModelConfig("researcher",       "mistral-small:22b",             :local,     32768, false),
    "reviewer-style"   => ModelConfig("reviewer-style",   "qwen2.5:7b-instruct-q4_K_M",  :local,     32768, false),
    "reviewer-argument"=> ModelConfig("reviewer-argument","deepseek-r1:14b",               :local,     32768, false),
    "reviewer-gaps"    => ModelConfig("reviewer-gaps",    "qwen2-math:7b-instruct",        :local,     4096,  false),
    "lean"             => ModelConfig("lean",             "mistral-small:22b",             :local,     32768, false),
    "embeddings"       => ModelConfig("embeddings",       "nomic-embed-text:latest",       :local,     8192,  false),
    "claude-opus-4-5"  => ModelConfig("claude-opus-4-5",  "claude-opus-4-5",              :anthropic, 200000,true),
    "claude-sonnet-4-5"=> ModelConfig("claude-sonnet-4-5","claude-sonnet-4-5",            :anthropic, 200000,true),
    "gemini-2.5-pro"   => ModelConfig("gemini-2.5-pro",   "gemini-2.5-pro",               :google,    1000000,true),
)

const AGENTS = Dict{String,AgentConfig}(
    "writer" => AgentConfig("writer","writer",
        "You are a scientific writing assistant for mathematical physics. Write precise technical English for journals such as JMP, Physica D, and SIAM. Preserve all LaTeX markup. Never alter equation content.",
        "Prose, structure, and style"),
    "mathematician" => AgentConfig("mathematician","mathematician",
        "You are a LaTeX mathematics expert for mathematical physics. Generate correct compilable LaTeX. Use standard notation from Abraham-Marsden, Arnold, and de León.",
        "LaTeX math and equations"),
    "literature" => AgentConfig("literature","literature",
        "You are a literature research agent. Search local index first, then external APIs. Return BibTeX entries and synthesis of findings.",
        "Literature search and BibTeX"),
    "researcher" => AgentConfig("researcher","researcher",
        "You are an exhaustive research agent. Analyze all project files to extract concepts, theorems, and gaps. Generate targeted search queries and structured reports.",
        "Exhaustive literature research"),
    "reviewer-style" => AgentConfig("reviewer-style","reviewer-style",
        "You are a scientific writing reviewer focused on style. Correct grammar, improve technical English, flag non-standard terminology.",
        "English style and clarity"),
    "reviewer-argument" => AgentConfig("reviewer-argument","reviewer-argument",
        "You are a rigorous referee. Audit logical structure section by section. Identify unsupported claims, circular reasoning, missing steps. Think carefully before reporting.",
        "Logical structure audit"),
    "reviewer-gaps" => AgentConfig("reviewer-gaps","reviewer-gaps",
        "You are a mathematical rigor reviewer. Find implicit hypotheses, boundary cases, counterexamples, notation clashes. Report with severity: critical/moderate/minor.",
        "Mathematical gaps"),
    "lean" => AgentConfig("lean","lean",
        "You are a Lean 4 formalization expert. Translate LaTeX theorems to Lean 4 using Mathlib4. Insert sorry for non-trivial steps with comments explaining what needs proof.",
        "Lean 4 formalization"),
)

function resolve_model(name::String) :: Union{ModelConfig,Nothing}
    get(MODELS, name, nothing)
end
EOF

# ── models/gateway.jl ────────────────────────────────────────────────────────
cat > src/models/gateway.jl << 'EOF'
# models/gateway.jl

const LITELLM_HOST = Ref{String}("http://100.64.0.22:8088")
const LITELLM_KEY  = Ref{String}("sk-phaimat-local")
const GATEWAY_TIMEOUT = 600

function set_gateway_host!(host::String)
    LITELLM_HOST[] = host
end

function set_gateway_key!(key::String)
    LITELLM_KEY[] = key
end

struct GatewayMessage
    role    :: String
    content :: String
end

struct ToolCall
    id        :: String
    name      :: String
    arguments :: Dict{String,Any}
end

struct CompletionResponse
    content    :: String
    tool_calls :: Vector{ToolCall}
    model      :: String
    usage      :: Dict{String,Int}
end

function chat_completion(
    model    :: String,
    messages :: Vector{GatewayMessage};
    tools       :: Vector{Dict} = Dict[],
    temperature :: Float64 = 0.7,
    max_tokens  :: Int = 4096,
) :: CompletionResponse

    body = Dict{String,Any}(
        "model"       => model,
        "messages"    => [Dict("role"=>m.role,"content"=>m.content) for m in messages],
        "stream"      => false,
        "temperature" => temperature,
        "max_tokens"  => max_tokens,
    )
    isempty(tools) || (body["tools"] = tools)

    headers = ["Authorization" => "Bearer $(LITELLM_KEY[])",
               "Content-Type"  => "application/json"]

    resp = HTTP.post(
        "$(LITELLM_HOST[])/v1/chat/completions",
        headers, JSON3.write(body);
        readtimeout=GATEWAY_TIMEOUT, connect_timeout=10,
    )

    data   = JSON3.read(resp.body)
    choice = data["choices"][1]
    msg    = choice["message"]

    tool_calls = ToolCall[]
    if haskey(msg, "tool_calls") && !isnothing(msg["tool_calls"])
        for tc in msg["tool_calls"]
            args = try JSON3.read(tc["function"]["arguments"], Dict{String,Any}) catch; Dict{String,Any}() end
            push!(tool_calls, ToolCall(string(tc["id"]), string(tc["function"]["name"]), args))
        end
    end

    content = get(msg, "content", nothing)
    content_str = isnothing(content) ? "" : string(content)
    usage = Dict{String,Int}(
        "prompt_tokens"     => get(get(data,"usage",Dict()),"prompt_tokens",0),
        "completion_tokens" => get(get(data,"usage",Dict()),"completion_tokens",0),
    )
    CompletionResponse(content_str, tool_calls, model, usage)
end

function stream_completion(
    model    :: String,
    messages :: Vector{GatewayMessage},
    on_token :: Function;
    tools       :: Vector{Dict} = Dict[],
    temperature :: Float64 = 0.7,
    max_tokens  :: Int = 4096,
) :: CompletionResponse

    body = Dict{String,Any}(
        "model"       => model,
        "messages"    => [Dict("role"=>m.role,"content"=>m.content) for m in messages],
        "stream"      => true,
        "temperature" => temperature,
        "max_tokens"  => max_tokens,
    )
    isempty(tools) || (body["tools"] = tools)
    headers = ["Authorization" => "Bearer $(LITELLM_KEY[])",
               "Content-Type"  => "application/json"]

    full_content = IOBuffer()

    HTTP.open("POST", "$(LITELLM_HOST[])/v1/chat/completions", headers;
              readtimeout=GATEWAY_TIMEOUT, connect_timeout=10) do io
        write(io, JSON3.write(body))
        HTTP.startread(io)
        while !eof(io)
            line = readline(io)
            isempty(line) && continue
            startswith(line, "data: ") || continue
            data_str = line[7:end]
            data_str == "[DONE]" && break
            chunk = try JSON3.read(data_str) catch; continue end
            haskey(chunk, "choices") || continue
            delta = get(chunk["choices"][1], "delta", Dict())
            token = get(delta, "content", nothing)
            if !isnothing(token) && !isempty(string(token))
                write(full_content, string(token))
                on_token(string(token))
            end
        end
    end

    CompletionResponse(String(take!(full_content)), ToolCall[], model,
                       Dict("prompt_tokens"=>0,"completion_tokens"=>0))
end
EOF

# ── models/anthropic.jl, selector.jl ─────────────────────────────────────────
echo "# models/anthropic.jl — stub" > src/models/anthropic.jl
echo "# models/selector.jl — stub"  > src/models/selector.jl

# ── agent/history.jl ─────────────────────────────────────────────────────────
cat > src/agent/history.jl << 'EOF'
# agent/history.jl

struct HistoryEntry
    role      :: String
    content   :: String
    timestamp :: DateTime
    tool_name :: Union{String,Nothing}
end

mutable struct ConversationHistory
    entries       :: Vector{HistoryEntry}
    system_prompt :: String
    max_tokens    :: Int
end

function ConversationHistory(system_prompt::String; max_tokens::Int=24000)
    ConversationHistory(HistoryEntry[], system_prompt, max_tokens)
end

function push_user!(h::ConversationHistory, content::String)
    push!(h.entries, HistoryEntry("user", content, now(), nothing))
end

function push_assistant!(h::ConversationHistory, content::String)
    push!(h.entries, HistoryEntry("assistant", content, now(), nothing))
end

function push_tool!(h::ConversationHistory, tool_name::String, result::String)
    push!(h.entries, HistoryEntry("tool", result, now(), tool_name))
end

function clear_history!(h::ConversationHistory)
    empty!(h.entries)
end

function to_messages(h::ConversationHistory) :: Vector{GatewayMessage}
    msgs = GatewayMessage[GatewayMessage("system", h.system_prompt)]
    for e in h.entries
        if e.role == "tool"
            push!(msgs, GatewayMessage("user", "[Tool: $(e.tool_name)]\n$(e.content)"))
        else
            push!(msgs, GatewayMessage(e.role, e.content))
        end
    end
    msgs
end

function history_summary(h::ConversationHistory) :: String
    n_u = count(e->e.role=="user",      h.entries)
    n_a = count(e->e.role=="assistant", h.entries)
    n_t = count(e->e.role=="tool",      h.entries)
    "$(n_u) user / $(n_a) assistant / $(n_t) tool"
end

function trim_to_limit!(h::ConversationHistory)
    total = sum(length(e.content) for e in h.entries; init=0)
    while total÷4 > h.max_tokens && length(h.entries) > 4
        total -= length(first(h.entries).content)
        popfirst!(h.entries)
    end
end
EOF

# ── agent/router.jl ──────────────────────────────────────────────────────────
cat > src/agent/router.jl << 'EOF'
# agent/router.jl

struct AgentRoute
    agent  :: String
    model  :: String
    reason :: String
    swap   :: Bool
end

const MATH_ENVS = r"\\begin\{(equation|align|gather|multline|cases|tikzcd)\}"i

const ROUTE_PATTERNS = [
    ("lean",              r"lean|coq|formal\s+proof|verify\s+theorem"i),
    ("reviewer-style",    r"\bstyle\b|grammar|clarity"i),
    ("reviewer-argument", r"audit|referee|logical\s+structure"i),
    ("reviewer-gaps",     r"\bgaps?\b|implicit\s+hyp|counterex"i),
    ("researcher",        r"exhaustive|survey|all\s+papers"i),
    ("literature",        r"busca|search|find\s+paper|references?|arxiv"i),
    ("mathematician",     r"ecuaci|formula|theorem|lemma|proof|\\begin"i),
]

function route_agent(
    message     :: String,
    active_file :: Union{String,Nothing} = nothing,
    override    :: Union{String,Nothing} = nothing,
    prev_agent  :: String = "writer",
    in_math_env :: Bool = false,
) :: AgentRoute

    if !isnothing(override) && haskey(AGENTS, override)
        return AgentRoute(override, AGENTS[override].model, "explicit", override!=prev_agent)
    end
    if !isnothing(active_file)
        endswith(active_file, ".bib")  && return _mk_route("literature",   prev_agent, "active .bib")
        endswith(active_file, ".lean") && return _mk_route("lean",          prev_agent, "active .lean")
    end
    (in_math_env || occursin(MATH_ENVS, message)) &&
        return _mk_route("mathematician", prev_agent, "math env")
    for (agent, pat) in ROUTE_PATTERNS
        occursin(pat, message) && return _mk_route(agent, prev_agent, "pattern")
    end
    _mk_route("writer", prev_agent, "default")
end

function _mk_route(agent::String, prev::String, reason::String) :: AgentRoute
    cfg = get(AGENTS, agent, AGENTS["writer"])
    AgentRoute(agent, cfg.model, reason, agent!=prev)
end
EOF

# ── agent/context.jl ─────────────────────────────────────────────────────────
echo "# agent/context.jl — stub" > src/agent/context.jl

# ── agent/confirmation.jl ────────────────────────────────────────────────────
cat > src/agent/confirmation.jl << 'EOF'
# agent/confirmation.jl

@enum ConfirmAction WRITE_FILE FETCH_PAPER INDEX_PDF LEAN_COMPILE CALL_EXTERNAL SEARCH_EXTERNAL

struct FileChange
    path :: String
    diff :: String
    size :: Int
end

struct ConfirmRequest
    id        :: String
    action    :: ConfirmAction
    message   :: String
    files     :: Vector{FileChange}
    metadata  :: Dict{String,Any}
end

struct ConfirmResponse
    request_id :: String
    answer     :: Symbol
end

function requires_confirmation(action::ConfirmAction) :: Bool
    action in (WRITE_FILE, FETCH_PAPER, INDEX_PDF, LEAN_COMPILE, CALL_EXTERNAL, SEARCH_EXTERNAL)
end

function build_confirm_request(action::ConfirmAction, message::String;
    files    :: Vector{FileChange}    = FileChange[],
    metadata :: Dict{String,Any}      = Dict{String,Any}(),
) :: ConfirmRequest
    ConfirmRequest(string(UUIDs.uuid4()), action, message, files, metadata)
end
EOF

# ── agent/loop.jl ────────────────────────────────────────────────────────────
cat > src/agent/loop.jl << 'EOF'
# agent/loop.jl

struct AgentLoopConfig
    session_id     :: String
    project_root   :: String
    model_override :: Union{String,Nothing}
    verbose        :: Bool
    no_confirm     :: Bool
end

struct ClientCallbacks
    on_token      :: Function
    on_tool_start :: Function
    on_tool_result:: Function
    on_agent_swap :: Function
    on_confirm    :: Function
    on_done       :: Function
    on_error      :: Function
end

mutable struct AgentLoop
    config        :: AgentLoopConfig
    history       :: ConversationHistory
    callbacks     :: ClientCallbacks
    active_agent  :: String
    tool_registry :: Dict{String,Function}
    running       :: Bool
end

function AgentLoop(config::AgentLoopConfig, callbacks::ClientCallbacks, tools::Dict{String,Function}) :: AgentLoop
    initial = something(config.model_override, "writer")
    haskey(AGENTS, initial) || (initial = "writer")
    history = ConversationHistory(AGENTS[initial].system_prompt)
    AgentLoop(config, history, callbacks, initial, tools, false)
end

function run_loop!(loop::AgentLoop, user_message::String)
    loop.running = true
    try
        route = route_agent(user_message, nothing, loop.config.model_override, loop.active_agent)
        if route.swap
            loop.callbacks.on_agent_swap(loop.active_agent, route.agent, 4)
            haskey(AGENTS, route.agent) &&
                (loop.history.system_prompt = AGENTS[route.agent].system_prompt)
            loop.active_agent = route.agent
        end

        push_user!(loop.history, user_message)
        trim_to_limit!(loop.history)

        for _ in 1:10
            loop.running || break
            messages = to_messages(loop.history)
            response = stream_completion(
                route.model, messages,
                token -> loop.callbacks.on_token(token);
            )
            push_assistant!(loop.history, response.content)

            isempty(response.tool_calls) && (loop.callbacks.on_done(); break)

            for tc in response.tool_calls
                _exec_tool!(loop, tc)
                loop.running || break
            end
        end
    catch e
        loop.callbacks.on_error(sprint(showerror, e))
    finally
        loop.running = false
    end
end

function stop_loop!(loop::AgentLoop)
    loop.running = false
end

function _exec_tool!(loop::AgentLoop, tc::ToolCall)
    fn = get(loop.tool_registry, tc.name, nothing)
    isnothing(fn) && (push_tool!(loop.history, tc.name, "Error: unknown tool"); return)

    loop.callbacks.on_tool_start(tc.name, tc.arguments)

    action = _tool_action(tc.name)
    if !isnothing(action) && !loop.config.no_confirm
        req  = build_confirm_request(action, "paipermc wants to run: $(tc.name)", metadata=tc.arguments)
        resp = loop.callbacks.on_confirm(req)
        resp.answer in (:no, :skip) && (push_tool!(loop.history, tc.name, "skipped"); return)
    end

    result = try fn(tc.arguments, loop.config.project_root) catch e; "Error: $(sprint(showerror,e))" end
    push_tool!(loop.history, tc.name, string(result))
    summary = length(string(result)) > 120 ? string(result)[1:120]*"…" : string(result)
    loop.callbacks.on_tool_result(tc.name, summary)
end

function _tool_action(name::String) :: Union{ConfirmAction,Nothing}
    name == "write_file"    && return WRITE_FILE
    name == "fetch_paper"   && return FETCH_PAPER
    name == "lean_compile"  && return LEAN_COMPILE
    name == "call_external" && return CALL_EXTERNAL
    nothing
end
EOF

# ── tools/registry.jl ────────────────────────────────────────────────────────
cat > src/tools/registry.jl << 'EOF'
# tools/registry.jl

const TOOL_SPECS = Dict[]   # populated after tool functions are defined

function build_tool_registry(project_root::String) :: Dict{String,Function}
    Dict{String,Function}(
        "read_file"         => (args,root) -> read_file(args, root),
        "search_literature" => (args,root) -> search_literature(args, root),
    )
end
EOF

# ── tools/read_file.jl ───────────────────────────────────────────────────────
cat > src/tools/read_file.jl << 'EOF'
# tools/read_file.jl

function read_file(args::Dict, project_root::String) :: String
    path = get(args, "path", "")
    isempty(path) && return "Error: path is required"
    full = normpath(joinpath(project_root, path))
    startswith(full, project_root) || return "Error: path outside project root"
    isfile(full) || return "Error: file not found: $path"
    content = read(full, String)
    lines   = split(content, '\n')
    n       = length(lines)
    numbered = join(["$(lpad(i,4))  $(lines[i])" for i in eachindex(lines)], '\n')
    length(numbered) > 32000 && (numbered = numbered[1:32000]*"\n[... truncated ...]")
    "[File: $path ($n lines)]\n$numbered"
end
EOF

# ── tools/write_file.jl ──────────────────────────────────────────────────────
cat > src/tools/write_file.jl << 'EOF'
# tools/write_file.jl

function write_file(args::Dict, project_root::String) :: String
    path    = get(args, "path", "")
    content = get(args, "content", "")
    mode    = get(args, "mode", "overwrite")
    isempty(path) && return "Error: path is required"
    full = normpath(joinpath(project_root, path))
    startswith(full, project_root) || return "Error: path outside project root"
    mkpath(dirname(full))
    tmp = full * ".tmp.$(getpid())"
    try
        if mode == "append" && isfile(full)
            write(tmp, read(full, String) * content)
        else
            write(tmp, content)
        end
        mv(tmp, full; force=true)
    catch e
        rm(tmp; force=true)
        return "Error: $(sprint(showerror, e))"
    end
    "Written: $path ($(length(content)) bytes)"
end
EOF

# ── tools/list_files.jl ──────────────────────────────────────────────────────
cat > src/tools/list_files.jl << 'EOF'
# tools/list_files.jl

function list_files(args::Dict, project_root::String) :: String
    subpath = get(args, "path", "")
    pattern = get(args, "pattern", "*")
    base = isempty(subpath) ? project_root : normpath(joinpath(project_root, subpath))
    startswith(base, project_root) || return "Error: path outside project root"
    isdir(base) || return "Error: not a directory: $subpath"
    files = String[]
    for (root, dirs, names) in walkdir(base)
        filter!(d -> !startswith(d,"."), dirs)
        for f in names
            rel = relpath(joinpath(root,f), project_root)
            push!(files, rel)
        end
    end
    pattern != "*" && filter!(f->endswith(f, replace(pattern,"*"=>"")), files)
    sort!(files)
    isempty(files) && return "No files found"
    join(files, "\n")
end
EOF

# ── tools/search_literature.jl ───────────────────────────────────────────────
cat > src/tools/search_literature.jl << 'EOF'
# tools/search_literature.jl

const LITERATURE_SVC = Ref{String}("http://100.64.0.22:8081")

function set_literature_host!(host::String)
    LITERATURE_SVC[] = host
end

function search_literature(args::Dict, project_root::String) :: String
    query   = get(args, "query", "")
    sources = get(args, "sources", ["local"])
    n       = get(args, "n", 10)
    isempty(query) && return "Error: query is required"
    body = Dict("query"=>query, "sources"=>sources, "max_results"=>n)
    try
        resp = HTTP.post(
            "$(LITERATURE_SVC[])/search",
            ["Content-Type"=>"application/json"],
            JSON3.write(body); readtimeout=30,
        )
        data = JSON3.read(resp.body)
        results = data["results"]
        isempty(results) && return "No results for: $query"
        buf = IOBuffer()
        println(buf, "Found $(data["total"]) results for: $query\n")
        for (i,r) in enumerate(results)
            println(buf, "[$i] $(get(r,"title","?"))")
            println(buf, "    $(join(get(r,"authors",[]),"," ))")
            yr = get(r,"year",nothing); !isnothing(yr) && println(buf,"    Year: $yr")
            doi = get(r,"doi",nothing); !isnothing(doi) && println(buf,"    DOI: $doi")
            println(buf)
        end
        String(take!(buf))
    catch e
        "Error: $(sprint(showerror,e))"
    end
end
EOF

# ── tools/improve_paragraph.jl ───────────────────────────────────────────────
cat > src/tools/improve_paragraph.jl << 'EOF'
# tools/improve_paragraph.jl

function improve_paragraph(args::Dict, project_root::String) :: String
    text = get(args, "text", "")
    isempty(text) && return "Error: text is required"
    msgs = [GatewayMessage("system","Improve the style of this LaTeX paragraph. Preserve math. Return only the improved paragraph."),
            GatewayMessage("user", text)]
    try
        resp = chat_completion("reviewer-style", msgs; temperature=0.3, max_tokens=2048)
        resp.content
    catch e
        "Error: $(sprint(showerror,e))"
    end
end
EOF

# ── tools/check_latex.jl ─────────────────────────────────────────────────────
cat > src/tools/check_latex.jl << 'EOF'
# tools/check_latex.jl

function check_latex(args::Dict, project_root::String) :: String
    latex = get(args, "latex", "")
    isempty(latex) && return "Error: latex is required"
    msgs = [GatewayMessage("system","Check if this LaTeX is correct. Reply: STATUS: valid|invalid\nERRORS: ...\nCORRECTED:\n..."),
            GatewayMessage("user", latex)]
    try
        resp = chat_completion("mathematician", msgs; temperature=0.1, max_tokens=2048)
        resp.content
    catch e
        "Error: $(sprint(showerror,e))"
    end
end
EOF

# ── tools restantes (stubs) ───────────────────────────────────────────────────
echo "# fetch_paper.jl — stub"   > src/tools/fetch_paper.jl
echo "# call_external.jl — stub" > src/tools/call_external.jl

# ── server stubs ──────────────────────────────────────────────────────────────
echo "# auth.jl — stub"    > src/server/auth.jl
echo "# session.jl — stub" > src/server/session.jl

# ── server/agent_server.jl ────────────────────────────────────────────────────
cat > src/server/agent_server.jl << 'EOF'
# server/agent_server.jl — stub WebSocket server

function start_agent_server(; host="0.0.0.0", port=9000, key="sk-phaimat-agent")
    @info "paipermc agent server starting on ws://$(host):$(port)"
    # Full implementation in Phase B
    @info "Agent server stub — WebSocket implementation pending"
end
EOF

# ── mcp stubs ─────────────────────────────────────────────────────────────────
echo "# mcp/protocol.jl — stub" > src/mcp/protocol.jl
echo "# mcp/proxy.jl — stub"    > src/mcp/proxy.jl
echo "# mcp/server.jl — stub"   > src/mcp/server.jl

# ── cli stubs ─────────────────────────────────────────────────────────────────
echo "# cli/renderer.jl — stub"  > src/cli/renderer.jl
echo "# cli/connection.jl — stub"> src/cli/connection.jl
echo "# cli/commands.jl — stub"  > src/cli/commands.jl

# ── cli/repl.jl ──────────────────────────────────────────────────────────────
cat > src/cli/repl.jl << 'EOF'
# cli/repl.jl

function start_repl(; project_root=pwd(), model=nothing, verbose=false)
    project_name = find_project_root(project_root) |> basename
    println("\npaipermc v0.1.0 — $project_name")
    println("Type your message or /help for commands.\n")

    active_agent = "writer"

    while true
        print("\033[36mpaiper\033[0m [\033[2m$active_agent\033[0m] $project_name > ")
        flush(stdout)
        line = try readline(stdin) catch; nothing end
        (isnothing(line) || strip(line) in ("", "/exit", "/quit")) && break

        line = strip(line)
        if startswith(line, "/agent ")
            active_agent = split(line)[2]
            println("Agent: $active_agent")
            continue
        end
        if line == "/help"
            println("/agent <n>  /exit")
            continue
        end

        println("\n\033[2m[sending to $active_agent...]\033[0m")
        try
            agent_cfg = get(AGENTS, active_agent, AGENTS["writer"])
            msgs = [GatewayMessage("system", agent_cfg.system_prompt),
                    GatewayMessage("user", line)]
            println()
            stream_completion(agent_cfg.model, msgs, token -> (print(token); flush(stdout)))
            println("\n")
        catch e
            println("\033[31mError: $(sprint(showerror,e))\033[0m\n")
        end
    end
    println("\nGoodbye.")
end
EOF

# ── cli/main.jl ───────────────────────────────────────────────────────────────
cat > src/cli/main.jl << 'EOF'
# cli/main.jl

function julia_main() :: Cint
    isempty(ARGS) && (start_repl(); return 0)

    if "--help" in ARGS || "-h" in ARGS
        println("""
paipermc v0.1.0

Usage:
  paipermc                     interactive REPL
  paipermc \"<prompt>\"          one-shot
  paipermc serve               start agent server
  paipermc status              check services
  paipermc --help
""")
        return 0
    end

    if ARGS[1] == "serve"
        start_agent_server()
        return 0
    end

    if ARGS[1] == "status"
        println("Checking xolotl services...")
        try
            r = HTTP.get("$(LITELLM_HOST[])/v1/models",
                         ["Authorization"=>"Bearer $(LITELLM_KEY[])"];
                         readtimeout=5)
            r.status < 400 ? println("  ● LiteLLM OK") : println("  ✗ LiteLLM $(r.status)")
        catch
            println("  ✗ LiteLLM unreachable")
        end
        try
            r = HTTP.get("$(LITERATURE_SVC[])/health"; readtimeout=5)
            r.status < 400 ? println("  ● literature-svc OK") : println("  ✗ literature-svc")
        catch
            println("  ✗ literature-svc unreachable")
        end
        return 0
    end

    # One-shot prompt
    prompt = join(ARGS, " ")
    route  = route_agent(prompt)
    agent  = get(AGENTS, route.agent, AGENTS["writer"])
    msgs   = [GatewayMessage("system", agent.system_prompt),
              GatewayMessage("user",   prompt)]
    try
        stream_completion(agent.model, msgs, token -> (print(token); flush(stdout)))
        println()
    catch e
        println("Error: $(sprint(showerror, e))")
        return 1
    end
    return 0
end
EOF

echo "Todos los archivos reescritos."
