# paipermc — Architecture Document

> **paiper** /ˈpeɪpər/ — scientific paper authoring platform with AI built-in
> **mc** — Model Context Protocol, the communication backbone
> Version: 0.6.0-spec | Status: pre-implementation

---

## 1. Vision

paipermc is a local-first AI research platform for mathematical physics.
It covers the full lifecycle of a scientific paper: exhaustive literature
research, conceptual auditing, formal verification, writing, and submission
preparation.

It behaves like claude-code in its interaction model — an autonomous agent
with conversation history, tool invocation, and confirmation-gated writes —
but is specialized for the research workflow of a mathematical physicist.

All core intelligence runs on xolotl. External APIs are invoked only on
explicit request or within named flows. Nothing leaves the project without
confirmation.

```bash
# One-shot
paipermc "reorganize the introduction based on the results section"
paipermc --model claude-opus-4-5 "full peer review as JMP referee"
paipermc --flow research             # exhaustive reference research
paipermc --flow literature "contact geometry dissipative systems"
paipermc --flow review
paipermc --flow verify "theorem:2"

# Background research agent
paipermc research --watch            # runs continuously, surfaces new refs

# Interactive REPL
paipermc
paiper [writer] contact-geometry-2025 > audit the argument in section 3
paiper [reviewer:gaps] > find implicit assumptions in theorem 2
paiper [lean] > generate lean scaffold for theorem 2

# Emacs MCP server
paipermc serve
paipermc serve --remote
```

---

## 2. Agent loop

Same agentic loop as claude-code: the agent reasons, chains tool calls
autonomously, and pauses only for writes, external API calls, and
operations that modify the project index.

```
User input
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│                      AGENT LOOP                          │
│                                                          │
│  1. Think    reason about task, select agent + model     │
│  2. Plan     choose tools, order of invocation           │
│  3. Act      call tools autonomously                     │
│  4. Observe  incorporate results, update context         │
│  5. Repeat   until task complete or confirmation needed  │
│  6. Respond  stream result to client                     │
│                                                          │
│  PAUSE for:                                              │
│    writes to project files                               │
│    external API calls (academic, LLM, formal)            │
│    PDF downloads and index modifications                 │
└──────────────────────────────────────────────────────────┘
```

Confirmation UI:

```
  paipermc wants to write 2 files

  ┌─ sections/introduction.tex ─────────────────────────┐
  │ - The paper investigates the...                     │
  │ + This work establishes a geometric framework...    │
  └─────────────────────────────────────────────────────┘
  ┌─ refs.bib ──────────────────────────────────────────┐
  │ + @article{bravetti2023, ...}                       │
  └─────────────────────────────────────────────────────┘

  Allow? [y/n/d(iff)/e(dit)/s(kip this file)]
```

---

## 3. System topology

```
tlacotzontli (Tailscale network)
│
├── xolotl  100.64.0.22                       [AI SERVER]
│   ├── paipermc-agent      :9000             agent loop + tools
│   ├── LiteLLM             :8088             local model gateway
│   ├── literature-svc      :8081             RAG + academic API bridge
│   ├── lean-svc            :8082             Lean 4 + Mathlib4
│   ├── Ollama              :11434            local model backend
│   └── LanceDB             local             vector store
│
│   Transport: HTTP directo sobre Tailscale (WireGuard cifra la conexión)
│   No se requiere TLS adicional dentro de tlacotzontli
│
└── ollintzin                                 [CLIENT]
    ├── paipermc CLI        local             WebSocket client
    └── Emacs               local             paipermc-mode (MCP/stdio)
```

### Communication

```
ollintzin                                 xolotl
─────────                                 ──────
paipermc CLI / Emacs
    │
    │  WebSocket  ws://100.64.0.22:9000
    ▼
paipermc-agent (Julia)
    │
    ├── LiteLLM :8088
    │     ├── Ollama :11434         local models (writer, math, literature)
    │     ├── Anthropic API         claude-opus-4-5, claude-sonnet-4-5
    │     └── Google AI API         gemini-2.5-pro
    │
    ├── literature-svc :8081
    │     ├── LanceDB               local vector index
    │     ├── Semantic Scholar API  primary academic search
    │     ├── Consensus API         AI-extracted conclusions
    │     ├── Elicit API            structured extraction + tables
    │     ├── Perplexity API        reasoning search + recent preprints
    │     ├── NASA ADS API          physics/math specialized coverage
    │     ├── OpenAlex API          open index, no rate limits
    │     └── arXiv API             preprint search + PDF download
    │
    ├── lean-svc :8082
    │     ├── Lean 4 + Mathlib4     local formal verification
    │     ├── Wolfram Alpha API     symbolic computation verification
    │     └── AlphaProof API        stubbed — activate when available
    │
    └── project files               read freely / write with confirmation
```

