# Story: literature_flow

## Estado: TODO (depende de 04-agent-server)

## Descripción

Pipeline completo de búsqueda de literatura:
1. Búsqueda local (LanceDB via literature-svc)
2. Búsqueda externa (S2, arXiv, etc.)
3. Fetch + indexar PDFs
4. Resumir papers
5. Tabla comparativa
6. Propuesta BibTeX

## Criterio de aceptación

```bash
paipermc --flow literature "contact geometry stochastic Hamiltonians"
# Muestra progreso paso a paso
# Produce tabla comparativa
# Propone entradas BibTeX
```

## Nota

`literature-svc` ya está corriendo en :8081 y tiene los clientes de APIs
implementados (S2, arXiv, OpenAlex, NASA ADS funcionales; Elicit, Consensus,
Perplexity como stubs). Ver `docker/literature-svc/main.py`.

El flow orquesta llamadas a `search_literature()` y al agente `literature`.
