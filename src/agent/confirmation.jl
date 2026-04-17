# agent/confirmation.jl

@enum ConfirmAction WRITE_FILE FETCH_PAPER INDEX_PDF LEAN_COMPILE CALL_EXTERNAL SEARCH_EXTERNAL

struct FileChange
    path :: String
    diff :: String
    size :: Int
end

struct ConfirmRequest
    id        :: String
    action    :: ConfirmAction
    message   :: String
    files     :: Vector{FileChange}
    metadata  :: Dict{String,Any}
end

struct ConfirmResponse
    request_id :: String
    answer     :: Symbol
end

function requires_confirmation(action::ConfirmAction) :: Bool
    action in (WRITE_FILE, FETCH_PAPER, INDEX_PDF, LEAN_COMPILE, CALL_EXTERNAL, SEARCH_EXTERNAL)
end

function build_confirm_request(action::ConfirmAction, message::String;
    files    :: Vector{FileChange}    = FileChange[],
    metadata :: Dict{String,Any}      = Dict{String,Any}(),
) :: ConfirmRequest
    ConfirmRequest(string(UUIDs.uuid4()), action, message, files, metadata)
end
