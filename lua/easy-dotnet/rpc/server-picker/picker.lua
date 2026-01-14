local M = {
  pickers = {},
}

---@class easy-dotnet.RPC.Picker
---@field supports_auto_cancel_detection boolean
---@field pick fun(title: string, options: easy-dotnet.RPC.PromptSelection[], on_select: fun(selection_id: string), on_cancel: fun(), register_cancel_callback: fun(cb: fun())): nil

function M.pick(title, options, respond)
  require("easy-dotnet.rpc.server-picker._telescope-server-picker").pick(title, options, function(selection_id)
    vim.print("responding", selection_id)
    respond(selection_id)
  end, function()
    vim.print("user cancelled")
    respond(vim.NIL)
  end, function() end)
end

return M
