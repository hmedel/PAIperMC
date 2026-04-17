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
