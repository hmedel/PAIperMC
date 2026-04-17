# paipermc — Guía BMAD para claude-code

## Cómo usar BMAD en este proyecto

### Arranque rápido

Cuando abras claude-code en xolotl, dale este contexto inicial:

```
Lee STATUS.md y .bmad/project.md para entender el estado actual del proyecto.
Luego lee la story que vamos a implementar en .bmad/stories/XX-nombre.md.
```

### Orden de trabajo recomendado

Las stories están numeradas en orden de dependencia:

```
01-exports.md        ~30 min   agregar exports (sin dependencias)
02-repl.md           ~1h       REPL con streaming (requiere 01)
03-cli-main.md       ~1h       CLI funcional (requiere 02)
04-agent-server.md   ~2-3h     WebSocket server (requiere 03)
05-literature-flow.md ~2h      flow de literatura (requiere 04)
06-emacs-mode.el     ~3h       Emacs package (requiere 04)
```

### Flujo de trabajo por story

1. `claude-code` lee STATUS.md y la story
2. Implementa los cambios en src/
3. Verifica con el test de la story
4. Si pasa: `git commit` y marcar story como DONE en el archivo
5. Actualizar STATUS.md con el nuevo estado

### Comandos que claude-code puede ejecutar en xolotl

```bash
# Verificar compilación
julia --project=. -e 'using Paipermc; println("OK")'

# Test de inferencia
julia --project=. -e '
using Paipermc
msgs = [Paipermc.GatewayMessage("user", "Say: OK")]
resp = Paipermc.chat_completion("writer", msgs; max_tokens=10)
println(resp.content)
'

# Ver errores de LiteLLM
docker logs --tail=20 paipermc-litellm

# Reiniciar si algo falla
cd ~/Projects/PAIperMC/paipermc/docker
docker compose restart
```

### Cuando algo no compila

1. Leer el error completo — Julia da ubicación exacta (archivo:línea)
2. `cat src/archivo_con_error.jl` — ver el contenido actual
3. El error más común: `end` huérfano → eliminarlo
4. Segundo más común: función duplicada → buscar con `grep -r "function nombre" src/`

### Restricciones importantes para claude-code

- NO crear submódulos (`module X ... end`) dentro de los archivos src/
- NO agregar dependencias sin verificar que están en el registry de Julia
- SIEMPRE hacer `julia --project=. -e 'using Paipermc; println("OK")'` antes de commit
- Las API keys están en `.env` — no hardcodear, usar `ENV["NOMBRE"]`
- El directorio `lean/` está en `.gitignore` — no commitearlo

### Estructura de commit recomendada

```bash
git add -A
git commit -m "feat(exports): add public function exports

- Added export for route_agent, ConversationHistory, chat_completion
- Verified: using Paipermc; route_agent() works without prefix"
git push origin main
```
