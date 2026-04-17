# Story: REPL funcional con streaming

## Estado: TODO (depende de 01-exports)

## Descripción

`start_repl()` en `src/cli/repl.jl` ya tiene la estructura básica pero el
streaming no está conectado al WebSocket. En esta fase, conectar directamente
a LiteLLM sin WebSocket (el WebSocket viene en la story del agent server).

## Criterio de aceptación

```bash
julia --project=. -e 'using Paipermc; start_repl()'
# Muestra prompt
# Acepta input
# Streams respuesta token a token
# /agent cambia agente
# /exit sale limpio
```

## Implementación

`start_repl()` ya existe en `src/cli/repl.jl`. El bucle principal llama a
`stream_completion` directamente — sin WebSocket por ahora.

La función `stream_completion` ya funciona. Solo hay que conectarla al loop
del REPL correctamente y manejar el historial de conversación.

Patrón a seguir:
```julia
history = ConversationHistory(AGENTS[active_agent].system_prompt)
push_user!(history, line)
msgs = to_messages(history)
response_buf = IOBuffer()
stream_completion(AGENTS[active_agent].model, msgs,
    token -> (print(token); flush(stdout); write(response_buf, token)))
push_assistant!(history, String(take!(response_buf)))
println()
```

## Test

```bash
# Test no interactivo — verifica que no crashea
echo "hello\n/exit" | julia --project=. -e 'using Paipermc; start_repl()'
```
