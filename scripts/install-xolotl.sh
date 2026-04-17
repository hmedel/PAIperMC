#!/usr/bin/env bash
# =============================================================================
# paipermc — install-xolotl.sh
# Fase A: infraestructura en xolotl (EndeavourOS / Arch Linux)
#
# Despliega:
#   Host (systemd):   Caddy, Lean 4 + Mathlib4
#   Docker Compose:   LiteLLM :8080, literature-svc :8081
#   Ollama:           modelos (ya en systemd, sin modificar)
#
# Usuario:  mech
# Proyecto: /home/mech/Projects/PAIperMC
# Datos:    /home/mech/Projects/PAIperMC/data   (486GB disponibles)
# =============================================================================

set -euo pipefail

# --- colores -----------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[paipermc]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BOLD}==============================${NC}\n${BOLD}$*${NC}\n${BOLD}==============================${NC}"; }

# --- configuracion -----------------------------------------------------------
PAIPERMC_USER="mech"
PROJECT_ROOT="/home/mech/Projects/PAIperMC"
PAIPERMC_ROOT="${PROJECT_ROOT}/paipermc"
DATA_ROOT="${PROJECT_ROOT}/data"
OLLAMA_HOST="http://localhost:11434"
AGENT_PORT=9000
LITELLM_PORT=8088
LITERATURE_PORT=8081
LEAN_PORT=8082

# --- verificaciones previas --------------------------------------------------
step "Verificando prerequisitos"

[[ $(whoami) != "root" ]] && error "Corre con sudo: sudo bash install-xolotl.sh"

# OS
if grep -q "EndeavourOS\|Arch" /etc/os-release 2>/dev/null; then
    success "EndeavourOS / Arch Linux detectado"
else
    warn "OS no reconocido como Arch — el script puede fallar en pasos de pacman"
fi

# Servicios criticos
for svc in ollama docker tailscaled; do
    systemctl is-active --quiet "${svc}.service" \
        && success "${svc} activo" \
        || error "${svc} no está corriendo: systemctl start ${svc}"
done

# Docker Compose v2
docker compose version &>/dev/null \
    && success "Docker Compose v2 disponible" \
    || error "Docker Compose v2 no encontrado. Instala: pacman -S docker-compose"

# Espacio en /home (donde van los datos)
AVAIL_HOME=$(df /home | awk 'NR==2 {print int($4/1024/1024)}')
info "Espacio disponible en /home: ${AVAIL_HOME}GB"
[[ $AVAIL_HOME -lt 40 ]] && warn "Menos de 40GB en /home — los modelos pesan ~27GB"

# Espacio en / (para paquetes del sistema)
AVAIL_ROOT=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
info "Espacio disponible en /: ${AVAIL_ROOT}GB"
[[ $AVAIL_ROOT -lt 5 ]] && error "Menos de 5GB en / — insuficiente para paquetes"

# Python
python3 --version | grep -q "3\." \
    && success "Python $(python3 --version)" \
    || error "Python 3 no encontrado"

# --- directorios -------------------------------------------------------------
step "Creando estructura de directorios"

mkdir -p \
    "${PAIPERMC_ROOT}/docker/literature-svc" \
    "${PAIPERMC_ROOT}/lean" \
    "${DATA_ROOT}/papers_global/pdfs" \
    "${DATA_ROOT}/lancedb" \
    "${DATA_ROOT}/models_cache" \
    "${DATA_ROOT}/lean_projects"

chown -R "${PAIPERMC_USER}:${PAIPERMC_USER}" "${PROJECT_ROOT}"
success "Directorios creados bajo ${PROJECT_ROOT}"

# --- .env --------------------------------------------------------------------
step "Configurando variables de entorno"

ENV_FILE="${PAIPERMC_ROOT}/.env"

if [[ -f "$ENV_FILE" ]]; then
    warn ".env ya existe — no se sobreescribe"
    warn "Edita manualmente: ${ENV_FILE}"
else
    cat > "$ENV_FILE" << 'ENV'
# =============================================================================
# paipermc — API keys
# NUNCA compartas este archivo ni lo subas a git
# =============================================================================

