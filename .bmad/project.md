# paipermc — BMAD Project Context

## Lo que es este proyecto

CLI + servidor de IA para escribir papers científicos en LaTeX.
Arquitectura: cliente Julia (CLI/Emacs) ↔ WebSocket ↔ agent server Julia en xolotl ↔ LiteLLM ↔ Ollama.

Análogo a claude-code pero especializado en física matemática y LaTeX.

## Documentos de referencia

- `STATUS.md`       — estado actual, qué funciona, qué falta (LEE ESTO PRIMERO)
- `ARCHITECTURE.md` — especificación completa del sistema
- `Project.toml`    — dependencias Julia

## Contexto técnico crítico

**Julia 1.12.6** corre en xolotl. Estructura de módulo PLANA — todas las
funciones en el namespace `Paipermc` directamente, sin submódulos. Esta
decisión fue tomada para evitar problemas de imports relativos.

**No usar** `module X ... end` dentro de los archivos `src/`. Todo va
directamente en el namespace `Paipermc`.

**Funciones públicas** deben calificarse como `Paipermc.nombre()` hasta que
se agreguen exports. Próxima tarea: agregar `export` en `src/Paipermc.jl`.

## Infraestructura en xolotl (ya lista, no tocar)

```
LiteLLM  :8088  — 12 agentes, OpenAI-compatible
lit-svc  :8081  — literature-svc FastAPI
Ollama   :11434 — 7 modelos
Lean 4   ~/Projects/PAIperMC/paipermc/lean/
```

Todos los servicios arrancan con el sistema via systemd/Docker.

## Convenciones de código

- Julia idiomático: funciones en lugar de métodos donde sea posible
- Nombres de funciones: snake_case
- Structs: PascalCase
- Archivos de tools: cada archivo define UNA función principal con el mismo nombre del archivo
- Stubs: comentario `# stub` al inicio, implementar en fase posterior
- Tests: `test/` con archivos `test_*.jl`

## Comandos útiles en xolotl

```bash
# Verificar que el paquete compila
julia --project=. -e 'using Paipermc; println("OK")'

# Inferencia real
julia --project=. -e '
using Paipermc
msgs = [Paipermc.GatewayMessage("user", "hello")]
Paipermc.stream_completion("writer", msgs, t -> print(t))
println()
'

# Ver logs de LiteLLM
docker logs -f paipermc-litellm

# Ver logs de literature-svc
docker logs -f paipermc-literature

# Reiniciar servicios Docker
cd ~/Projects/PAIperMC/paipermc/docker
docker compose restart

# Estado de servicios
systemctl status paipermc-docker ollama
```

## Flujo de trabajo git

```bash
# Después de cada cambio que funciona
git add -A
git commit -m "tipo: descripción breve"
git push origin main
```

Tipos de commit: `feat`, `fix`, `refactor`, `test`, `docs`
