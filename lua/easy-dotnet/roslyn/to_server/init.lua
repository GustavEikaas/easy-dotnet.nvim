local run_tests = require("easy-dotnet.roslyn.to_server.requests.run_tests")
local project_open = require("easy-dotnet.roslyn.to_server.notifications.project_open")
local solution_open = require("easy-dotnet.roslyn.to_server.notifications.solution_open")

---@class RoslynLspClient
---@field client vim.lsp.Client
---@field requests table
---@field notifications table
---@field refresh_document fun()

local M = {}

---@param client_id number
---@return RoslynLspClient
M.from_client_id = function(client_id)
  assert(client_id, "[RoslynClient] client_id is required")
  local client = vim.lsp.get_client_by_id(client_id)
  assert(client, string.format("[RoslynClient] no client with id %d found", client_id))
  return M.from_client(client)
end

---@param client vim.lsp.Client
---@return RoslynLspClient
M.from_client = function(client)
  assert(client, "[RoslynClient] client is required")
  local obj = {}
  obj.client = client
  obj.refresh_document = function()
    local bufnr = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    local params = {
      textDocument = {
        uri = vim.uri_from_bufnr(bufnr),
        version = vim.lsp.util.buf_versions[bufnr] or 0,
      },
      contentChanges = {},
    }

    client:notify("textDocument/didChange", params)
  end
  obj.requests = {
    run_tests = function(params, on_res, on_err) run_tests.run_tests(client, params, on_res, on_err) end,
  }
  obj.notifications = {
    project_open = function(params) project_open.projects_open(client, params) end,
    solution_open = function(params) solution_open.solution_open(client, params) end,
  }
  return obj
end

return M
