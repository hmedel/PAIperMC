# tools/improve_paragraph.jl

function improve_paragraph(args::Dict, project_root::String) :: String
    text = get(args, "text", "")
    isempty(text) && return "Error: text is required"
    msgs = [GatewayMessage("system","Improve the style of this LaTeX paragraph. Preserve math. Return only the improved paragraph."),
            GatewayMessage("user", text)]
    try
        resp = chat_completion("reviewer-style", msgs; temperature=0.3, max_tokens=2048)
        resp.content
    catch e
        "Error: $(sprint(showerror,e))"
    end
end
