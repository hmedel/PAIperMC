# tools/search_literature.jl

const LITERATURE_SVC = Ref{String}("http://100.64.0.22:8081")

function set_literature_host!(host::String)
    LITERATURE_SVC[] = host
end

function search_literature(args::Dict, project_root::String) :: String
    query   = get(args, "query", "")
    sources = get(args, "sources", ["local"])
    n       = get(args, "n", 10)
    isempty(query) && return "Error: query is required"
    body = Dict("query"=>query, "sources"=>sources, "max_results"=>n)
    try
        resp = HTTP.post(
            "$(LITERATURE_SVC[])/search",
            ["Content-Type"=>"application/json"],
            JSON3.write(body); readtimeout=30,
        )
        data = JSON3.read(resp.body)
        results = data["results"]
        isempty(results) && return "No results for: $query"
        buf = IOBuffer()
        println(buf, "Found $(data["total"]) results for: $query\n")
        for (i,r) in enumerate(results)
            println(buf, "[$i] $(get(r,"title","?"))")
            println(buf, "    $(join(get(r,"authors",[]),"," ))")
            yr = get(r,"year",nothing); !isnothing(yr) && println(buf,"    Year: $yr")
            doi = get(r,"doi",nothing); !isnothing(doi) && println(buf,"    DOI: $doi")
            println(buf)
        end
        String(take!(buf))
    catch e
        "Error: $(sprint(showerror,e))"
    end
end