---

## 4. Repository structure

```
paipermc/
├── ARCHITECTURE.md
├── Project.toml
├── Manifest.toml
├── src/
│   ├── Paipermc.jl
│   │
│   ├── cli/
│   │   ├── main.jl               entry point, flags, dispatch
│   │   ├── repl.jl               REPL loop, slash commands
│   │   ├── commands.jl           subcommand handlers
│   │   ├── renderer.jl           streaming, diffs, tables, progress
│   │   └── connection.jl         WebSocket client
│   │
│   ├── server/
│   │   ├── agent_server.jl       WebSocket server :9000
│   │   ├── session.jl            per-connection session state
│   │   └── auth.jl               shared key authentication
│   │
│   ├── agent/
│   │   ├── loop.jl               core agentic loop
│   │   ├── router.jl             auto-selects agent + model
│   │   ├── history.jl            conversation history management
│   │   ├── context.jl            project context assembly
│   │   └── confirmation.jl       pause + confirm logic
│   │
│   ├── agents/
│   │   ├── writer.jl
│   │   ├── mathematician.jl
│   │   ├── literature.jl
│   │   ├── researcher.jl         exhaustive research agent
│   │   ├── reviewer.jl           multi-mode auditor
│   │   └── lean_agent.jl         formal verification orchestrator
│   │
│   ├── flows/
│   │   ├── research_flow.jl      exhaustive reference research pipeline
│   │   ├── literature_flow.jl    targeted discovery pipeline
│   │   ├── review_flow.jl        style + argument + gaps pipeline
│   │   └── verify_flow.jl        Lean + formal verification pipeline
│   │
│   ├── tools/
│   │   ├── registry.jl
│   │   ├── read_file.jl
│   │   ├── write_file.jl
│   │   ├── list_files.jl
│   │   ├── search_literature.jl  unified search across all academic APIs
│   │   ├── fetch_paper.jl
│   │   ├── summarize_paper.jl
│   │   ├── compare_papers.jl
│   │   ├── build_concept_graph.jl
│   │   ├── index_pdf.jl
│   │   ├── improve_paragraph.jl
│   │   ├── check_latex.jl
│   │   ├── wolfram_compute.jl
│   │   ├── lean_scaffold.jl
│   │   ├── lean_compile.jl
│   │   └── call_external.jl
│   │
│   ├── models/
│   │   ├── gateway.jl            LiteLLM client
│   │   ├── anthropic.jl          Anthropic API direct client
│   │   ├── gemini.jl             Google AI API client
│   │   ├── selector.jl           model resolution logic
│   │   └── definitions.jl        all model aliases + capabilities
│   │
│   ├── academic/
│   │   ├── semantic_scholar.jl
│   │   ├── elicit.jl
│   │   ├── consensus.jl
│   │   ├── perplexity.jl
│   │   ├── nasa_ads.jl
│   │   ├── openalex.jl
│   │   ├── arxiv.jl
│   │   ├── marker.jl             PDF → Markdown
│   │   ├── lancedb.jl            vector store interface
│   │   └── bibtex.jl             BibTeX generation + deduplication
│   │
│   ├── formal/
│   │   ├── lean_bridge.jl        Julia ↔ Lean 4
│   │   ├── lean_templates.jl     Lean scaffolds for math physics
│   │   ├── gap_analyzer.jl       Lean errors → human-readable gaps
│   │   ├── wolfram_bridge.jl     Wolfram Alpha API client
│   │   └── alphaproof.jl         AlphaProof API (stubbed)
│   │
│   ├── mcp/
│   │   ├── server.jl             JSON-RPC over stdio
│   │   ├── protocol.jl
│   │   └── proxy.jl              stdio ↔ WebSocket bridge
│   │
│   └── project/
│       ├── config.jl
│       ├── workspace.jl
│       └── scaffold.jl
│
├── emacs/
│   └── paipermc-mode.el
│
├── services/
│   ├── litellm_config.yaml
│   ├── paipermc-agent.service
│   ├── paipermc-litellm.service
│   ├── paipermc-literature.service
│   └── paipermc-lean.service
│
├── scripts/
│   ├── install-xolotl.sh
│   └── install-ollintzin.sh
│
└── test/
    ├── runtests.jl
    ├── test_agent_loop.jl
    ├── test_research_flow.jl
    ├── test_literature_flow.jl
    ├── test_review_flow.jl
    ├── test_verify_flow.jl
    └── test_mcp.jl
```

---

## 5. Julia package definition

