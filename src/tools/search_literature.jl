export run

using HTTP, JSON3

const LITERATURE_SVC = Ref{String}("http://100.64.0.22:8081")

function set_host!(host::String)
    LITERATURE_SVC[] = host
end

function run(args::Dict, project_root::String) :: String
    query   = get(args, "query", "")
    sources = get(args, "sources", ["local"])
    n       = get(args, "n", 10)

    isempty(query) && return "Error: query is required"

    body = Dict("query" => query, "sources" => sources, "max_results" => n)

    try
        resp = HTTP.post(
            "$(LITERATURE_SVC[])/search",
            ["Content-Type" => "application/json"],
            JSON3.write(body);
            readtimeout = 30,
        )
        data = JSON3.read(resp.body)
        results = data["results"]

        isempty(results) && return "No results found for: $query"

        buf = IOBuffer()
        println(buf, "Found $(data["total"]) results for: $query\n")
        for (i, r) in enumerate(results)
            println(buf, "[$i] $(get(r, "title", "Unknown title"))")
            authors = get(r, "authors", [])
            !isempty(authors) && println(buf, "    Authors: $(join(authors[1:min(3,end)], ", "))")
            get(r, "year", nothing) !== nothing && println(buf, "    Year: $(r["year"])")
            get(r, "venue", nothing) !== nothing && println(buf, "    Venue: $(r["venue"])")
            get(r, "doi", nothing) !== nothing && println(buf, "    DOI: $(r["doi"])")
            get(r, "arxiv_id", nothing) !== nothing && println(buf, "    arXiv: $(r["arxiv_id"])")
            abstract = get(r, "abstract", nothing)
            if !isnothing(abstract) && !isempty(abstract)
                short = length(abstract) > 200 ? abstract[1:200] * "…" : abstract
                println(buf, "    Abstract: $short")
            end
            println(buf, "    Source: $(get(r, "source", "?")) | Score: $(round(get(r, "relevance_score", 0.0), digits=2))")
            println(buf)
        end
        String(take!(buf))

    catch e
        "Error searching literature: $(sprint(showerror, e))"
    end
end

end # module SearchLiterature

# ─────────────────────────────────────────────────────────────────────────────

export run


function run(args::Dict, project_root::String) :: String
    text = get(args, "text", "")
    isempty(text) && return "Error: text is required"

    messages = [
        Message("system", """You are a scientific writing expert. Improve the style
and clarity of the given LaTeX paragraph. Preserve all mathematical content
exactly. Return only the improved LaTeX paragraph, nothing else."""),
        Message("user", "Improve this paragraph:\n\n$text"),
    ]

    try
        response = chat_completion("reviewer-style", messages;
                                   temperature=0.3, max_tokens=2048)
        response.content
    catch e
        "Error improving paragraph: $(sprint(showerror, e))"
    end
end

end # module ImproveParagraph

# ─────────────────────────────────────────────────────────────────────────────

export run


function run(args::Dict, project_root::String) :: String
    latex = get(args, "latex", "")
    isempty(latex) && return "Error: latex is required"

    messages = [
        Message("system", """You are a LaTeX expert for mathematical physics.
Check if the given LaTeX is correct and compilable. If there are errors,
explain each error clearly and provide the corrected version.
Format your response as:
STATUS: valid|invalid
ERRORS: (list errors if any, or "none")
CORRECTED:
(corrected LaTeX code)"""),
        Message("user", "Check this LaTeX:\n\n$latex"),
    ]

    try
        response = chat_completion("mathematician", messages;
                                   temperature=0.1, max_tokens=2048)
        response.content
    catch e
        "Error checking LaTeX: $(sprint(showerror, e))"
    end
end

end # module CheckLatex

# ─────────────────────────────────────────────────────────────────────────────

export run

using Dates, JSON3

function run(args::Dict, project_root::String) :: String
    model   = get(args, "model", "claude-sonnet-4-5")
    content = get(args, "content", "")
    instruction = get(args, "instruction", "Review this content.")

    isempty(content) && return "Error: content is required"

    # Verificar que el modelo es externo
    model_cfg = resolve_model(model)
    (isnothing(model_cfg) || !model_cfg.requires_confirm) &&
        return "Error: call_external requires an external model (claude-*, gemini-*)"

    messages = [
        Message("user", "$instruction\n\n$content"),
    ]

    try
        response = chat_completion(model, messages; max_tokens=4096)

        # Log de uso de API
        log_path = joinpath(project_root, ".paipermc", "api_log.jsonl")
        mkpath(dirname(log_path))
        open(log_path, "a") do f
            println(f, JSON3.write(Dict(
                "timestamp" => string(now()),
                "model"     => model,
                "prompt_tokens" => response.usage["prompt_tokens"],
                "completion_tokens" => response.usage["completion_tokens"],
            )))
        end

        response.content
    catch e
        "Error calling external API: $(sprint(showerror, e))"
    end
end
