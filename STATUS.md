# paipermc — STATUS

> Última actualización: Fase B base completa
> Repo: https://github.com/hmedel/PAIperMC

---

## Estado por fase

### Fase A — Infraestructura xolotl COMPLETA

```
Ollama          http://100.64.0.22:11434   7 modelos
LiteLLM         http://100.64.0.22:8088   12 agentes configurados
literature-svc  http://100.64.0.22:8081   7 APIs académicas
Lean 4          ~/Projects/PAIperMC/paipermc/lean/   Mathlib4 compilado
```

Modelos Ollama disponibles:
- `qwen2.5:7b-instruct-q4_K_M`  — writer, reviewer-style
- `qwen2-math:7b-instruct`       — mathematician, reviewer-gaps
- `mistral-small:22b`            — literature, researcher, lean
- `deepseek-r1:14b`              — reviewer-argument
- `qwen3:8b`                     — fallback
- `nomic-embed-text:latest`      — embeddings
- `mistral-nemo:latest`          — disponible

Servicios systemd:
- `ollama.service`           — activo
- `paipermc-docker.service`  — activo (LiteLLM + literature-svc)

### Fase B — Paquete Julia FUNCIONAL (base)

```
using Paipermc        → compila limpio en Julia 1.12.6
chat_completion()     → LiteLLM → modelo → respuesta verificada
route_agent()         → routing automático funcional
ConversationHistory   → historial con trim funcional
load_config()         → papermind.toml funcional
```

Lo que FALTA en Fase B:
- [ ] `export` de funciones públicas en `Paipermc.jl`
- [ ] `start_repl()` conectado a LiteLLM con streaming real en terminal
- [ ] `julia_main()` funcional como CLI one-shot y subcomandos
- [ ] `start_agent_server()` WebSocket real en :9000
- [ ] `build_tool_registry()` con todas las tools conectadas
- [ ] `cli/connection.jl` — cliente WebSocket

### Fase C — Flows NO INICIADA

- [ ] `literature_flow` — 6 pasos discovery → tabla → BibTeX
- [ ] `review_flow`     — 3 modos reviewer
- [ ] `verify_flow`     — Lean 4 scaffold + gap analysis
- [ ] `research_flow`   — investigación exhaustiva

### Fase D — CLI compilado NO INICIADA

- [ ] PackageCompiler sysimage (~10 min)
- [ ] `install-ollintzin.sh` probado

### Fase E — Emacs NO INICIADA

- [ ] `paipermc-mode.el` — layout 3 paneles
- [ ] gptel apuntando a LiteLLM
- [ ] MCP proxy stdio ↔ WebSocket

---

## Verificación rápida del sistema

```bash
# En xolotl — verificar todo
curl http://localhost:8088/v1/models -H 'Authorization: Bearer sk-phaimat-local' | python3 -m json.tool | grep '"id"'
curl http://localhost:8081/health
julia --project=. -e 'using Paipermc; println("OK")'

# Inferencia real
julia --project=. -e '
using Paipermc
msgs = [Paipermc.GatewayMessage("user", "Say: PAIPERMC_OK")]
resp = Paipermc.chat_completion("writer", msgs; max_tokens=20)
println(resp.content)
'
```

---

## Variables de entorno (xolotl)

```bash
PAIPERMC_LITELLM_HOST=http://100.64.0.22:8088
PAIPERMC_LITELLM_KEY=sk-phaimat-local
PAIPERMC_LITERATURE_HOST=http://100.64.0.22:8081
PAIPERMC_AGENT_KEY=sk-phaimat-agent
PAIPERMC_AGENT_PORT=9000
```

---

## Estructura de archivos clave

```
~/Projects/PAIperMC/paipermc/
├── STATUS.md                   ← este archivo
├── ARCHITECTURE.md             ← especificación completa
├── Project.toml                ← dependencias Julia (correctas)
├── Manifest.toml               ← generado por Julia, no editar
├── build.jl                    ← PackageCompiler
├── precompile_paipermc.jl      ← tracing para sysimage
├── src/
│   ├── Paipermc.jl             ← entry point, todos los includes
│   ├── models/
│   │   ├── definitions.jl      ← MODELS, AGENTS dicts — FUNCIONAL
│   │   └── gateway.jl          ← chat_completion, stream_completion — FUNCIONAL
│   ├── agent/
│   │   ├── history.jl          ← ConversationHistory — FUNCIONAL
│   │   ├── router.jl           ← route_agent — FUNCIONAL
│   │   ├── confirmation.jl     ← ConfirmAction, ConfirmRequest — FUNCIONAL
│   │   └── loop.jl             ← AgentLoop, run_loop! — FUNCIONAL (stub server)
│   ├── project/
│   │   └── config.jl           ← load_config, find_project_root — FUNCIONAL
│   ├── tools/
│   │   ├── read_file.jl        ← FUNCIONAL
│   │   ├── write_file.jl       ← FUNCIONAL
│   │   ├── list_files.jl       ← FUNCIONAL
│   │   ├── search_literature.jl← FUNCIONAL (llama a literature-svc)
│   │   ├── improve_paragraph.jl← FUNCIONAL (llama a LiteLLM)
│   │   └── check_latex.jl      ← FUNCIONAL (llama a LiteLLM)
│   ├── server/
│   │   └── agent_server.jl     ← STUB — WebSocket pendiente
│   ├── cli/
│   │   ├── repl.jl             ← PARCIAL — streaming funciona, WebSocket pendiente
│   │   └── main.jl             ← PARCIAL — julia_main() básico
│   └── mcp/                    ← TODO — stubs
├── docker/
│   ├── docker-compose.yml      ← LiteLLM + literature-svc
│   └── litellm_config.yaml     ← 12 agentes configurados
└── scripts/
    ├── install-xolotl.sh       ← PROBADO Y FUNCIONAL
    └── install-ollintzin.sh    ← pendiente probar
```