```toml
name    = "Paipermc"
uuid    = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
authors = ["Héctor Javier Medel Cobaxin <hector@phaimat.com>"]
version = "0.4.0"

[deps]
ArgParse    = "c7e460c6-2fb9-53a9-8c5b-16f535851c63"
HTTP        = "cd3eb016-35fb-5094-929b-558a96fad6f3"
JSON3       = "0f8b85d8-7e73-4b43-9b55-9e7f2f3a5df8"
WebSockets  = "104b5d7c-a370-577a-8038-80a2059c5097"
REPL        = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"
TOML        = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
Logging     = "56ddb016-857b-54e1-b83d-db4d58db5568"
Dates       = "ade2ca70-3891-5945-98fb-dc099432e06a"
UUIDs       = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
StructTypes = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
Markdown    = "d6f4376e-aef5-505a-96c1-9c027394607a"
PythonCall  = "6099a3de-0909-46bc-b1f4-468b9a2dfc0b"

[compat]
julia = "1.10"
```

---

## 6. Model assignments — best model per task

### Design principle

Every agent uses the model with the highest capability for its specific
cognitive demand, not the most convenient for VRAM. Model swaps on xolotl
take 3-5 seconds; this is acceptable for quality. The router announces
swaps in verbose mode.

### Local models on xolotl (Ollama via LiteLLM)

| Agent / Task | Model | VRAM | Cognitive demand |
|---|---|---|---|
| `writer` — prose, structure, style | qwen2.5:14b-instruct-q4_K_M | 9 GB | instruction following, technical English |
| `mathematician` — LaTeX, equations | qwen2.5-math:7b-instruct | 5 GB | symbolic precision, math notation |
| `literature` — synthesis, BibTeX | mistral-small:22b-instruct-q4_K_M | 13 GB | long context, multi-document |
| `researcher` — concept graph, gaps | mistral-small:22b-instruct-q4_K_M | 13 GB | long context, deep domain analysis |
| `reviewer:style` — English, clarity | qwen2.5:14b-instruct-q4_K_M | 9 GB | linguistic correction |
| `reviewer:argument` — logic audit | mistral-small:22b-instruct-q4_K_M | 13 GB | structural reasoning, long context |
| `reviewer:gaps` — math rigor | qwen2.5-math:7b + mistral-small:22b | sequential | formal + contextual |
| `lean` — scaffold, gap analysis | mistral-small:22b-instruct-q4_K_M | 13 GB | formal reasoning, Lean syntax |
| `embeddings` — always resident | nomic-embed-text | 0.5 GB | semantic similarity |

VRAM note: 16 GB available. `nomic-embed-text` (0.5 GB) stays resident
always. One large model at a time: either qwen2.5:14b (9 GB) or
mistral-small:22b (13 GB). Ollama handles eviction automatically.
`reviewer:gaps` runs qwen2.5-math:7b first, then loads mistral-small:22b
for contextual analysis.

### External LLM APIs (confirmation required, keys on xolotl)

| Alias | Model | Primary use in paipermc |
|---|---|---|
| `claude-opus-4-5` | claude-opus-4-5 | deep argument audit, full paper review, complex reasoning chains |
| `claude-sonnet-4-5` | claude-sonnet-4-5 | section review, lean agent when local insufficient |
| `gemini-2.5-pro` | gemini-2.5-pro | very long context tasks: read entire project + 40 papers simultaneously, cross-document synthesis |

When to prefer each external LLM:
- `claude-opus-4-5`: any task requiring deep logical reasoning over the
  paper's argument structure. Best reviewer for mathematical arguments.
- `claude-sonnet-4-5`: balanced quality/cost for iterative editing tasks.
- `gemini-2.5-pro`: when context window matters most — ingesting the full
  project plus a large literature corpus in a single prompt.

### Academic search APIs (literature-svc, no LLM confirmation needed)

| API | Role in paipermc | Confirmation |
|---|---|---|
| Semantic Scholar | primary search, citation graph, related work | external network |
| Elicit | structured extraction, comparison tables | external network |
| Consensus | AI-extracted conclusions from papers | external network |
| Perplexity | reasoning search, recent preprints not yet indexed | external network |
| NASA ADS | physics and math specialized coverage | external network |
| OpenAlex | open index, no rate limits, 250M+ works | external network |
| arXiv | preprint search, PDF download | external network |

These APIs are gated behind a single confirmation per flow invocation,
not per individual call. Once approved for a session, they run freely
within that flow.

### Formal verification APIs

| Tool | Role | Confirmation |
|---|---|---|
| Lean 4 + Mathlib4 | primary formal verifier, runs locally on xolotl | compile step |
| Wolfram Alpha API | symbolic computation: integrals, tensor algebra, ODE solutions | per call |
| AlphaProof API | autonomous proof completion (stubbed until API available) | per call |
| Gauss/Aletheia API | theorem exploration, proof search (stubbed) | per call |

