module Gateway

using HTTP, JSON3, Logging
using ..Definitions

export chat_completion, stream_completion, embed

# ── Configuración ────────────────────────────────────────────────────────────
const DEFAULT_HOST = Ref{String}("http://100.64.0.22:8088")
const DEFAULT_KEY  = Ref{String}("sk-phaimat-local")
const TIMEOUT      = 600  # segundos — modelos locales pueden tardar

function set_host!(host::String)
    DEFAULT_HOST[] = host
end

function set_key!(key::String)
    DEFAULT_KEY[] = key
end

# ── Tipos ────────────────────────────────────────────────────────────────────
struct Message
    role    :: String
    content :: String
end

struct ToolCall
    id       :: String
    name     :: String
    arguments :: Dict{String,Any}
end

struct CompletionResponse
    content    :: String
    tool_calls :: Vector{ToolCall}
    model      :: String
    usage      :: Dict{String,Int}
end

# ── Chat completion (no streaming) ───────────────────────────────────────────
function chat_completion(
    model    :: String,
    messages :: Vector{Message};
    tools    :: Vector{Dict} = Dict[],
    temperature :: Float64 = 0.7,
    max_tokens  :: Int = 4096,
) :: CompletionResponse

    body = Dict(
        "model"       => model,
        "messages"    => [Dict("role" => m.role, "content" => m.content) for m in messages],
        "stream"      => false,
        "temperature" => temperature,
        "max_tokens"  => max_tokens,
    )
    isempty(tools) || (body["tools"] = tools)

    headers = [
        "Authorization" => "Bearer $(DEFAULT_KEY[])",
        "Content-Type"  => "application/json",
    ]

    resp = HTTP.post(
        "$(DEFAULT_HOST[])/v1/chat/completions",
        headers,
        JSON3.write(body);
        readtimeout = TIMEOUT,
        connect_timeout = 10,
    )

    data = JSON3.read(resp.body)

    # Extraer tool calls si existen
    tool_calls = ToolCall[]
    choice = data["choices"][1]
    msg = choice["message"]

    if haskey(msg, "tool_calls") && !isnothing(msg["tool_calls"])
        for tc in msg["tool_calls"]
            args = try
                JSON3.read(tc["function"]["arguments"], Dict{String,Any})
            catch
                Dict{String,Any}()
            end
            push!(tool_calls, ToolCall(
                string(tc["id"]),
                string(tc["function"]["name"]),
                args,
            ))
        end
    end

    content = get(msg, "content", "") |> string
    usage   = Dict{String,Int}(
        "prompt_tokens"     => get(get(data, "usage", Dict()), "prompt_tokens", 0),
        "completion_tokens" => get(get(data, "usage", Dict()), "completion_tokens", 0),
    )

    CompletionResponse(content, tool_calls, model, usage)
end

# ── Stream completion (genera tokens a medida que llegan) ────────────────────
"""
Llama al modelo en modo streaming. Invoca `on_token(chunk::String)` por cada
fragmento recibido. Retorna el contenido completo al finalizar.
"""
function stream_completion(
    model    :: String,
    messages :: Vector{Message},
    on_token :: Function;
    tools       :: Vector{Dict} = Dict[],
    temperature :: Float64 = 0.7,
    max_tokens  :: Int = 4096,
) :: CompletionResponse

    body = Dict(
        "model"       => model,
        "messages"    => [Dict("role" => m.role, "content" => m.content) for m in messages],
        "stream"      => true,
        "temperature" => temperature,
        "max_tokens"  => max_tokens,
    )
    isempty(tools) || (body["tools"] = tools)

    headers = [
        "Authorization" => "Bearer $(DEFAULT_KEY[])",
        "Content-Type"  => "application/json",
    ]

    full_content  = IOBuffer()
    tool_calls    = ToolCall[]

    HTTP.open("POST", "$(DEFAULT_HOST[])/v1/chat/completions", headers;
              readtimeout = TIMEOUT, connect_timeout = 10) do io
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

    content = String(take!(full_content))
    usage   = Dict{String,Int}("prompt_tokens" => 0, "completion_tokens" => 0)
    CompletionResponse(content, tool_calls, model, usage)
end

# ── Embeddings ───────────────────────────────────────────────────────────────
function embed(text::String) :: Vector{Float32}
    body = Dict("model" => "embeddings", "input" => text)
    headers = [
        "Authorization" => "Bearer $(DEFAULT_KEY[])",
        "Content-Type"  => "application/json",
    ]
    resp = HTTP.post(
        "$(DEFAULT_HOST[])/v1/embeddings",
        headers,
        JSON3.write(body);
        readtimeout = 30,
    )
    data = JSON3.read(resp.body)
    Float32.(data["data"][1]["embedding"])
end

end # module
