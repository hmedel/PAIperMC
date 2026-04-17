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