### Model selection via --model flag

```bash
# Local agents
paipermc --model writer "..."
paipermc --model mathematician "..."
paipermc --model literature "..."
paipermc --model researcher "..."
paipermc --model lean "..."

# External LLMs
paipermc --model claude-opus-4-5 "full paper review"
paipermc --model claude-sonnet-4-5 "check section 3 argument"
paipermc --model gemini-2.5-pro "synthesize all 40 papers in the index"

# Raw model strings
paipermc --model ollama/qwen2.5:14b "..."
paipermc --model ollama/mistral-small:22b "..."
```

---

## 7. Agent auto-routing (src/agent/router.jl)

```
Priority (first match wins):

1. --model or --flow flag                    → use explicitly, skip routing
2. /agent or /flow command active            → use until /clear or session end
3. message ~ /lean|coq|formal proof|verify theorem/i → lean (mistral-small:22b)
4. message ~ /review|referee|audit|gaps|implicit|counterex/i
       with --mode style                     → reviewer:style (qwen2.5:14b)
       with --mode argument                  → reviewer:argument (mistral-small:22b)
       with --mode gaps                      → reviewer:gaps (sequential)
       no --mode                             → reviewer full (all three)
5. message ~ /research|exhaustive|map|survey|all papers/i → researcher (mistral-small:22b)
6. cursor in math environment                → mathematician (qwen2.5-math:7b)
   [equation, align, gather, multline, cases, tikzcd]
7. message ~ /busca|search|find paper|references|cita|arxiv/i → literature (mistral-small:22b)
8. active file is *.bib                      → literature
9. active file is *.lean                     → lean
10. default                                  → writer (qwen2.5:14b)

Model swap notification (verbose mode):
  "[paipermc] switching model: qwen2.5:14b → mistral-small:22b (~4s)"
```

---

## 8. Flows (src/flows/)

### 8.1 research_flow — exhaustive reference research

The proactive research agent. Given the full project, it builds the
complete map of literature that should exist in the paper — including
references the author does not yet know about.

**Three invocation modes:**

```bash
# Mode 1: named flow (full pipeline, one shot)
paipermc --flow research

# Mode 2: exhaustive flag on literature flow
paipermc --flow literature --exhaustive "contact geometry"

# Mode 3: background watcher (runs continuously, surfaces new refs)
paipermc research --watch
paipermc research --watch --interval 24h  # check every 24 hours
```

**Pipeline:**

```
Step 1 — Project analysis  (researcher agent, mistral-small:22b)
  reads: all .tex files, refs.bib, papermind.toml
  extracts:
    - core concepts and mathematical objects
    - named theorems, lemmas, methods referenced
    - open questions stated in the paper
    - journals and authors already cited
  output: concept map + research profile of the project

Step 2 — Query generation  (researcher agent)
  from concept map, generates:
    - 10-20 targeted search queries (narrow, specific)
    - 5-10 broad survey queries (catch related areas)
    - author-based queries for key figures in the field
    - citation-forward queries (who cites the papers already in refs.bib)

Step 3 — Multi-source exhaustive search  (confirmation: external APIs)
  parallel queries to:
    Semantic Scholar  — primary, citation graph, related work
    Consensus         — AI-extracted conclusions per query
    Elicit            — structured extraction, table rows per paper
    arXiv             — recent preprints not yet in S2
    NASA ADS          — physics/math specific papers not in S2
    OpenAlex          — broad fallback, 250M+ works, no rate limits
  deduplication across all sources
  output: candidate pool (typically 50-200 papers)

Step 4 — Relevance filtering  (researcher agent, mistral-small:22b)
  scores each candidate against the project's concept map:
    - direct relevance (uses same objects/methods)
    - foundational relevance (cited by direct papers)
    - peripheral relevance (adjacent area, worth noting)
  filters to top N (configurable, default 30)

Step 5 — Fetch and index  (confirmation: PDF downloads)
  fetch_paper for each filtered result above threshold
  Marker → Markdown, embed with nomic-embed-text → LanceDB

Step 6 — Deep summarization  (literature agent, mistral-small:22b)
  summarize_paper for each new paper:
    objective, method, main result, connection to this project

Step 7 — Gap analysis  (researcher agent)
  compares: existing refs.bib vs candidate pool
  identifies:
    - foundational papers that should be cited but are not
    - more recent work that supersedes or extends cited results
    - alternative approaches not represented in bibliography
    - missing methodological references

Step 8 — Organized report  (researcher + writer agents)
  produces structured markdown report:
    Section: "Foundational references to add" (must-cite)
    Section: "Directly related recent work" (should-cite)
    Section: "Peripheral connections" (may-cite)
    Section: "Potential conflicts" (papers that contradict results)
  each entry: paper + why it matters + suggested location in paper

Step 9 — BibTeX proposal  (confirmation: write to refs.bib)
  proposes new BibTeX entries organized by section relevance
  deduplicates against existing refs.bib
  confirmation required before writing

Output:
  .paipermc/research_YYYYMMDD.md   full report
  refs.bib additions (proposed, confirmation required)
  LanceDB updated with all new papers
```

