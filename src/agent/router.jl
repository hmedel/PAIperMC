export route_agent, AgentRoute

# ── Resultado del routing ────────────────────────────────────────────────────
struct AgentRoute
    agent   :: String    # nombre del agente seleccionado
    model   :: String    # modelo a usar
    reason  :: String    # por qué se seleccionó
    swap    :: Bool      # true si cambió respecto al agente anterior
end

# ── Patrones de detección ────────────────────────────────────────────────────

# Entornos matemáticos LaTeX que activan el agente mathematician
const MATH_ENVS = r"\\begin\{(equation|align|gather|multline|cases|tikzcd|array|matrix)\}"i

# Patrones de mensaje que activan cada agente
const PATTERNS = [
    # Verificación formal — mayor prioridad
    (:lean,              r"lean|coq|formal\s+proof|verify\s+theorem|formali[sz]"i),

    # Revisión intelectual
    (:reviewer_style,    r"(style|grammar|english|clarity|writefull|paperpal)\b"i),
    (:reviewer_argument, r"(audit|referee|review\s+argument|logical\s+structure|claims?\b)"i),
    (:reviewer_gaps,     r"(gaps?|implicit\s+hyp|counterex|rigor|missing\s+step)"i),
    (:reviewer,          r"(review|referee|revisa|audita)\b"i),  # review genérico → full pipeline

    # Investigación exhaustiva
    (:researcher,        r"(research|exhaustive|survey\s+lit|map\s+lit|all\s+papers|estado\s+del\s+arte)"i),

    # Literatura
    (:literature,        r"(busca|search|find\s+paper|references?|cita[rs]?|arxiv|bibliography|bib)"i),

    # Matemáticas
    (:mathematician,     r"(ecuaci[oó]n|formula|theorem|lemma|proof|latex\s+error|\\begin\{)"i),
]

# ── Función principal de routing ─────────────────────────────────────────────
"""
Selecciona el agente más apropiado basándose en:
1. Override explícito (--model o /agent)
2. Archivo activo (*.bib → literature, *.lean → lean)
3. Entorno matemático en cursor
4. Contenido del mensaje
5. Default: writer
"""
function route_agent(
    message      :: String,
    active_file  :: Union{String, Nothing} = nothing,
    override     :: Union{String, Nothing} = nothing,
    prev_agent   :: String = "writer",
    in_math_env  :: Bool = false,
) :: AgentRoute

    # 1. Override explícito
    if !isnothing(override) && haskey(AGENTS, override)
        swap = override != prev_agent
        return AgentRoute(override, AGENTS[override].model, "explicit override", swap)
    end

    # 2. Archivo activo
    if !isnothing(active_file)
        if endswith(active_file, ".bib")
            return _route("literature", prev_agent, "active file is .bib")
        elseif endswith(active_file, ".lean")
            return _route("lean", prev_agent, "active file is .lean")
        end
    end

    # 3. Entorno matemático en cursor
    if in_math_env || occursin(MATH_ENVS, message)
        return _route("mathematician", prev_agent, "math environment detected")
    end

    # 4. Patrones en el mensaje
    for (agent_sym, pattern) in PATTERNS
        if occursin(pattern, message)
            agent_name = string(agent_sym) |> _normalize_agent
            return _route(agent_name, prev_agent, "pattern match: $pattern")
        end
    end

    # 5. Default
    _route("writer", prev_agent, "default")
end

# ── Helpers ──────────────────────────────────────────────────────────────────
function _route(agent::String, prev::String, reason::String) :: AgentRoute
    cfg  = get(AGENTS, agent, AGENTS["writer"])
    swap = agent != prev
    AgentRoute(agent, cfg.model, reason, swap)
end

function _normalize_agent(s::String) :: String
    # reviewer_style → reviewer-style
    replace(s, "_" => "-")
end
