local M = {}

---@class LSP_NotifyOpts
---@field client vim.lsp.Client         # The LSP client used to send the notification
---@field method string                 # LSP method name (e.g. "solution/open")
---@field params table                  # LSP request parameters object

---@param opts LSP_NotifyOpts
function M.create_lsp_notification(opts)
  return function()
    local success = opts.client:notify(opts.method, opts.params)
    if not success then error("Failed to send LSP notification " .. opts.method) end
  end
end

return M