**Background watcher mode:**

```bash
paipermc research --watch
# Runs as background process on xolotl
# Monitors: new papers on arXiv matching project queries (daily)
#           citation alerts for papers in refs.bib (weekly)
# Surfaces findings via:
#   - notification in next REPL session
#   - Emacs: message in *paipermc-chat* buffer
#   - .paipermc/research_alerts.jsonl (append-only log)
```

---

### 8.2 literature_flow — targeted discovery

Focused search for a specific topic. Faster than research_flow.

```
Input: search query

Step 1  Local search (LanceDB)
Step 2  External search (S2 + Elicit + Consensus + Perplexity + arXiv)  [confirmation]
Step 3  Fetch + index new papers  [confirmation]
Step 4  Summarize each paper
Step 5  Generate Elicit-style comparison table
Step 6  BibTeX proposal for refs.bib  [confirmation]

--exhaustive flag: adds NASA ADS + OpenAlex + author queries + citation-forward
```

---

### 8.3 review_flow — intellectual audit

Three modes, run individually or as full pipeline:

```bash
paipermc --flow review                    # all three modes
paipermc --flow review --mode style       # English and clarity only
paipermc --flow review --mode argument    # logical structure
paipermc --flow review --mode gaps        # mathematical rigor
paipermc --model claude-opus-4-5 --flow review  # use Claude as reviewer
```

**style mode** (qwen2.5:14b or claude-sonnet-4-5):
Corrects grammar, improves technical English, flags non-standard
terminology for the target journal, suggests rewrites at paragraph level.

**argument mode** (mistral-small:22b or claude-opus-4-5):
Section-by-section logical audit: unsupported claims, circular reasoning,
missing intermediate steps, weak transitions, abstract/conclusions mismatch.

**gaps mode** (qwen2.5-math:7b → mistral-small:22b, or claude-opus-4-5):
Mathematical rigor: implicit hypotheses, boundary cases, possible
counterexamples, notation clashes with established conventions. Reports
as structured gap list with severity (critical / moderate / minor).

**Full pipeline output:**
Single markdown review report + proposed diffs (confirmation required).

---

### 8.4 verify_flow — formal verification

```bash
paipermc --flow verify "theorem:2"
paipermc lean scaffold theorem:2
paipermc lean check .paipermc/lean/theorem_2.lean
```

```
Step 1  Extract theorem + proof from LaTeX
Step 2  Generate Lean 4 scaffold with sorry placeholders  [confirmation to write]
Step 3  Compile with Lean 4 + Mathlib4 on xolotl  [confirmation]
Step 4  Wolfram Alpha verification of key symbolic steps  [confirmation per call]
Step 5  gap_analyzer: Lean errors → human-readable proof gaps
Step 6  AlphaProof/Gauss: attempt to fill sorry blocks  [confirmation, stubbed]
Step 7  Gap report with severity + suggested LaTeX edits  [confirmation to write]

Output:
  .paipermc/lean/theorem_N.lean
  .paipermc/verify_YYYYMMDD.md
  proposed LaTeX edits (confirmation required)
```

---

## 9. Tool specifications

### Permission model

```
AUTONOMOUS:
  read_file, list_files
  search_literature (local LanceDB only)
  summarize_paper, improve_paragraph, check_latex
  lean_scaffold (generates, does not write until confirmed)
  gap_analyzer, build_concept_graph, wolfram_compute (read-only)

CONFIRMATION (one-time per flow invocation):
  search_literature via academic APIs (external network batch)
  fetch_paper (downloads PDFs, modifies index)
  index_pdf (modifies index)

CONFIRMATION (per operation):
  write_file
  lean_compile (executes code on xolotl)
  wolfram_compute (external API call)
  compare_papers (if writing table to file)

CONFIRMATION + --model flag:
  call_external (Anthropic, Gemini, AlphaProof, Gauss)
```

### build_concept_graph — project analysis

```
Input: all .tex files in project
Output: structured JSON:
  {
    "core_objects": ["contact manifold", "Reeb vector field", ...],
    "methods": ["stochastic calculus", "variational principle", ...],
    "named_results": ["theorem:1", "lemma:3", ...],
    "open_questions": [...],
    "cited_authors": ["Bravetti", "de León", "van der Schaft", ...],
    "search_queries": [...],
    "concept_map": { node: [related_nodes] }
  }
```