# LLM externos
ANTHROPIC_API_KEY=sk-ant-XXXXXXXXXXXXXXXX
GOOGLE_AI_API_KEY=XXXXXXXXXXXXXXXX

# APIs académicas
SEMANTIC_SCHOLAR_API_KEY=XXXXXXXXXXXXXXXX
ELICIT_API_KEY=XXXXXXXXXXXXXXXX
CONSENSUS_API_KEY=XXXXXXXXXXXXXXXX
PERPLEXITY_API_KEY=pplx-XXXXXXXXXXXXXXXX
NASA_ADS_API_KEY=XXXXXXXXXXXXXXXX
# OpenAlex no requiere key

# Verificación formal
WOLFRAM_APP_ID=XXXXXX-XXXXXXXXXX
# ALPHAPROOF_API_KEY=          # descomentar cuando esté disponible

# Interno
LITELLM_MASTER_KEY=sk-phaimat-local
PAIPERMC_AGENT_KEY=sk-phaimat-agent
ENV

    chmod 600 "$ENV_FILE"
    chown "${PAIPERMC_USER}:${PAIPERMC_USER}" "$ENV_FILE"
    success ".env creado — edítalo con tus keys antes de continuar"
fi

# Cargar variables
set -a; source "$ENV_FILE"; set +a

# --- Configuracion de red (HTTP directo sobre Tailscale) --------------------
step "Configurando acceso de red"

# Obtener IP Tailscale
TS_IP=$(tailscale ip -4 2>/dev/null || echo "100.64.0.22")
info "IP Tailscale de xolotl: ${TS_IP}"

# Hacer que Ollama escuche en todas las interfaces (incluyendo Tailscale)
OLLAMA_OVERRIDE="/etc/systemd/system/ollama.service.d"
mkdir -p "$OLLAMA_OVERRIDE"
cat > "${OLLAMA_OVERRIDE}/tailscale.conf" << OLLAMACONF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
OLLAMACONF

systemctl daemon-reload
systemctl restart ollama
sleep 3
systemctl is-active --quiet ollama && success "Ollama escuchando en 0.0.0.0:11434" || warn "Revisa ollama"

info "Servicios accesibles en tlacotzontli:"
info "  LiteLLM:        http://${TS_IP}:${LITELLM_PORT}"
info "  literature-svc: http://${TS_IP}:${LITERATURE_PORT}"
info "  agent server:   http://${TS_IP}:${AGENT_PORT}  (Fase B)"
info "  Ollama:         http://${TS_IP}:11434"
success "Red configurada — HTTP directo sobre Tailscale (WireGuard cifra el tráfico)"


# --- LiteLLM config ----------------------------------------------------------
step "Generando configuración LiteLLM"

cat > "${PAIPERMC_ROOT}/docker/litellm_config.yaml" << 'LITELLM'
# paipermc — LiteLLM gateway
# Cada agente usa el modelo óptimo para su tarea cognitiva

