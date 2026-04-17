# Story: WebSocket agent server real en :9000

## Estado: TODO (depende de 03-cli-main)

## Descripción

Implementar `start_agent_server()` real en `src/server/agent_server.jl`.
El stub actual solo imprime un mensaje. Necesita WebSocket real con:
- Autenticación por key
- Manejo de sesiones
- Streaming de tokens al cliente
- Confirmaciones bidireccionales

## Criterio de aceptación

```bash
# Terminal 1 — arrancar server
julia --project=. -e 'using Paipermc; start_agent_server()'

# Terminal 2 — conectar cliente de prueba
julia --project=. -e '
using WebSockets, JSON3
WebSockets.open("ws://localhost:9000") do ws
    send(ws, JSON3.write(Dict(
        "type"=>"session_start",
        "key"=>"sk-phaimat-agent",
        "project_root"=>pwd()
    )))
    resp = JSON3.read(receive(ws), Dict)
    println("Got: ", resp["type"])  # session_ready
end
'
```

## Protocolo completo

Ver ARCHITECTURE.md sección 10 para todos los tipos de mensaje.

## Dependencias Julia

```julia
using WebSockets, JSON3, UUIDs
```