### compare_papers — Elicit-style table

```
Dimensions auto-extracted from project context for math physics:
  method | manifold type | main theorem | numerical results |
  connection to known results | open problems | year | venue

Output: markdown table + structured JSON for Emacs rendering
```

### wolfram_compute — symbolic verification

```
Input: mathematical expression or computation in natural language / LaTeX
Examples:
  "verify that d(α ∧ dα) = 0 for a contact form α"
  "compute the Lie derivative of H along the Reeb field"
  "solve this first-order ODE: ẋ = -∂H/∂p"
Output: Wolfram result + LaTeX-formatted answer
Confirmation: required per call (external API, billed)
```

---

## 10. WebSocket protocol

```json
// Session management
{ "type": "session_start", "project_root": "/path", "model": "auto" }
{ "type": "session_ready", "session_id": "uuid", "agent": "writer", "project": "name" }

// Conversation
{ "type": "user_message", "session_id": "uuid", "content": "..." }
{ "type": "token", "session_id": "uuid", "content": "chunk" }

// Tool execution
{ "type": "tool_start", "tool": "search_literature", "args": {...} }
{ "type": "tool_result", "tool": "search_literature", "summary": "47 results" }

// Flow progress
{
  "type": "flow_progress",
  "flow": "research",
  "step": 3,
  "total": 9,
  "label": "Multi-source exhaustive search...",
  "detail": "Querying S2 (28), Elicit (19), Consensus (12), Perplexity (8), NASA ADS (11), arXiv (34)"
}

// Confirmation
{
  "type": "confirm_request",
  "action": "fetch_papers",
  "count": 28,
  "message": "paipermc wants to download 28 PDFs and update the index",
  "details": [{"title": "...", "doi": "..."}]
}
{ "type": "confirm_response", "answer": "y" }

// Model swap notification
{ "type": "model_swap", "from": "qwen2.5:14b", "to": "mistral-small:22b", "eta_seconds": 4 }

// Agent change
{ "type": "agent_changed", "from": "writer", "to": "researcher" }

// Background research alert
{ "type": "research_alert", "new_papers": 3, "summary": "3 new relevant papers on arXiv" }

// Done
{ "type": "flow_done", "flow": "research", "summary": "..." }
{ "type": "done" }
```

---

## 11. CLI specification

### Flags

```
--model,   -m  <n>    override model (see Section 6 for all aliases)
--flow,    -f  <n>    run named pipeline: research|literature|review|verify
--mode         <n>    flow sub-mode: style|argument|gaps|exhaustive
--project, -p  <path> set project root
--remote,  -r         force execution on xolotl via SSH
--no-confirm          skip confirmations (scripting only)
--verbose             show tool calls, model swaps, reasoning steps
--watch               background mode (research flow only)
--interval     <d>    watcher interval: 1h|12h|24h|7d (default: 24h)
--version
--help
```

### Subcommands

```
paipermc                              interactive REPL
paipermc "<prompt>"                   one-shot
paipermc serve                        MCP server for Emacs
paipermc serve --remote

paipermc new paper <n>
paipermc open <path>

paipermc search "<query>"             targeted literature search
paipermc research                     exhaustive research flow
paipermc research --watch             background watcher
paipermc fetch <doi|arxiv-id>
paipermc index <pdf|dir>
paipermc refs
paipermc table "<query>"

paipermc review
paipermc review --mode style|argument|gaps
paipermc verify <theorem-ref>
paipermc lean scaffold <theorem-ref>
paipermc lean check <lean-file>

paipermc models                       list models + GPU status
paipermc apis                         list external APIs + auth status
paipermc agents
paipermc status
paipermc config
```

### REPL slash commands

```
/agent   writer|mathematician|literature|researcher|reviewer|lean
/model   <n>
/flow    research|literature|review|verify
/mode    style|argument|gaps|exhaustive
/search  <query>
/fetch   <doi|arxiv-id>
/file    <path>
/context
/history
/clear
/confirm on|off
/apis                   show external API status
/status
/help
```

---

## 12. Project structure

```
/papers/contact-geometry-2025/
├── papermind.toml
├── main.tex
├── sections/
│   ├── introduction.tex
│   ├── methods.tex
│   └── results.tex
├── refs.bib
├── figures/
└── .paipermc/
    ├── context.json            session state
    ├── concept_map.json        project analysis (updated by researcher)
    ├── literature_index/       LanceDB project index
    ├── lean/
    │   ├── theorem_1.lean
    │   └── theorem_2.lean
    ├── research_20250415.md    exhaustive research report
    ├── research_alerts.jsonl   background watcher log
    ├── reviews/
    │   └── review_20250415.md
    ├── verify_20250415.md
    ├── write_log.jsonl
    └── api_log.jsonl           all external API calls + token counts
```