model_list:

  # ── Agentes locales (Ollama) ─────────────────────────────────────────────
  # Modelos confirmados en xolotl:
  #   qwen2.5:7b-instruct-q4_K_M   — escritura, instrucciones
  #   qwen2-math:7b-instruct        — matemáticas, LaTeX formal
  #   mistral-small:22b             — contexto largo, síntesis
  #   deepseek-r1:14b               — razonamiento en cadena, auditoría
  #   qwen3:8b                      — general, fallback rápido
  #   nomic-embed-text:latest       — embeddings semánticos

  # Prosa, estructura, estilo — inglés técnico
  - model_name: writer
    litellm_params:
      model: ollama/qwen2.5:7b-instruct-q4_K_M
      api_base: http://host.docker.internal:11434
    model_info:
      description: "Escritura científica, IMRaD, estilo de journal"

  # LaTeX matemático — precisión simbólica
  - model_name: mathematician
    litellm_params:
      model: ollama/qwen2-math:7b-instruct
      api_base: http://host.docker.internal:11434
    model_info:
      description: "Ecuaciones, notación, entornos LaTeX"

  # Literatura, síntesis, BibTeX — contexto largo
  - model_name: literature
    litellm_params:
      model: ollama/mistral-small:22b
      api_base: http://host.docker.internal:11434
    model_info:
      description: "Síntesis multi-paper, generación de BibTeX"

  # Investigación exhaustiva — análisis profundo del proyecto
  - model_name: researcher
    litellm_params:
      model: ollama/mistral-small:22b
      api_base: http://host.docker.internal:11434
    model_info:
      description: "Mapa conceptual, gap analysis de literatura"

  # Revisión: estilo e inglés técnico
  - model_name: reviewer-style
    litellm_params:
      model: ollama/qwen2.5:7b-instruct-q4_K_M
      api_base: http://host.docker.internal:11434
    model_info:
      description: "Gramática, claridad, terminología de journal"

  # Revisión: auditoría lógica — deepseek-r1 razona antes de responder
  - model_name: reviewer-argument
    litellm_params:
      model: ollama/deepseek-r1:14b
      api_base: http://host.docker.internal:11434
    model_info:
      description: "Estructura lógica, claims sin soporte, razonamiento en cadena"

  # Revisión: gaps matemáticos — primera pasada formal
  - model_name: reviewer-gaps
    litellm_params:
      model: ollama/qwen2-math:7b-instruct
      api_base: http://host.docker.internal:11434
    model_info:
      description: "Hipótesis implícitas, contraejemplos, notación"

  # Lean 4 — razonamiento formal + síntesis larga
  - model_name: lean
    litellm_params:
      model: ollama/mistral-small:22b
      api_base: http://host.docker.internal:11434
    model_info:
      description: "Scaffold LaTeX→Lean4, análisis de gaps formales"

  # Embeddings — siempre residente en VRAM
  - model_name: embeddings
    litellm_params:
      model: ollama/nomic-embed-text:latest
      api_base: http://host.docker.internal:11434
    model_info:
      description: "Embeddings semánticos para LanceDB"

  # ── Modelos externos (requieren confirmación en el agente) ────────────────

  # Razonamiento profundo, revisión completa de paper
  - model_name: claude-opus-4-5
    litellm_params:
      model: claude-opus-4-5
      api_key: os.environ/ANTHROPIC_API_KEY

  # Revisión de sección, Lean agent cuando lo local no alcanza
  - model_name: claude-sonnet-4-5
    litellm_params:
      model: claude-sonnet-4-5
      api_key: os.environ/ANTHROPIC_API_KEY

  # Contexto muy largo: proyecto completo + corpus de literatura
  - model_name: gemini-2.5-pro
    litellm_params:
      model: gemini/gemini-2.5-pro
      api_key: os.environ/GOOGLE_AI_API_KEY

litellm_settings:
  drop_params: true
  request_timeout: 600
  set_verbose: false

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  port: 8080
  host: "0.0.0.0"
LITELLM

success "litellm_config.yaml generado"

# --- literature-svc ----------------------------------------------------------
step "Generando literature-svc (FastAPI)"

cat > "${PAIPERMC_ROOT}/docker/literature-svc/requirements.txt" << 'REQS'
fastapi==0.115.0
uvicorn[standard]==0.30.0
httpx==0.27.0
lancedb==0.13.0
python-dotenv==1.0.0
pydantic==2.8.0
REQS

cat > "${PAIPERMC_ROOT}/docker/literature-svc/Dockerfile" << 'DOCKERFILE'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8081", "--log-level", "info"]
DOCKERFILE

cat > "${PAIPERMC_ROOT}/docker/literature-svc/main.py" << 'PYAPP'
"""
paipermc — literature service v0.1
FastAPI bridge: LanceDB + academic search APIs

Funcional en Fase A:
  - Semantic Scholar API  (búsqueda primaria)
  - arXiv API             (preprints)
  - OpenAlex API          (sin key, fallback abierto)
  - NASA ADS API          (física/matemáticas)
  - LanceDB               (índice local)

Stubs para Fase B:
  - Elicit, Consensus, Perplexity (requieren acceso a sus APIs)
"""

import os, xml.etree.ElementTree as ET
from typing import Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx, lancedb

app = FastAPI(title="paipermc literature-svc", version="0.1.0")

