# precompile_paipermc.jl
# Script de tracing para PackageCompiler
# Ejecuta los caminos más comunes para que queden compilados en la sysimage

using Paipermc

# ── Tracing del gateway ──────────────────────────────────────────────────────
# Simula una llamada al modelo sin hacer HTTP real
import Paipermc.Gateway as GW
GW.set_host!("http://localhost:9999")   # puerto inválido — solo tracear tipos
GW.set_key!("sk-test")

msg = GW.Message("user", "hello")
msgs = GW.Message[msg]

# Tracear construcción de tipos
_ = GW.CompletionResponse("content", GW.ToolCall[], "writer", Dict("prompt_tokens"=>0, "completion_tokens"=>0))

# ── Tracing del router ───────────────────────────────────────────────────────
import Paipermc.Router as R
route = R.route_agent("mejora la introducción", nothing, nothing, "writer", false)
route = R.route_agent("busca papers sobre geometría de contacto", "main.tex", nothing, "writer", false)
route = R.route_agent("verifica el teorema 2 en Lean", nothing, nothing, "writer", false)
route = R.route_agent("\\begin{equation}", nothing, nothing, "writer", true)

# ── Tracing del historial ────────────────────────────────────────────────────
import Paipermc.History as H
hist = H.ConversationHistory("You are a writer.")
H.push_user!(hist, "hello")
H.push_assistant!(hist, "Hello!")
H.push_tool!(hist, "read_file", "File content here")
msgs_out = H.to_messages(hist)
H.trim_to_limit!(hist)
_ = H.summary(hist)

# ── Tracing de tools ─────────────────────────────────────────────────────────
import Paipermc.ListFiles as LF
import Paipermc.ReadFile as RF

# Listar archivos en directorio temporal
tmp = mktempdir()
write(joinpath(tmp, "main.tex"), "\\documentclass{article}")
write(joinpath(tmp, "refs.bib"), "@article{test, author={Test}}")

_ = LF.run(Dict("path" => "", "pattern" => "*.tex"), tmp)
_ = RF.run(Dict("path" => "main.tex"), tmp)
_ = RF.run(Dict("path" => "nonexistent.tex"), tmp)

import Paipermc.WriteFile as WF
_ = WF.run(Dict("path" => "test_output.txt", "content" => "test", "mode" => "overwrite"), tmp)

# ── Tracing del config ───────────────────────────────────────────────────────
import Paipermc.Config as C
_ = C.find_project_root(tmp)
_ = C.load_config(tmp)

# ── Tracing del ArgParse (CLI) ───────────────────────────────────────────────
# Simular parsing de argumentos comunes
import Paipermc.Main as M
# Los flags más comunes
for args in [
    String[],
    ["--model", "writer", "hello world"],
    ["--verbose", "status"],
    ["--help"],
]
    try M.parse_args_paipermc(args) catch end
end

# ── Tracing de JSON3 ─────────────────────────────────────────────────────────
using JSON3
_ = JSON3.write(Dict("type" => "token", "content" => "hello"))
_ = JSON3.read("""{"type":"done","session_id":"abc"}""", Dict{String,Any})

# ── Tracing de confirmaciones ────────────────────────────────────────────────
import Paipermc.Confirmation as Conf
req = Conf.build_confirm_request(
    Conf.WRITE_FILE,
    "paipermc wants to write main.tex",
    files = [Conf.FileChange("main.tex", "+ new line", 42)],
)
_ = Conf.format_confirm_cli(req)
_ = Conf.requires_confirmation(Conf.WRITE_FILE)
_ = Conf.requires_confirmation(Conf.CALL_EXTERNAL)

# ── Tracing del registry ─────────────────────────────────────────────────────
import Paipermc.ToolRegistry as TR
registry = TR.build_registry(tmp)
_ = TR.TOOL_SPECS

println("Precompile tracing complete")

# Cleanup
rm(tmp, recursive=true)