### papermind.toml

```toml
[project]
name     = "Stochastic Hamiltonian systems on contact manifolds"
main     = "main.tex"
journal  = "Journal of Mathematical Physics"
style    = "aip"
language = "en"

[agents]
default           = "writer"
math_environments = ["equation", "align", "gather", "multline", "cases", "tikzcd"]
auto_route        = true
lean_agent_model  = "mistral-small:22b"   # or "claude-sonnet-4-5"
review_model      = "auto"                # auto: local; set "claude-opus-4-5" for external

[models]
default           = "auto"
external_review   = "claude-opus-4-5"
external_longctx  = "gemini-2.5-pro"

[literature]
index         = ".paipermc/literature_index"
bib           = "refs.bib"
sources       = ["local", "semantic_scholar", "arxiv"]
max_results   = 30
auto_fetch    = false

[research]
enabled       = true
watch         = false
interval      = "24h"
sources       = ["semantic_scholar", "elicit", "consensus", "perplexity", "nasa_ads", "openalex", "arxiv"]
max_candidates = 200
top_n         = 30

[formal]
lean_dir      = ".paipermc/lean"
mathlib       = true
wolfram       = true
alphaproof    = false   # enable when API available

[server]
host = "100.64.0.22"   # IP Tailscale de xolotl
port = 9000
tls  = false           # Tailscale/WireGuard cifra el transporte
```

---

## 13. External API configuration on xolotl

All API keys stored in `/opt/paipermc/.env`:

```bash
# LLM APIs
ANTHROPIC_API_KEY=...
GOOGLE_AI_API_KEY=...          # Gemini 2.5 Pro

# Academic search APIs
SEMANTIC_SCHOLAR_API_KEY=...   # free tier available, higher limits with key
CONSENSUS_API_KEY=...
ELICIT_API_KEY=...
NASA_ADS_API_KEY=...          # free, requires registration
PERPLEXITY_API_KEY=...        # sonar-pro model for academic search
# OpenAlex requires no key (public API)

# Formal verification
WOLFRAM_APP_ID=...
ALPHAPROOF_API_KEY=...         # stubbed, add when available

# Internal
LITELLM_MASTER_KEY=sk-phaimat-local
```

`paipermc apis` shows status of all configured APIs:

```
paipermc apis

  LOCAL
  ● Ollama          running (qwen2.5:14b loaded, 9.1 GB VRAM)
  ● LanceDB         running (1,247 papers indexed)
  ● Lean 4          running (Mathlib4 ready)

  ACADEMIC SEARCH
  ● Semantic Scholar configured (100 req/s)
  ● Elicit           configured
  ● Consensus        configured
  ● Perplexity       configured (sonar-pro)
  ● NASA ADS         configured
  ● OpenAlex         public (no key required)
  ● arXiv            public (no key required)

  LLM EXTERNAL
  ● Anthropic        configured (claude-opus-4-5, claude-sonnet-4-5)
  ● Google AI        configured (gemini-2.5-pro)

  FORMAL
  ● Wolfram Alpha    configured
  ○ AlphaProof       not configured (stubbed)
  ○ Gauss/Aletheia   not configured (stubbed)
```

---

## 14. Emacs package: paipermc-mode

### Layout

```
M-x paipermc  or  C-c p l

┌────────────────────────────────┬─────────────────────────┐
│                                │                         │
│  *sections/introduction.tex*   │                         │
│  AUCTeX · CDLaTeX              │   *paipermc-chat*       │
│  RefTeX · SyncTeX              │                         │
│  (left · 65% height)           │   [writer] streaming    │
│                                │   flow progress bar     │
├────────────────────────────────┤   model swap notice     │
│                                │   research alerts       │
│  *paipermc-files*              │   confirmations via     │
│  dired · project root          │   minibuffer            │
│  (left · 35% height)           │   (right · 100%)        │
└────────────────────────────────┴─────────────────────────┘

Left:  60% frame width — LaTeX 65% height / dired 35% height
Right: 40% frame width — chat, full height

Mode line: [paipermc: writer | contact-geometry-2025 | xolotl ●]
```

### Elisp layout

```elisp
(defun paipermc-layout ()
  (interactive)
  (delete-other-windows)
  (let* ((left-width (floor (* (frame-width) 0.60)))
         (tex-buf    (paipermc--find-tex-buffer))
         (files-buf  (dired-noselect (paipermc--project-root)))
         (chat-buf   (get-buffer-create "*paipermc-chat*")))
    (split-window-right left-width)
    (switch-to-buffer tex-buf)
    (split-window-below (floor (* (window-height) 0.65)))
    (other-window 1)
    (switch-to-buffer files-buf)
    (other-window 1)
    (switch-to-buffer chat-buf)
    (other-window 1)))
```

