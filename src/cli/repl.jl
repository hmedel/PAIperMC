# cli/repl.jl

function start_repl(; project_root=pwd(), model=nothing, verbose=false)
    project_name = find_project_root(project_root) |> basename
    println("\npaipermc v0.1.0 — $project_name")
    println("Type your message or /help for commands.\n")

    active_agent = "writer"

    while true
        print("\033[36mpaiper\033[0m [\033[2m$active_agent\033[0m] $project_name > ")
        flush(stdout)
        line = try readline(stdin) catch; nothing end
        (isnothing(line) || strip(line) in ("", "/exit", "/quit")) && break

        line = strip(line)
        if startswith(line, "/agent ")
            active_agent = split(line)[2]
            println("Agent: $active_agent")
            continue
        end
        if line == "/help"
            println("/agent <n>  /exit")
            continue
        end

        println("\n\033[2m[sending to $active_agent...]\033[0m")
        try
            agent_cfg = get(AGENTS, active_agent, AGENTS["writer"])
            msgs = [GatewayMessage("system", agent_cfg.system_prompt),
                    GatewayMessage("user", line)]
            println()
            stream_completion(agent_cfg.model, msgs, token -> (print(token); flush(stdout)))
            println("\n")
        catch e
            println("\033[31mError: $(sprint(showerror,e))\033[0m\n")
        end
    end
    println("\nGoodbye.")
end
