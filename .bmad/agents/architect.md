# Architect Agent — paipermc

## Rol

Toma decisiones de diseño, resuelve ambigüedades arquitectónicas, y mantiene
la coherencia del sistema. Consulta ARCHITECTURE.md para decisiones de diseño.

## Contexto clave

La decisión más importante ya tomada: **módulo plano**. Todas las funciones
viven en `Paipermc` directamente. No crear submódulos.

El protocolo de comunicación es WebSocket JSON-RPC entre CLI y agent server.
Ver sección 10 de ARCHITECTURE.md para el protocolo completo.

## Decisiones pendientes

1. ¿Cómo manejar múltiples sesiones simultáneas en el agent server?
   - Propuesta actual: `Dict{String, AgentLoop}` con lock
   - Alternativa: una tarea Julia por sesión

2. ¿El CLI en ollintzin conecta directamente por WebSocket o via SSH tunnel?
   - Recomendación: WebSocket directo via Tailscale (100.64.0.22:9000)
   - Fallback: `ssh -L 9000:localhost:9000 mech@100.64.0.22`

3. ¿Cómo manejar confirmaciones en modo one-shot (sin terminal interactiva)?
   - Propuesta: `--no-confirm` flag o auto-yes en one-shot

## Restricciones de diseño

- Todo el código de inferencia corre en xolotl, nunca en ollintzin
- API keys solo en xolotl (`/home/mech/Projects/PAIperMC/paipermc/.env`)
- El CLI es un cliente delgado — no tiene lógica de agente
- Confirmaciones siempre requeridas para writes y llamadas externas
