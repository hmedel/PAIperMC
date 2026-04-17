# tools/read_file.jl

function read_file(args::Dict, project_root::String) :: String
    path = get(args, "path", "")
    isempty(path) && return "Error: path is required"
    full = normpath(joinpath(project_root, path))
    startswith(full, project_root) || return "Error: path outside project root"
    isfile(full) || return "Error: file not found: $path"
    content = read(full, String)
    lines   = split(content, '\n')
    n       = length(lines)
    numbered = join(["$(lpad(i,4))  $(lines[i])" for i in eachindex(lines)], '\n')
    length(numbered) > 32000 && (numbered = numbered[1:32000]*"\n[... truncated ...]")
    "[File: $path ($n lines)]\n$numbered"
end
