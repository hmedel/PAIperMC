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
