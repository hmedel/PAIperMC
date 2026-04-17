# tools/registry.jl

const TOOL_SPECS = Dict[]   # populated after tool functions are defined

function build_tool_registry(project_root::String) :: Dict{String,Function}
    Dict{String,Function}(
        "read_file"         => (args,root) -> read_file(args, root),
        "search_literature" => (args,root) -> search_literature(args, root),
    )
end
