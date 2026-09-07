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
    ---@param dispatchers vim.lsp.rpc.Dispatchers
    ---@return vim.lsp.rpc.PublicClient
    cmd = function(dispatchers)
      local closing = false
      local request_id = 0
      local function close()
        if closing then return end
        closing = true
        vim.schedule(function() dispatchers.on_exit(0, 0) end)
      end

      return {
        request = function(method, params, callback)
          if closing then return false end

          request_id = request_id + 1

          if method == "shutdown" then
            callback(nil, nil, request_id)
          elseif handlers[method] then
            handlers[method](params, callback)
          else
            callback({ code = -32601, message = "Method not found: " .. method }, nil, request_id)
          end

          return true, request_id
        end,
        notify = function(method)
          if closing then return false end
          if method == "exit" then close() end
          return true
        end,
        is_closing = function() return closing end,
        terminate = close,
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
