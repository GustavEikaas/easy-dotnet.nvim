local constants = require("easy-dotnet.constants")

---@type table<vim.lsp.protocol.Method, fun(params: table, callback:fun(err: lsp.ResponseError?, result: any))>
local handlers = {}

local M = {}

---@param callback fun(err?: lsp.ResponseError, result: lsp.InitializeResult)
handlers["initialize"] = function(_, callback)
  callback(nil, {
    capabilities = {
      textDocumentSync = 1,
      codeActionProvider = true,
    },
    serverInfo = {
      name = constants.lsp_in_process_client_name,
    },
  })
end

---@param params lsp.CodeActionParams
handlers["textDocument/codeAction"] = function(params, callback) require("easy-dotnet.in-process-lsp.import-missing-namespaces").register_action(params, callback) end

function M.enable()
  local import_missing_namespaces = require("easy-dotnet.in-process-lsp.import-missing-namespaces")

  ---@type vim.lsp.Config
  vim.lsp.config(constants.lsp_in_process_client_name, {
    filetypes = { "cs" },
    cmd = function(_)
      return {
        request = function(method, params, callback)
          if handlers[method] then handlers[method](params, callback) end
        end,
        notify = function() end,
        is_closing = function() return false end,
        terminate = function() end,
      }
    end,
    commands = {
      [import_missing_namespaces.command_name] = function(command)
        local bufnr = command.arguments and command.arguments[1]
        import_missing_namespaces.run(bufnr)
      end,
    },
  })

  vim.lsp.enable(constants.lsp_in_process_client_name)
end

return M
