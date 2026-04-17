# tools/check_latex.jl

function check_latex(args::Dict, project_root::String) :: String
    latex = get(args, "latex", "")
    isempty(latex) && return "Error: latex is required"
    msgs = [GatewayMessage("system","Check if this LaTeX is correct. Reply: STATUS: valid|invalid\nERRORS: ...\nCORRECTED:\n..."),
            GatewayMessage("user", latex)]
    try
        resp = chat_completion("mathematician", msgs; temperature=0.1, max_tokens=2048)
        resp.content
    catch e
        "Error: $(sprint(showerror,e))"
    end
end
