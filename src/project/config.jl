# src/project/config.jl
module Config

using TOML
export ProjectConfig, load_config, find_project_root

struct ProjectConfig
    name         :: String
    main         :: String
    journal      :: String
    style        :: String
    language     :: String
    bib          :: String
    server_host  :: String
    server_port  :: Int
    server_key   :: String
    lean_dir     :: String
    sources      :: Vector{String}
end

function load_config(root::String) :: ProjectConfig
    toml_path = joinpath(root, "papermind.toml")
    isfile(toml_path) || return _defaults(root)
    cfg = TOML.parsefile(toml_path)
    p   = get(cfg, "project",   Dict())
    s   = get(cfg, "server",    Dict())
    l   = get(cfg, "literature", Dict())
    f   = get(cfg, "formal",    Dict())

    ProjectConfig(
        get(p, "name",     basename(root)),
        get(p, "main",     "main.tex"),
        get(p, "journal",  ""),
        get(p, "style",    ""),
        get(p, "language", "en"),
        get(l, "bib",      "refs.bib"),
        get(s, "host",     "100.64.0.22"),
        get(s, "port",     9000),
        get(s, "key",      "sk-phaimat-agent"),
        get(f, "lean_dir", ".paipermc/lean"),
        get(l, "sources",  ["local", "semantic_scholar", "arxiv"]),
    )
end

function find_project_root(start::String = pwd()) :: String
    dir = abspath(start)
    while true
        isfile(joinpath(dir, "papermind.toml")) && return dir
        parent = dirname(dir)
        parent == dir && break
        dir = parent
    end
    start
end

function _defaults(root::String) :: ProjectConfig
    ProjectConfig(
        basename(root), "main.tex", "", "", "en", "refs.bib",
        "100.64.0.22", 9000, "sk-phaimat-agent",
        ".paipermc/lean", ["local", "arxiv"],
    )
end

end # module Config
