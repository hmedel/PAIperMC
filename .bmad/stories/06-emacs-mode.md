# Story: paipermc-mode.el

## Estado: TODO (depende de 04-agent-server)

## Descripción

Paquete Emacs que conecta al agent server via MCP sobre stdio.

## Layout objetivo

```
┌────────────────────────────────┬─────────────────────────┐
│  *paper.tex*                   │                         │
│  AUCTeX · CDLaTeX              │   *paipermc-chat*       │
│  (izq · 65% altura)            │   streaming tokens      │
├────────────────────────────────┤   (der · 100%)          │
│  *paipermc-files*              │                         │
│  dired                         │                         │
│  (izq · 35% altura)            │                         │
└────────────────────────────────┴─────────────────────────┘
```

## Keybindings principales

```
C-c p l   paipermc-layout
C-c p p   paipermc-send
C-c p s   paipermc-search
C-c p R   paipermc-review
C-c p V   paipermc-verify
```

## Archivo

`emacs/paipermc-mode.el` — ya existe como stub vacío.
La implementación completa requiere que el WebSocket server (story 04)
esté funcionando primero.

## Referencia

Ver ARCHITECTURE.md sección 14 para especificación completa del paquete Emacs.
