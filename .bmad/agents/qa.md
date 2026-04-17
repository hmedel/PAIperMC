# QA Agent — paipermc

## Rol

Verifica que cada implementación funciona antes de marcar la story como done.
Ejecuta los smoke tests y reporta resultados precisos.

## Smoke tests por componente

### Paquete Julia base
```bash
julia --project=. -e 'using Paipermc; println("OK")'
```
Esperado: `OK` sin warnings críticos.

### Router
```bash
julia --project=. -e '
using Paipermc
@assert Paipermc.route_agent("mejora la intro").agent == "writer"
@assert Paipermc.route_agent("busca papers").agent == "literature"
@assert Paipermc.route_agent("verifica lean").agent == "lean"
@assert Paipermc.route_agent("check equation").agent == "mathematician"
println("Router OK")
'
```

### Gateway LiteLLM
```bash
julia --project=. -e '
using Paipermc
msgs = [Paipermc.GatewayMessage("user", "Reply with exactly: PAIPERMC_OK")]
resp = Paipermc.chat_completion("writer", msgs; max_tokens=20)
@assert occursin("PAIPERMC_OK", resp.content) "Got: $(resp.content)"
println("Gateway OK: $(resp.content)")
'
```

### Streaming
```bash
julia --project=. -e '
using Paipermc
msgs = [Paipermc.GatewayMessage("user", "Say hello in 5 words")]
buf = IOBuffer()
Paipermc.stream_completion("writer", msgs, t -> write(buf, t))
result = String(take!(buf))
@assert length(result) > 0 "No streaming output"
println("Streaming OK: $(length(result)) chars")
'
```

### Literature service
```bash
julia --project=. -e '
using Paipermc
result = Paipermc.search_literature(Dict("query"=>"contact geometry","sources"=>["local"]), pwd())
println("Literature OK: $(length(result)) chars")
'
```

### Servicios Docker
```bash
curl -sf http://localhost:8088/v1/models \
  -H "Authorization: Bearer sk-phaimat-local" | python3 -m json.tool | grep '"id"' | wc -l
# Esperado: 12
curl -sf http://localhost:8081/health
# Esperado: {"status":"ok",...}
```

## Criterios de aceptación por story

### exports.md — DONE cuando:
- `route_agent(...)` funciona SIN `Paipermc.` prefix

### repl.md — DONE cuando:
- `paipermc` arranca REPL
- tokens aparecen uno a uno en terminal
- `/agent writer` cambia el agente

### cli-main.md — DONE cuando:
- `paipermc "hello"` retorna respuesta
- `paipermc status` muestra estado de servicios
- `paipermc --help` muestra ayuda

### agent-server.md — DONE cuando:
- WebSocket en :9000 acepta conexiones
- `session_start` → `session_ready` funciona
- `user_message` → tokens streamed → `done` funciona
