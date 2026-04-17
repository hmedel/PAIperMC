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