DB_PATH  = os.getenv("LANCEDB_PATH", "/data/lancedb")
S2_KEY   = os.getenv("SEMANTIC_SCHOLAR_API_KEY", "")
ADS_KEY  = os.getenv("NASA_ADS_API_KEY", "")
PPX_KEY  = os.getenv("PERPLEXITY_API_KEY", "")

db = lancedb.connect(DB_PATH)

# ---------------------------------------------------------------------------

class SearchRequest(BaseModel):
    query:       str
    sources:     list[str] = ["local"]
    max_results: int = 20

class SearchResult(BaseModel):
    title:          str
    authors:        list[str] = []
    year:           Optional[int] = None
    abstract:       Optional[str] = None
    doi:            Optional[str] = None
    arxiv_id:       Optional[str] = None
    venue:          Optional[str] = None
    citation_count: Optional[int] = None
    relevance_score: float = 0.5
    source:         str

# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    return {"status": "ok", "service": "literature-svc", "version": "0.1.0"}

@app.get("/sources")
async def sources():
    """Qué APIs están configuradas."""
    return {
        "local":            True,
        "semantic_scholar": bool(S2_KEY),
        "arxiv":            True,
        "openalex":         True,
        "nasa_ads":         bool(ADS_KEY),
        "perplexity":       bool(PPX_KEY),
        "elicit":           False,   # stub
        "consensus":        False,   # stub
    }

@app.post("/search")
async def search(req: SearchRequest):
    results: list[SearchResult] = []

    # Búsqueda local (LanceDB)
    if "local" in req.sources:
        results.extend(await _search_local(req.query, req.max_results))

    # APIs externas en paralelo
    import asyncio
    tasks = []
    if "semantic_scholar" in req.sources:
        tasks.append(_search_s2(req.query, req.max_results))
    if "arxiv" in req.sources:
        tasks.append(_search_arxiv(req.query, req.max_results))
    if "openalex" in req.sources:
        tasks.append(_search_openalex(req.query, req.max_results))
    if "nasa_ads" in req.sources and ADS_KEY:
        tasks.append(_search_nasa_ads(req.query, req.max_results))
    if "perplexity" in req.sources and PPX_KEY:
        tasks.append(_search_perplexity(req.query, req.max_results))

    if tasks:
        external = await asyncio.gather(*tasks, return_exceptions=True)
        for r in external:
            if isinstance(r, list):
                results.extend(r)

    # Deduplicar por DOI / arXiv ID / título
    seen: set[str] = set()
    deduped: list[SearchResult] = []
    for r in results:
        key = r.doi or r.arxiv_id or r.title.lower()[:60]
        if key and key not in seen:
            seen.add(key)
            deduped.append(r)

    deduped.sort(key=lambda x: x.relevance_score, reverse=True)
    return {
        "results": deduped[:req.max_results],
        "total":   len(deduped),
        "sources": req.sources,
    }

@app.post("/index")
async def index_paper(path: str, metadata: dict = {}):
    """Indexa un paper (ya convertido a Markdown) en LanceDB."""
    # Implementación completa en Fase B con el agent server Julia
    return {"status": "queued", "path": path}

# --- Clientes de APIs -------------------------------------------------------

async def _search_local(query: str, n: int) -> list[SearchResult]:
    try:
        tbl = db.open_table("papers")
        rows = tbl.search(query).limit(n).to_list()
        return [SearchResult(
            title=r.get("title", ""),
            authors=r.get("authors", []),
            year=r.get("year"),
            abstract=r.get("abstract"),
            doi=r.get("doi"),
            arxiv_id=r.get("arxiv_id"),
            venue=r.get("venue"),
            citation_count=r.get("citation_count"),
            relevance_score=max(0.0, 1.0 - float(r.get("_distance", 0.5))),
            source="local"
        ) for r in rows]
    except Exception:
        return []

