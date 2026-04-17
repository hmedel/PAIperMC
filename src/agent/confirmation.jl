export ConfirmRequest, ConfirmResponse, ConfirmAction,
       requires_confirmation, build_confirm_request,
       CONFIRM_TIMEOUT

using Dates

# ── Tipos de acción que requieren confirmación ───────────────────────────────
@enum ConfirmAction begin
    WRITE_FILE
    FETCH_PAPER       # descarga PDF + modifica índice
    INDEX_PDF
    LEAN_COMPILE
    CALL_EXTERNAL     # Anthropic, Gemini, AlphaProof
    SEARCH_EXTERNAL   # arXiv, S2, Elicit, etc.
end

const CONFIRM_TIMEOUT = 120  # segundos antes de cancelar si no hay respuesta

# ── Request de confirmación (enviado al cliente) ─────────────────────────────
struct FileChange
    path    :: String
    diff    :: String       # unified diff o descripción del cambio
    size    :: Int          # bytes aproximados
end

struct ConfirmRequest
    id        :: String          # UUID para correlacionar con response
    action    :: ConfirmAction
    message   :: String          # descripción human-readable
    files     :: Vector{FileChange}
    metadata  :: Dict{String,Any}
    timestamp :: DateTime
end

# ── Response de confirmación (recibido del cliente) ──────────────────────────
struct ConfirmResponse
    request_id :: String
    answer     :: Symbol   # :yes | :no | :skip | :edit
end

# ── Lógica de permisos ───────────────────────────────────────────────────────
"""
¿Esta acción requiere confirmación del usuario?
Las lecturas y búsquedas locales son siempre autónomas.
"""
function requires_confirmation(action::ConfirmAction) :: Bool
    action in (WRITE_FILE, FETCH_PAPER, INDEX_PDF,
                LEAN_COMPILE, CALL_EXTERNAL, SEARCH_EXTERNAL)
end

# ── Construcción de requests ─────────────────────────────────────────────────
function build_confirm_request(
    action   :: ConfirmAction,
    message  :: String;
    files    :: Vector{FileChange} = FileChange[],
    metadata :: Dict{String,Any}   = Dict{String,Any}(),
) :: ConfirmRequest
    ConfirmRequest(
        string(Base.UUID(rand(UInt128))),
        action,
        message,
        files,
        metadata,
        now(),
    )
end

"""
Genera un diff legible entre contenido original y nuevo.
"""
function make_diff(original::String, new_content::String, path::String) :: String
    orig_lines = split(original, '\n')
    new_lines  = split(new_content, '\n')

    buf = IOBuffer()
    println(buf, "--- a/$(path)")
    println(buf, "+++ b/$(path)")

    # Diff simplificado — líneas eliminadas y añadidas
    # Para una implementación completa usar DeepDiffs.jl
    for line in orig_lines
        line ∉ new_lines && println(buf, "- $line")
    end
    for line in new_lines
        line ∉ orig_lines && println(buf, "+ $line")
    end

    String(take!(buf))
end

"""
Texto de confirmación para la terminal (modo CLI).
"""
function format_confirm_cli(req::ConfirmRequest) :: String
    buf = IOBuffer()

    println(buf, "\n  \033[1mpaipermc wants to $(action_label(req.action))\033[0m")

    for f in req.files
        println(buf, "\n  ┌─ $(f.path) ─────────────────────────────────────")
        for line in split(f.diff, '\n')[1:min(20, end)]
            startswith(line, "+") && print(buf, "\033[32m")
            startswith(line, "-") && print(buf, "\033[31m")
            println(buf, "  │ $line\033[0m")
        end
        println(buf, "  └────────────────────────────────────────────────")
    end

    isempty(req.files) && println(buf, "\n  $(req.message)")
    println(buf, "\n  Allow? [y/n/s(kip)]")

    String(take!(buf))
end

function action_label(a::ConfirmAction) :: String
    a == WRITE_FILE      && return "write files"
    a == FETCH_PAPER     && return "download papers and update index"
    a == INDEX_PDF       && return "index PDF into the project"
    a == LEAN_COMPILE    && return "compile Lean 4 on xolotl"
    a == CALL_EXTERNAL   && return "call external API"
    a == SEARCH_EXTERNAL && return "query external academic APIs"
    "perform action"
end
