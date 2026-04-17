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