async def _search_s2(query: str, n: int) -> list[SearchResult]:
    headers = {"x-api-key": S2_KEY} if S2_KEY else {}
    fields  = "title,authors,year,abstract,externalIds,venue,citationCount,tldr"
    async with httpx.AsyncClient(timeout=20) as c:
        try:
            r = await c.get(
                "https://api.semanticscholar.org/graph/v1/paper/search",
                params={"query": query, "limit": n, "fields": fields},
                headers=headers
            )
            return [SearchResult(
                title=p.get("title", ""),
                authors=[a["name"] for a in p.get("authors", [])],
                year=p.get("year"),
                abstract=(p.get("tldr") or {}).get("text") or p.get("abstract"),
                doi=p.get("externalIds", {}).get("DOI"),
                arxiv_id=p.get("externalIds", {}).get("ArXiv"),
                venue=p.get("venue"),
                citation_count=p.get("citationCount"),
                relevance_score=0.85,
                source="semantic_scholar"
            ) for p in r.json().get("data", [])]
        except Exception:
            return []

async def _search_arxiv(query: str, n: int) -> list[SearchResult]:
    async with httpx.AsyncClient(timeout=20) as c:
        try:
            r = await c.get(
                "http://export.arxiv.org/api/query",
                params={"search_query": f"all:{query}",
                        "max_results": n, "sortBy": "relevance"}
            )
            ns   = {"a": "http://www.w3.org/2005/Atom"}
            root = ET.fromstring(r.text)
            out  = []
            for e in root.findall("a:entry", ns):
                arxiv_id = e.find("a:id", ns).text.split("/abs/")[-1]
                out.append(SearchResult(
                    title=e.find("a:title", ns).text.strip().replace("\n", " "),
                    authors=[a.find("a:name", ns).text
                             for a in e.findall("a:author", ns)],
                    abstract=e.find("a:summary", ns).text.strip(),
                    arxiv_id=arxiv_id,
                    venue="arXiv",
                    relevance_score=0.78,
                    source="arxiv"
                ))
            return out
        except Exception:
            return []

async def _search_openalex(query: str, n: int) -> list[SearchResult]:
    async with httpx.AsyncClient(timeout=20) as c:
        try:
            r = await c.get(
                "https://api.openalex.org/works",
                params={"search": query, "per-page": n,
                        "select": "title,authorships,publication_year,doi,"
                                  "primary_location,cited_by_count"},
                headers={"User-Agent": "paipermc/0.1 (mailto:hector@phaimat.com)"}
            )
            return [SearchResult(
                title=w.get("title") or "",
                authors=[a["author"]["display_name"]
                         for a in w.get("authorships", [])],
                year=w.get("publication_year"),
                doi=(w.get("doi") or "").replace("https://doi.org/", "") or None,
                venue=(w.get("primary_location") or {}).get("source", {}).get("display_name"),
                citation_count=w.get("cited_by_count"),
                relevance_score=0.72,
                source="openalex"
            ) for w in r.json().get("results", [])]
        except Exception:
            return []

async def _search_nasa_ads(query: str, n: int) -> list[SearchResult]:
    async with httpx.AsyncClient(timeout=20) as c:
        try:
            r = await c.get(
                "https://api.adsabs.harvard.edu/v1/search/query",
                params={"q": query, "rows": n,
                        "fl": "title,author,year,abstract,doi,citation_count"},
                headers={"Authorization": f"Bearer {ADS_KEY}"}
            )
            return [SearchResult(
                title=(d.get("title") or [""])[0],
                authors=d.get("author", []),
                year=d.get("year"),
                abstract=d.get("abstract"),
                doi=(d.get("doi") or [None])[0],
                venue="NASA ADS",
                citation_count=d.get("citation_count"),
                relevance_score=0.80,
                source="nasa_ads"
            ) for d in r.json().get("response", {}).get("docs", [])]
        except Exception:
            return []

async def _search_perplexity(query: str, n: int) -> list[SearchResult]:
    """Perplexity sonar-pro — útil para preprints recientes y queries complejas."""
    async with httpx.AsyncClient(timeout=30) as c:
        try:
            r = await c.post(
                "https://api.perplexity.ai/chat/completions",
                headers={"Authorization": f"Bearer {PPX_KEY}"},
                json={
                    "model": "sonar-pro",
                    "messages": [{
                        "role": "user",
                        "content": (
                            f"Find the {n} most relevant academic papers about: {query}. "
                            "For each paper provide: title, authors, year, DOI or arXiv ID, "
                            "and a one-sentence summary. Format as JSON array."
                        )
                    }],
                    "return_citations": True
                }
            )
            # Perplexity devuelve texto con citas — parseamos lo que podemos
            # Implementación completa en Fase B
            return []
        except Exception:
            return []
