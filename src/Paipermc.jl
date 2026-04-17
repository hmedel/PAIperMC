module Paipermc

using Logging

# ── Re-exports públicos ──────────────────────────────────────────────────────
export serve, repl, run_command

# ── Carga de submódulos en orden de dependencia ──────────────────────────────
include("project/config.jl")
include("project/workspace.jl")
include("project/scaffold.jl")

include("models/definitions.jl")
include("models/gateway.jl")
include("models/anthropic.jl")
include("models/selector.jl")

include("agent/history.jl")
include("agent/context.jl")
include("agent/router.jl")
include("agent/confirmation.jl")
include("agent/loop.jl")

include("tools/registry.jl")
include("tools/read_file.jl")
include("tools/write_file.jl")
include("tools/list_files.jl")
include("tools/search_literature.jl")
include("tools/fetch_paper.jl")
include("tools/improve_paragraph.jl")
include("tools/check_latex.jl")
include("tools/call_external.jl")

include("server/auth.jl")
include("server/session.jl")
include("server/agent_server.jl")

include("mcp/protocol.jl")
include("mcp/proxy.jl")
include("mcp/server.jl")

include("cli/renderer.jl")
include("cli/connection.jl")
include("cli/repl.jl")
include("cli/commands.jl")
include("cli/main.jl")

end # module
