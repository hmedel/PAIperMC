# Story: Exports en Paipermc.jl

## Estado: TODO

## Descripción

Agregar exports en `src/Paipermc.jl` para que las funciones públicas sean
accesibles sin calificar con `Paipermc.`.

## Criterio de aceptación

```julia
using Paipermc
route_agent("hello")           # sin Paipermc.
ConversationHistory("system")  # sin Paipermc.
chat_completion("writer", msgs)
```

## Implementación

Agregar en `src/Paipermc.jl` ANTES de los includes:

```julia
export route_agent, AgentRoute
export ConversationHistory, push_user!, push_assistant!, push_tool!,
       clear_history!, to_messages, history_summary, trim_to_limit!
export GatewayMessage, ToolCall, CompletionResponse
export chat_completion, stream_completion
export set_gateway_host!, set_gateway_key!, set_literature_host!
export load_config, find_project_root, ProjectConfig
export AGENTS, MODELS, resolve_model, ModelConfig, AgentConfig
export ConfirmAction, ConfirmRequest, ConfirmResponse, FileChange
export requires_confirmation, build_confirm_request
export WRITE_FILE, FETCH_PAPER, INDEX_PDF, LEAN_COMPILE, CALL_EXTERNAL, SEARCH_EXTERNAL
export AgentLoop, AgentLoopConfig, ClientCallbacks, run_loop!, stop_loop!
export read_file, write_file, list_files, search_literature
export improve_paragraph, check_latex
export build_tool_registry
export start_repl, julia_main, start_agent_server
```

## Test

```bash
julia --project=. -e '
using Paipermc
r = route_agent("mejora la intro")
println("OK: ", r.agent)
'
```
