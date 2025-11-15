local progress = require("easy-dotnet.roslyn.progress")

local M = {}

---@class LSP_CallHandle
---@field id integer                    # LSP request ID
---@field cancel fun()                  # cancel the in-flight request

---@class LSP_CallOpts
---@field client vim.lsp.Client         # The LSP client used to send the request
---@field method string                 # LSP method name (e.g. "textDocument/definition")
---@field params table                  # LSP request parameters object
---@field supports_progress boolean     # If true, attach $/progress spinner
---@field on_progress? fun(progress: ProgressMessage)
---@field on_result? fun(result:any, ctx:table)  # Called on success
---@field on_error? fun(err:table, ctx:table)    # Called on LSP error

---@param opts LSP_CallOpts
---@return fun():LSP_CallHandle
function M.create_lsp_call(opts)
  return function()
    local token, unsubscribe

    if opts.supports_progress or opts.on_progress then
      token, unsubscribe = progress.generate_token(function(...)
        if opts.on_progress then opts.on_progress(...) end
      end)
      opts.params = opts.params or {}
      opts.params.partialResultToken = token
    end

    local success, id = opts.client:request(opts.method, opts.params, function(err, result, ctx)
      if unsubscribe then unsubscribe() end

      if err then
        if opts.on_error then opts.on_error(err, ctx) end
        return
      end

      if opts.on_result then opts.on_result(result, ctx) end
    end)

    if not success or not id then
      if unsubscribe then unsubscribe() end
      error("Failed to send LSP request " .. opts.method)
    end

    return {
      id = id,
      cancel = function()
        opts.client:cancel_request(id)
        if unsubscribe then unsubscribe() end
      end,
    }
  end
end

return M
