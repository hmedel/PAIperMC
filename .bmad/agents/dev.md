# Dev Agent — paipermc

## Rol

Implementa las stories, corrige bugs, escribe código Julia limpio.
Siempre verifica que `julia --project=. -e 'using Paipermc; println("OK")'`
pase antes de hacer commit.

## Contexto técnico

**Julia 1.12.6** en xolotl. **Módulo plano** — sin submódulos anidados.

### Patrón de función de tool

Cada tool sigue este patrón:
```julia
function nombre_tool(args::Dict, project_root::String) :: String
    # validar args
    # ejecutar
    # retornar String con resultado o "Error: mensaje"
end
```

### Patrón de inferencia

```julia
# Sin streaming (para tools internas)
msgs = [Paipermc.GatewayMessage("system", "..."), GatewayMessage("user", "...")]
resp = Paipermc.chat_completion("writer", msgs; max_tokens=2048)
resp.content

# Con streaming (para output al usuario)
Paipermc.stream_completion("writer", msgs, token -> print(token))
```

### Agregar exports

Al agregar una función pública, agregarla en `src/Paipermc.jl`:
```julia
export nombre_funcion, OtroTipo
```

### Testing rápido en xolotl

```bash
julia --project=. -e '
using Paipermc
# tu test aquí
'
```

### Errores comunes y soluciones

| Error | Causa | Solución |
|---|---|---|
| `UndefVarError: route_agent` | No exportado | Usar `Paipermc.route_agent` o agregar export |
| `Method overwriting` | Función definida 2 veces | Buscar duplicados en src/ |
| `Expected end` | `end` huérfano de módulo eliminado | Revisar el archivo con `cat` |
| `HTTP.post` timeout | LiteLLM no responde | `docker compose restart litellm` |

### Dependencias disponibles

```julia
# Ya en Project.toml y compiladas:
using HTTP, JSON3, WebSockets, ArgParse, StructTypes
using Logging, Dates, UUIDs, TOML
```

## Orden de implementación recomendado

1. Exports en Paipermc.jl
2. REPL con streaming real
3. julia_main() CLI funcional
4. WebSocket server real
5. Flows (literature → review → verify)
6. Emacs mode
