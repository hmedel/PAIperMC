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
