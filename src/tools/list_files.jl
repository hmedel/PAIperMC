# tools/list_files.jl

function list_files(args::Dict, project_root::String) :: String
    subpath = get(args, "path", "")
    pattern = get(args, "pattern", "*")
    base = isempty(subpath) ? project_root : normpath(joinpath(project_root, subpath))
    startswith(base, project_root) || return "Error: path outside project root"
    isdir(base) || return "Error: not a directory: $subpath"
    files = String[]
    for (root, dirs, names) in walkdir(base)
        filter!(d -> !startswith(d,"."), dirs)
        for f in names
            rel = relpath(joinpath(root,f), project_root)
            push!(files, rel)
        end
    end
    pattern != "*" && filter!(f->endswith(f, replace(pattern,"*"=>"")), files)
    sort!(files)
    isempty(files) && return "No files found"
    join(files, "\n")
end
