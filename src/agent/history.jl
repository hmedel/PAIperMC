using Dates, JSON3

export ConversationHistory, push_user!, push_assistant!, push_tool!,
       push_system!, to_messages, clear!, summary, trim_to_limit!

# ── Entrada del historial ────────────────────────────────────────────────────
struct HistoryEntry
    role      :: String
    content   :: String
    timestamp :: DateTime
    tool_name :: Union{String, Nothing}
end

# ── Historial de conversación ────────────────────────────────────────────────
mutable struct ConversationHistory
    entries       :: Vector{HistoryEntry}
    system_prompt :: String
    max_tokens    :: Int     # limite aproximado antes de trim
end

function ConversationHistory(system_prompt::String; max_tokens::Int = 24000)
    ConversationHistory(HistoryEntry[], system_prompt, max_tokens)
end

# ── Mutadores ────────────────────────────────────────────────────────────────
function push_user!(h::ConversationHistory, content::String)
    push!(h.entries, HistoryEntry("user", content, now(), nothing))
end

function push_assistant!(h::ConversationHistory, content::String)
    push!(h.entries, HistoryEntry("assistant", content, now(), nothing))
end

function push_tool!(h::ConversationHistory, tool_name::String, result::String)
    push!(h.entries, HistoryEntry("tool", result, now(), tool_name))
end

function push_system!(h::ConversationHistory, content::String)
    push!(h.entries, HistoryEntry("system", content, now(), nothing))
end

function clear!(h::ConversationHistory)
    empty!(h.entries)
end

# ── Convertir a formato de mensajes para la API ──────────────────────────────
function to_messages(h::ConversationHistory) :: Vector{Message}
    msgs = Message[]
    push!(msgs, Message("system", h.system_prompt))
    for e in h.entries
        if e.role == "tool"
            # Resultado de tool se incluye como mensaje user con contexto
            push!(msgs, Message("user", "[Tool result: $(e.tool_name)]\n$(e.content)"))
        else
            push!(msgs, Message(e.role, e.content))
        end
    end
    msgs
end

# ── Resumen del historial ────────────────────────────────────────────────────
function summary(h::ConversationHistory) :: String
    n_user      = count(e -> e.role == "user", h.entries)
    n_assistant = count(e -> e.role == "assistant", h.entries)
    n_tool      = count(e -> e.role == "tool", h.entries)
    "$(n_user) user / $(n_assistant) assistant / $(n_tool) tool calls"
end

# ── Trim por longitud aproximada de tokens ───────────────────────────────────
"""
Elimina entradas antiguas para mantener el historial dentro del límite.
Preserva siempre las últimas 4 entradas para no perder contexto inmediato.
Estimación: 1 token ≈ 4 caracteres.
"""
function trim_to_limit!(h::ConversationHistory)
    total_chars = sum(length(e.content) for e in h.entries; init=0)
    estimated_tokens = total_chars ÷ 4

    while estimated_tokens > h.max_tokens && length(h.entries) > 4
        popfirst!(h.entries)
        total_chars = sum(length(e.content) for e in h.entries; init=0)
        estimated_tokens = total_chars ÷ 4
    end
end

# ── Persistencia ─────────────────────────────────────────────────────────────
function save(h::ConversationHistory, path::String)
    data = Dict(
        "system_prompt" => h.system_prompt,
        "entries" => [Dict(
            "role"      => e.role,
            "content"   => e.content,
            "timestamp" => string(e.timestamp),
            "tool_name" => e.tool_name,
        ) for e in h.entries]
    )
    open(path, "w") do f
        JSON3.pretty(f, data)
    end
end

function load(path::String) :: ConversationHistory
    data = JSON3.read(read(path, String))
    h = ConversationHistory(data["system_prompt"])
    for e in data["entries"]
        push!(h.entries, HistoryEntry(
            e["role"],
            e["content"],
            DateTime(e["timestamp"]),
            get(e, "tool_name", nothing),
        ))
    end
    h
end
