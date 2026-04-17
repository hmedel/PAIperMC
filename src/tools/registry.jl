export build_registry, TOOL_SPECS

# ── Especificaciones de tools en formato OpenAI ──────────────────────────────
# Estas specs se envían al modelo para que sepa qué herramientas puede invocar

const TOOL_SPECS = [

    Dict(
        "type" => "function",
        "function" => Dict(
            "name" => "read_file",
            "description" => "Read a file from the active project. Use this to understand the current state of the paper before suggesting changes.",
            "parameters" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "path" => Dict("type" => "string",
                                   "description" => "Relative path within project root"),
                ),
                "required" => ["path"],
            ),
        ),
    ),

    Dict(
        "type" => "function",
        "function" => Dict(
            "name" => "write_file",
            "description" => "Write content to a file in the active project. Requires user confirmation. Always read the file first to understand its current content.",
            "parameters" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "path"    => Dict("type" => "string",
                                     "description" => "Relative path within project root"),
                    "content" => Dict("type" => "string",
                                     "description" => "Complete new file content"),
                    "mode"    => Dict("type" => "string",
                                     "enum" => ["overwrite", "append"],
                                     "description" => "Write mode (default: overwrite)"),
                ),
                "required" => ["path", "content"],
            ),
        ),
    ),

    Dict(
        "type" => "function",
        "function" => Dict(
            "name" => "list_files",
            "description" => "List files in the active project directory.",
            "parameters" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "path"    => Dict("type" => "string",
                                     "description" => "Subdirectory to list (default: project root)"),
                    "pattern" => Dict("type" => "string",
                                     "description" => "Glob pattern, e.g. *.tex"),
                ),
            ),
        ),
    ),

    Dict(
        "type" => "function",
        "function" => Dict(
            "name" => "search_literature",
            "description" => "Search for academic papers. Always search local index first. Use external sources only when local results are insufficient.",
            "parameters" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "query"   => Dict("type" => "string",
                                     "description" => "Search query"),
                    "sources" => Dict("type" => "array",
                                     "items" => Dict("type" => "string",
                                                     "enum" => ["local", "semantic_scholar",
                                                                "arxiv", "openalex",
                                                                "nasa_ads", "perplexity"]),
                                     "description" => "Sources to query (default: [local])"),
                    "n"       => Dict("type" => "integer",
                                     "description" => "Max results (default: 10)"),
                ),
                "required" => ["query"],
            ),
        ),
    ),

    Dict(
        "type" => "function",
        "function" => Dict(
            "name" => "improve_paragraph",
            "description" => "Improve the style and clarity of a LaTeX paragraph without changing its technical content.",
            "parameters" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "text" => Dict("type" => "string",
                                   "description" => "LaTeX paragraph to improve"),
                ),
                "required" => ["text"],
            ),
        ),
    ),

    Dict(
        "type" => "function",
        "function" => Dict(
            "name" => "check_latex",
            "description" => "Validate and correct a LaTeX math fragment. Returns corrected LaTeX and explanation of any errors found.",
            "parameters" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "latex" => Dict("type" => "string",
                                   "description" => "LaTeX fragment to check"),
                ),
                "required" => ["latex"],
            ),
        ),
    ),

]

# ── Construcción del registro de funciones ───────────────────────────────────
"""
Construye el Dict{String, Function} con todas las herramientas disponibles.
Cada función recibe (args::Dict, project_root::String) y retorna String.
"""
function build_registry(project_root::String) :: Dict{String, Function}
    Dict{String, Function}(
        "read_file"          => (args, root) -> run(args, root),
        "write_file"         => (args, root) -> run(args, root),
        "list_files"         => (args, root) -> run(args, root),
        "search_literature"  => (args, root) -> run(args, root),
        "improve_paragraph"  => (args, root) -> run(args, root),
        "check_latex"        => (args, root) -> run(args, root),
    )
end