PYAPP

success "literature-svc generado"

# --- Docker Compose ----------------------------------------------------------
step "Generando docker-compose.yml"

cat > "${PAIPERMC_ROOT}/docker/docker-compose.yml" << COMPOSE
# paipermc — Docker Compose
# LiteLLM gateway + literature service
# Generado por install-xolotl.sh

services:

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: paipermc-litellm
    restart: unless-stopped
    ports:
      - "0.0.0.0:${LITELLM_PORT}:4000"
    volumes:
      - ${PAIPERMC_ROOT}/docker/litellm_config.yaml:/app/config.yaml:ro
    env_file:
      - ${PAIPERMC_ROOT}/.env
    extra_hosts:
      - "host.docker.internal:host-gateway"
    command: ["--config", "/app/config.yaml"]
    healthcheck:
      test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:4000/health')"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  literature-svc:
    build:
      context: ${PAIPERMC_ROOT}/docker/literature-svc
    container_name: paipermc-literature
    restart: unless-stopped
    ports:
      - "0.0.0.0:${LITERATURE_PORT}:8081"
    volumes:
      - ${DATA_ROOT}/lancedb:/data/lancedb
      - ${DATA_ROOT}/papers_global:/data/papers_global
    env_file:
      - ${PAIPERMC_ROOT}/.env
    environment:
      - LANCEDB_PATH=/data/lancedb
    healthcheck:
      test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8081/health')"]
      interval: 20s
      timeout: 5s
      retries: 3

networks:
  default:
    name: paipermc-network
COMPOSE

# Servicio systemd para docker compose
cat > /etc/systemd/system/paipermc-docker.service << DOCKERSVC
[Unit]
Description=paipermc Docker Compose (LiteLLM + literature-svc)
After=docker.service network-online.target ollama.service
Requires=docker.service
Wants=ollama.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=${PAIPERMC_USER}
WorkingDirectory=${PAIPERMC_ROOT}/docker
ExecStart=/usr/bin/docker compose up -d --build
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
DOCKERSVC

chown -R "${PAIPERMC_USER}:${PAIPERMC_USER}" "${PAIPERMC_ROOT}"
systemctl daemon-reload
systemctl enable paipermc-docker.service
success "paipermc-docker.service habilitado"

# --- Lean 4 + Mathlib4 -------------------------------------------------------
step "Instalando Lean 4 + Mathlib4"

ELAN_HOME="/home/${PAIPERMC_USER}/.elan"
LEAN_PROJECT="${PAIPERMC_ROOT}/lean/paipermc_lean"

if [[ -f "${ELAN_HOME}/bin/elan" ]]; then
    # No llamar lean --version sin toolchain global — usa elan directamente
    success "elan instalado ($(sudo -u ${PAIPERMC_USER} ${ELAN_HOME}/bin/elan --version 2>/dev/null))"
else
    info "Instalando elan (gestor de versiones de Lean 4)..."
    sudo -u "${PAIPERMC_USER}" bash -c "
        curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
            | sh -s -- -y --default-toolchain leanprover/lean4:stable --no-modify-path
    " && success "elan instalado" || warn "elan falló — instala manualmente"
fi
# Cada proyecto usa su propio lean-toolchain — no se requiere toolchain global

if [[ ! -d "${LEAN_PROJECT}" ]]; then
    info "Inicializando proyecto Lean con Mathlib4..."
    info "Esto puede tardar 30-60 minutos en la primera compilación..."

    sudo -u "${PAIPERMC_USER}" bash -c "
        export PATH=${ELAN_HOME}/bin:\$PATH
        mkdir -p ${PAIPERMC_ROOT}/lean
        cd ${PAIPERMC_ROOT}/lean
        lake new paipermc_lean
        cd paipermc_lean

        # lake add cambió en versiones recientes — usar lakefile.toml directamente
        cat > lakefile.toml << 'LAKEFILE'
