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
