export run

const MAX_TOKENS = 8000   # ~32000 chars antes de truncar

function run(args::Dict, project_root::String) :: String
    path = get(args, "path", "")
    isempty(path) && return "Error: path is required"

    # Seguridad: no salir del proyecto
    full_path = normpath(joinpath(project_root, path))
    startswith(full_path, project_root) ||
        return "Error: path outside project root"

    isfile(full_path) || return "Error: file not found: $path"

    content = read(full_path, String)
    lines   = split(content, '\n')
    n_lines = length(lines)

    # Añadir números de línea
    numbered = join(["$(lpad(i,4))  $(lines[i])" for i in eachindex(lines)], '\n')

    # Truncar si es muy largo
    if length(numbered) > MAX_TOKENS * 4
        numbered = numbered[1:MAX_TOKENS*4]
        return "[File: $path ($n_lines lines, truncated to $(MAX_TOKENS) tokens)]\n$numbered\n[... truncated ...]"
    end

    "[File: $path ($n_lines lines)]\n$numbered"
end

end # module ReadFile

# ─────────────────────────────────────────────────────────────────────────────

export run

using Dates

function run(args::Dict, project_root::String) :: String
    path    = get(args, "path", "")
    content = get(args, "content", "")
    mode    = get(args, "mode", "overwrite")

    isempty(path)    && return "Error: path is required"
    isempty(content) && return "Error: content is required"

    full_path = normpath(joinpath(project_root, path))
    startswith(full_path, project_root) ||
        return "Error: path outside project root"

    # Crear directorio si no existe
    mkpath(dirname(full_path))

    # Escribir (atómico: temp file + rename)
    tmp = full_path * ".tmp.$(getpid())"
    try
        if mode == "append" && isfile(full_path)
            existing = read(full_path, String)
            write(tmp, existing * content)
        else
            write(tmp, content)
        end
        mv(tmp, full_path; force=true)
    catch e
        rm(tmp; force=true)
        return "Error writing file: $(sprint(showerror, e))"
    end

    # Log de escritura
    log_path = joinpath(project_root, ".paipermc", "write_log.jsonl")
    mkpath(dirname(log_path))
    open(log_path, "a") do f
        println(f, """{"timestamp":"$(now())","path":"$path","mode":"$mode","bytes":$(length(content))}""")
    end

    "Written: $path ($(length(content)) bytes, mode=$mode)"
end

end # module WriteFile

# ─────────────────────────────────────────────────────────────────────────────

export run

function run(args::Dict, project_root::String) :: String
    subpath = get(args, "path", "")
    pattern = get(args, "pattern", "*")

    base = isempty(subpath) ? project_root :
           normpath(joinpath(project_root, subpath))
    startswith(base, project_root) || return "Error: path outside project root"
    isdir(base) || return "Error: directory not found: $subpath"

    # Recolectar archivos recursivamente
    files = String[]
    for (root, dirs, filenames) in walkdir(base)
        # Ignorar directorios ocultos y .paipermc
        filter!(d -> !startswith(d, ".") && d != "__pycache__", dirs)
        for f in filenames
            full = joinpath(root, f)
            rel  = relpath(full, project_root)
            push!(files, rel)
        end
    end

    # Filtrar por patrón si se especificó
    if pattern != "*"
        ext = replace(pattern, "*" => "")
        filter!(f -> endswith(f, ext), files)
    end

    sort!(files)
    isempty(files) && return "No files found in $subpath"

    # Formato con tamaño
    buf = IOBuffer()
    println(buf, "Files in $(isempty(subpath) ? "project root" : subpath):")
    for f in files
        full = joinpath(project_root, f)
        sz   = isfile(full) ? filesize(full) : 0
        println(buf, "  $(lpad(_fmt_size(sz), 8))  $f")
    end
    println(buf, "\n$(length(files)) files")
    String(take!(buf))
end

function _fmt_size(bytes::Int) :: String
    bytes < 1024      && return "$(bytes)B"
    bytes < 1024^2    && return "$(round(bytes/1024, digits=1))KB"
    return "$(round(bytes/1024^2, digits=1))MB"
end