name = \"paipermc_lean\"
version = \"0.1.0\"
defaultTargets = [\"PaipermcLean\"]

[[require]]
name = \"mathlib\"
from = \"https://github.com/leanprover-community/mathlib4\"
revision = \"stable\"

[[lean_lib]]
name = \"PaipermcLean\"
LAKEFILE

        echo 'import Mathlib' > PaipermcLean/Basic.lean

        # Descargar Mathlib y compilar
        lake update
        lake build
    " && success "Lean 4 + Mathlib4 listo" \
      || warn "Lean/Mathlib falló — ejecuta manualmente:
        cd ${LEAN_PROJECT} && lake update && lake build"

else
    info "Proyecto Lean ya existe — verificando dependencias..."
    sudo -u "${PAIPERMC_USER}" bash -c "
        export PATH=${ELAN_HOME}/bin:\$PATH
        cd ${LEAN_PROJECT}

        # Verificar que lakefile.toml tiene Mathlib — lake new no lo incluye
        if ! grep -q 'mathlib' lakefile.toml 2>/dev/null; then
            echo 'Mathlib no encontrado en lakefile.toml — agregando...'
            cat > lakefile.toml << 'LAKEFILE'
name = \"paipermc_lean\"
version = \"0.1.0\"
defaultTargets = [\"PaipermcLean\"]

[[require]]
name = \"mathlib\"
from = \"https://github.com/leanprover-community/mathlib4\"
revision = \"stable\"

[[lean_lib]]
name = \"PaipermcLean\"
LAKEFILE
            echo 'import Mathlib' > PaipermcLean/Basic.lean
            rm -f lake-manifest.json
            lake update
        fi

        lake build
    " && success "Lean 4 + Mathlib4 OK" \
      || warn "Lean build falló — ejecuta manualmente:
        cd ${LEAN_PROJECT}
        grep -q mathlib lakefile.toml || (cat > lakefile.toml con [[require]] mathlib)
        rm -f lake-manifest.json && lake update && lake build"
fi

# --- Descargar modelos Ollama ------------------------------------------------
step "Descargando modelos Ollama"

info "Descargando en orden de menor a mayor tamaño"
info "Total aproximado: ~27GB"

# Nota: qwen2-math:7b-instruct es el modelo math oficial en Ollama
# que es la version de la misma familia disponible en el registry
declare -A MODEL_SIZES=(
    ["nomic-embed-text"]="0.5GB"
    ["qwen2-math:7b-instruct"]="4.4GB"
    ["qwen2.5:7b-instruct-q4_K_M"]="5GB"
    ["mistral-small:22b"]="13GB"
    ["deepseek-r1:14b"]="9GB"
    ["qwen3:8b"]="5GB"
)

for model in "nomic-embed-text" "qwen2-math:7b-instruct" "qwen2.5:7b-instruct-q4_K_M" "mistral-small:22b" "deepseek-r1:14b" "qwen3:8b"; do
    size="${MODEL_SIZES[$model]}"
    if ollama list 2>/dev/null | grep -q "${model%%:*}\b"; then
        success "${model} (${size}) ya disponible"
    else
        info "Descargando ${model} (~${size})..."
        ollama pull "$model" \
            && success "${model} descargado" \
            || warn "No se pudo descargar ${model} — ejecuta: ollama pull ${model}"
    fi
done

# --- Levantar Docker ---------------------------------------------------------
step "Levantando servicios Docker"

cd "${PAIPERMC_ROOT}/docker"

info "Construyendo literature-svc..."
sudo -u "${PAIPERMC_USER}" docker compose build literature-svc

info "Iniciando LiteLLM + literature-svc..."
sudo -u "${PAIPERMC_USER}" docker compose up -d

# Esperar LiteLLM
info "Esperando LiteLLM..."
for i in {1..30}; do
    curl -sf "http://localhost:${LITELLM_PORT}/health" &>/dev/null \
        && { success "LiteLLM activo"; break; } \
        || sleep 3
done

# Esperar literature-svc
info "Esperando literature-svc..."
for i in {1..20}; do
    curl -sf "http://localhost:${LITERATURE_PORT}/health" &>/dev/null \
        && { success "literature-svc activo"; break; } \
        || sleep 2
done

# --- .gitignore --------------------------------------------------------------
cat > "${PAIPERMC_ROOT}/.gitignore" << 'GITIGNORE'
.env
*.key
*.crt
data/
__pycache__/
*.pyc
.DS_Store
GITIGNORE

# --- Smoke tests -------------------------------------------------------------
step "Smoke tests"

PASS=0; FAIL=0

check() {
    local name="$1" cmd="$2"
    if eval "$cmd" &>/dev/null; then
        success "  $name"
        ((PASS++))
    else
        warn    "  FAIL: $name"
        ((FAIL++))
    fi
}

check "Ollama API"                 "curl -sf http://localhost:11434/api/tags"
check "nomic-embed-text"          "ollama list | grep -q nomic-embed"
check "qwen2-math:7b-instruct"             "ollama list | grep -q 'qwen2-math'"
check "qwen2.5:7b-instruct"       "ollama list | grep -q 'qwen2.5:7b'"
check "deepseek-r1:14b"           "ollama list | grep -q 'deepseek-r1'"
check "mistral-small:22b"         "ollama list | grep -q 'mistral-small'"
check "LiteLLM /health"           "curl -sf http://localhost:${LITELLM_PORT}/health"
check "LiteLLM /v1/models"        "curl -sf http://localhost:${LITELLM_PORT}/v1/models \
                                    -H 'Authorization: Bearer ${LITELLM_MASTER_KEY:-sk-phaimat-local}'"
check "literature-svc /health"    "curl -sf http://localhost:${LITERATURE_PORT}/health"
check "literature-svc /sources"   "curl -sf http://localhost:${LITERATURE_PORT}/sources"
check "firewalld activo"          "systemctl is-active --quiet firewalld"
check "Ollama en Tailscale"       "curl -sf http://${TS_IP}:11434/api/tags"
check "paipermc-docker habilitado" "systemctl is-enabled --quiet paipermc-docker"

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}Todos los checks pasaron (${PASS}/${PASS})${NC}"
else
    echo -e "${YELLOW}${BOLD}${PASS} OK / ${FAIL} FAIL${NC}"
    echo -e "Revisa los servicios fallidos con: docker compose logs -f"
fi

# --- Resumen -----------------------------------------------------------------
step "Fase A completa"

cat << SUMMARY

${BOLD}Servicios activos:${NC}
  Ollama          http://localhost:11434
  LiteLLM         http://localhost:${LITELLM_PORT}    (Docker)
  literature-svc  http://localhost:${LITERATURE_PORT}    (Docker)
  Acceso Tailscale  http://${TS_IP}:PUERTO  (WireGuard cifra el trafico)

${BOLD}Directorios:${NC}
  Config          ${PAIPERMC_ROOT}/
  Datos           ${DATA_ROOT}/
  Lean            ${PAIPERMC_ROOT}/lean/
  API keys        ${PAIPERMC_ROOT}/.env

${YELLOW}${BOLD}Pasos siguientes:${NC}

  1. Edita las API keys:
       nano ${PAIPERMC_ROOT}/.env

  2. Verifica desde ollintzin:
       curl http://${TS_IP}:${LITELLM_PORT}/health
       curl http://${TS_IP}:${LITELLM_PORT}/v1/models \
         -H 'Authorization: Bearer sk-phaimat-local'

  3. Prueba el agente writer:
       curl http://${TS_IP}:${LITELLM_PORT}/v1/chat/completions \
         -H 'Authorization: Bearer sk-phaimat-local' \
         -H 'Content-Type: application/json' \
         -d '{"model":"writer","messages":[{"role":"user","content":"Hello"}],"stream":false}'

  4. Ver logs:
       docker compose -f ${PAIPERMC_ROOT}/docker/docker-compose.yml logs -f

  5. Firewall — asegurate de que solo Tailscale puede llegar a los puertos:
       sudo firewall-cmd --zone=tailscale --add-port=8080/tcp --permanent
       sudo firewall-cmd --zone=tailscale --add-port=8081/tcp --permanent
       sudo firewall-cmd --reload

  5. Fase B: implementar paipermc-agent (Julia WebSocket server)

SUMMARY