### Keybindings

```
C-c p l     paipermc-layout
C-c p p     paipermc-send              send region/paragraph to agent
C-c p s     paipermc-search            targeted literature search
C-c p S     paipermc-fetch             fetch paper by DOI/arXiv id
C-c p t     paipermc-table             comparison table
C-c p e     paipermc-research          exhaustive research flow
C-c p w     paipermc-research-watch    toggle background watcher
C-c p f     paipermc-files             focus file browser
C-c p a     paipermc-agent             manual agent override
C-c p m     paipermc-model             switch model
C-c p R     paipermc-review            review flow (full or --mode)
C-c p V     paipermc-verify            verify flow on theorem at point
C-c p L     paipermc-lean-scaffold     Lean scaffold for theorem at point
C-c p W     paipermc-wolfram           Wolfram computation
C-c p v     paipermc-call-external     call Claude/Gemini explicitly
C-c p i     paipermc-index-pdf
C-c p r     paipermc-rewrite
C-c p d     paipermc-diff
C-c p /     paipermc-clear
C-c p ?     paipermc-status
C-c p A     paipermc-apis              show API status
```

---

## 15. Infrastructure on xolotl (Arch Linux)

```
systemd services:
  ollama.service                       (already running)
  paipermc-agent.service               Julia WS server      :9000
  paipermc-litellm.service             LiteLLM gateway      :8088
  paipermc-literature.service          academic API bridge  :8081
  paipermc-lean.service                Lean 4 compile svc   :8082

Data layout:
  /home/mech/Projects/PAIperMC/paipermc/   application root
  /home/mech/Projects/PAIperMC/paipermc/.env   API keys
  /opt/paipermc/venv/              Python: LiteLLM, FastAPI, LanceDB, Marker
  /opt/paipermc/lean/              Lean 4 + Mathlib4
  /data/papers_global/             shared LanceDB index (all projects)
  /data/papers_global/pdfs/        downloaded PDFs
```

---

## 16. Development roadmap

### Phase A — xolotl infrastructure  ~2-3 days
- [ ] LiteLLM with all 5 agent configs + external LLM routes
- [ ] Pull models: qwen2.5:14b, qwen2.5-math:7b, mistral-small:22b, nomic-embed-text
- [ ] FastAPI literature-svc: LanceDB + all 7 academic API clients (S2, Elicit, Consensus, Perplexity, NASA ADS, OpenAlex, arXiv)
- [ ] Lean 4 + Mathlib4 installation
- [ ] All systemd services
- [ ] `.env` with all API keys
- [ ] Verificar acceso desde ollintzin: curl http://100.64.0.22:8088/health
- [ ] `paipermc apis` smoke test

### Phase B — Agent server  ~1 week
- [ ] WebSocket server :9000
- [ ] Agent loop + history + confirmation system
- [ ] Auto-router with model swap notifications
- [ ] All tools in src/tools/
- [ ] LiteLLM + Anthropic + Gemini clients
- [ ] `paipermc-agent.service`

### Phase C — Flows  ~1-2 weeks
- [ ] `research_flow`: full 9-step pipeline + background watcher
- [ ] `literature_flow`: 6-step + --exhaustive flag
- [ ] `review_flow`: 3-mode reviewer with correct model per mode
- [ ] `verify_flow`: Lean + Wolfram + gap analysis
- [ ] AlphaProof/Gauss stubbed with clean activation path

### Phase D — CLI client  ~3-4 days
- [ ] WebSocket client + REPL + slash commands
- [ ] --flow, --mode, --model, --watch flag handling
- [ ] Terminal renderer: tables, diffs, progress bars, API status
- [ ] `install-ollintzin.sh`

### Phase E — MCP + Emacs  ~4-5 days
- [ ] stdio ↔ WebSocket proxy
- [ ] `paipermc-mode.el`: full package
- [ ] Flow progress + research alerts in chat buffer
- [ ] All keybindings including new research/wolfram bindings

### Phase F — Polish  ongoing
- [ ] Session persistence
- [ ] Zotero/BBT refs.bib watcher integration
- [ ] `paipermc new paper` scaffolding
- [ ] Full test suite
- [ ] Performance: model preloading hints based on project type

---

## 17. Non-goals for v0.4

- No web UI
- No multi-user support
- No automatic cloud sync without confirmation
- No non-LaTeX formats
- No Windows support
- AlphaProof/Gauss/Aletheia: stubbed with clean activation path,
  not implemented until APIs are publicly available

---

*Maintained in `paipermc/ARCHITECTURE.md`.*
*Update before implementing any architectural change.*
