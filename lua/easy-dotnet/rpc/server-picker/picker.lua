local M = {
  pickers = {},
}

---@class easy-dotnet.RPC.Picker
---@field supports_auto_cancel_detection boolean
---@field pick fun(title: string, options: easy-dotnet.RPC.PromptSelection[], on_select: fun(selection_id: string), on_cancel: fun(), register_cancel_callback: fun(cb: fun())): nil

function M.pick()
  --TODO: choose picker
end

return M
