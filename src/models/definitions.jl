export ModelConfig, AgentConfig, AGENTS, MODELS, resolve_model

# ── Configuración de modelo ──────────────────────────────────────────────────
struct ModelConfig
    name         :: String   # alias usado en la API (ej. "writer")
    ollama_name  :: String   # nombre real en Ollama (ej. "qwen2.5:7b-instruct-q4_K_M")
    provider     :: Symbol   # :local | :anthropic | :google
    context_size :: Int      # tokens de contexto máximo
    requires_confirm :: Bool # true para APIs externas
end

# ── Modelos disponibles en xolotl ────────────────────────────────────────────
const MODELS = Dict{String, ModelConfig}(

    # Locales via LiteLLM
    "writer" => ModelConfig(
        "writer", "qwen2.5:7b-instruct-q4_K_M",
        :local, 32768, false
    ),
    "mathematician" => ModelConfig(
        "mathematician", "qwen2-math:7b-instruct",
        :local, 4096, false
    ),
    "literature" => ModelConfig(
        "literature", "mistral-small:22b",
        :local, 32768, false
    ),
    "researcher" => ModelConfig(
        "researcher", "mistral-small:22b",
        :local, 32768, false
    ),
    "reviewer-style" => ModelConfig(
        "reviewer-style", "qwen2.5:7b-instruct-q4_K_M",
        :local, 32768, false
    ),
    "reviewer-argument" => ModelConfig(
        "reviewer-argument", "deepseek-r1:14b",
        :local, 32768, false
    ),
    "reviewer-gaps" => ModelConfig(
        "reviewer-gaps", "qwen2-math:7b-instruct",
        :local, 4096, false
    ),
    "lean" => ModelConfig(
        "lean", "mistral-small:22b",
        :local, 32768, false
    ),
    "embeddings" => ModelConfig(
        "embeddings", "nomic-embed-text:latest",
        :local, 8192, false
    ),

    # Externos — requieren confirmación
    "claude-opus-4-5" => ModelConfig(
        "claude-opus-4-5", "claude-opus-4-5",
        :anthropic, 200000, true
    ),
    "claude-sonnet-4-5" => ModelConfig(
        "claude-sonnet-4-5", "claude-sonnet-4-5",
        :anthropic, 200000, true
    ),
    "gemini-2.5-pro" => ModelConfig(
        "gemini-2.5-pro", "gemini-2.5-pro",
        :google, 1000000, true
    ),
)

# ── Configuración de agente ──────────────────────────────────────────────────
struct AgentConfig
    name         :: String
    model        :: String        # key en MODELS
    system_prompt :: String
    description  :: String
end

const AGENTS = Dict{String, AgentConfig}(

    "writer" => AgentConfig(
        "writer", "writer",
        """You are a scientific writing assistant for mathematical physics and applied
mathematics. You write precise technical English suitable for journals such as
JMP, Physica D, and SIA Preserve all LaTeX markup. When suggesting edits,
return valid compilable LaTeX. Never alter equation content — only surrounding
prose. When you need to read files or search for references, use the available
tools. Think step by step before proposing any change.""",
        "Prose, structure, and style for scientific papers"
    ),

    "mathematician" => AgentConfig(
        "mathematician", "mathematician",
        """You are a LaTeX mathematics expert for mathematical physics: symplectic
geometry, contact geometry, stochastic Hamiltonian systems, statistical
mechanics. Generate correct compilable LaTeX. Verify that all math environments
are properly opened and closed. Use standard notation from Abraham-Marsden,
Arnold, and de León. When checking a document, read the full file before
commenting.""",
        "LaTeX math, equations, and notation"
    ),

    "literature" => AgentConfig(
        "literature", "literature",
        """You are a literature research agent for mathematical physics. Search the
local paper index first, then external APIs if needed. Respond with: a short
synthesis of findings, complete BibTeX entries ready to paste into refs.bib,
and suggested search terms for deeper exploration. Always verify that BibTeX
keys are unique with respect to the project refs.bib.""",
        "Literature search, synthesis, and BibTeX generation"
    ),

    "researcher" => AgentConfig(
        "researcher", "researcher",
        """You are an exhaustive research agent for mathematical physics. Given a
project, you analyze all source files to extract core concepts, named theorems,
methods, and open questions. You generate targeted search queries, identify
gaps in the bibliography, and produce structured reports organized by relevance.
Be systematic and thorough. Always read all project files before reporting.""",
        "Exhaustive literature research and gap analysis"
    ),

    "reviewer-style" => AgentConfig(
        "reviewer-style", "reviewer-style",
        """You are a scientific writing reviewer focused on style and clarity. Correct
grammar, improve technical English, flag non-standard terminology for the target
journal, and suggest paragraph-level rewrites. Be specific: cite the exact
phrase and provide a concrete alternative. Do not alter mathematical content.""",
        "English style, grammar, and journal conventions"
    ),

    "reviewer-argument" => AgentConfig(
        "reviewer-argument", "reviewer-argument",
        """You are a rigorous referee for mathematical physics papers. Audit the logical
structure section by section. Identify: unsupported claims, circular reasoning,
missing intermediate steps, weak transitions, and mismatches between abstract
and conclusions. Think through each argument carefully before reporting. Provide
severity: critical / moderate / minor.""",
        "Logical structure audit and argument analysis"
    ),

    "reviewer-gaps" => AgentConfig(
        "reviewer-gaps", "reviewer-gaps",
        """You are a mathematical rigor reviewer. Focus on: implicit hypotheses in
theorems, boundary cases not considered, possible counterexamples, notation
that clashes with established conventions (Abraham-Marsden, Arnold), and steps
that require additional justification. Report as a structured list with
severity: critical / moderate / minor.""",
        "Mathematical gaps, implicit assumptions, and counterexamples"
    ),

    "lean" => AgentConfig(
        "lean", "lean",
        """You are a Lean 4 formalization expert for mathematical physics. You translate
LaTeX theorem statements and proofs into valid Lean 4 syntax using Mathlib4.
For each non-trivial proof step, insert a `sorry` placeholder with a comment
explaining what needs to be proved. After compilation errors, translate each
error into human-readable language explaining what is missing in the original
proof.""",
        "Lean 4 formalization and proof gap analysis"
    ),
)

"""
Resolve a model name or alias to a Model
Returns nothing if not found.
"""
function resolve_model(name::String) :: Union{ModelConfig, Nothing}
    get(MODELS, name, nothing)
end
