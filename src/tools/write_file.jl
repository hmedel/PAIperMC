# tools/write_file.jl

function write_file(args::Dict, project_root::String) :: String
    path    = get(args, "path", "")
    content = get(args, "content", "")
    mode    = get(args, "mode", "overwrite")
    isempty(path) && return "Error: path is required"
    full = normpath(joinpath(project_root, path))
    startswith(full, project_root) || return "Error: path outside project root"
    mkpath(dirname(full))
    tmp = full * ".tmp.$(getpid())"
    try
        if mode == "append" && isfile(full)
            write(tmp, read(full, String) * content)
        else
            write(tmp, content)
        end
        mv(tmp, full; force=true)
    catch e
        rm(tmp; force=true)
        return "Error: $(sprint(showerror, e))"
    end
    "Written: $path ($(length(content)) bytes)"
end
