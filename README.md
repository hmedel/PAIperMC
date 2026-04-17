# PAIperMC

Local-first AI research platform for scientific papers in LaTeX.

**paiper** — scientific paper authoring with AI built-in  
**mc** — Model Context Protocol backbone

## Architecture

```
tlacotzontli (Tailscale)
│
├── xolotl  [AI Server]          100.64.0.22
│   ├── Ollama          :11434   local models
│   ├── LiteLLM         :8088    model gateway
│   ├── literature-svc  :8081    academic APIs
│   └── Lean 4 + Mathlib4        formal verification
│
└── ollintzin  [Client]
    ├── paipermc CLI             Julia executable
    └── Emacs + paipermc-mode    LaTeX IDE
```

## Features

- **Agent loop** — autonomous reasoning with tool invocation (like claude-code)
- **Literature research** — Semantic Scholar, Elicit, arXiv, NASA ADS, OpenAlex
- **Formal verification** — Lean 4 + Mathlib4 scaffold from LaTeX theorems
- **Multi-agent** — writer, mathematician, literature, researcher, reviewer (3 modes), lean
- **Emacs integration** — 3-panel layout (LaTeX / files / chat)
- **Local-first** — all models run on xolotl via Ollama

## Quick Start

```bash
# On xolotl — install infrastructure (Phase A)
sudo bash scripts/install-xolotl.sh

# On xolotl — install agent server (Phase B)
bash scripts/install-agent-xolotl.sh

# On ollintzin — install CLI
bash scripts/install-ollintzin.sh sysimage

# Use
paipermc status
paipermc "improve the introduction"
paipermc --flow literature "contact geometry Hamiltonian systems"
paipermc --flow review
paipermc --flow verify "theorem:2"
```

## Models (xolotl)

| Agent | Model | Role |
|---|---|---|
| writer | qwen2.5:7b-instruct-q4_K_M | prose, structure, style |
| mathematician | qwen2-math:7b-instruct | LaTeX math, equations |
| literature | mistral-small:22b | synthesis, BibTeX |
| researcher | mistral-small:22b | exhaustive research |
| reviewer-style | qwen2.5:7b-instruct-q4_K_M | English, clarity |
| reviewer-argument | deepseek-r1:14b | logical audit |
| reviewer-gaps | qwen2-math:7b-instruct | math rigor |
| lean | mistral-small:22b | Lean 4 formalization |

External: claude-opus-4-5, claude-sonnet-4-5, gemini-2.5-pro (on request)

## Build

```bash
# Sysimage (~10 min, fast startup)
julia build.jl sysimage

# Standalone executable (~25 min)
julia build.jl app

# Benchmark startup time
julia build.jl benchmark
```

## Project structure

```
src/
├── Paipermc.jl          package entry point
├── agent/               loop, router, history, confirmation
├── models/              gateway, definitions, anthropic
├── tools/               read_file, write_file, search_literature...
├── server/              WebSocket agent server :9000
├── cli/                 REPL, main, renderer
├── mcp/                 stdio proxy for Emacs
└── project/             config, workspace, scaffold
emacs/
└── paipermc-mode.el     Emacs package
services/
└── paipermc-agent.service
scripts/
├── install-xolotl.sh
├── install-agent-xolotl.sh
└── install-ollintzin.sh
build.jl                 PackageCompiler build script
precompile_paipermc.jl   precompile tracing script
```

## Architecture document

See [ARCHITECTURE.md](ARCHITECTURE.md) for full specification.

## License

MIT
