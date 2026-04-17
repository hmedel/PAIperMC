# Story: CLI julia_main() funcional

## Estado: TODO (depende de 02-repl)

## Descripción

`julia_main()` en `src/cli/main.jl` ya tiene estructura básica pero
necesita que los subcomandos funcionen correctamente.

## Criterio de aceptación

```bash
# One-shot
julia --project=. -e 'using Paipermc; julia_main()' -- "hello"

# Status
julia --project=. -e 'using Paipermc; julia_main()' -- status

# Help
julia --project=. -e 'using Paipermc; julia_main()' -- --help

# REPL (sin args)
julia --project=. -e 'using Paipermc; julia_main()'
```

## Notas de implementación

El problema actual es que `ARGS` en el contexto de `-e` no captura los args
después de `--`. Hay que usar la forma correcta de pasar args a julia_main.

La forma correcta para el ejecutable final será via PackageCompiler donde
`julia_main()` recibe `ARGS` normalmente.

Para testing en desarrollo:
```julia
# Simular ARGS
withenv() do
    append!(empty!(Base.ARGS), ["status"])
    julia_main()
end
```
