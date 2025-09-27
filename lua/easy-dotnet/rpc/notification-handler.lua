local logger = require("easy-dotnet.logger")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local M = {}

---@param client DotnetClient
local function nuget_restore_handler(client, target_path) client.nuget:nuget_restore(target_path) end

---@param client DotnetClient
M.handler = function(client, method, params)
  coroutine.wrap(function()
    if method == "request/restore" then
      logger.info("Server requested restore for " .. vim.fs.basename(params.targetPath))
      nuget_restore_handler(client, params.targetPath)
    elseif method == "project/changed" then
      csproj_parse.invalidate(params.projectPath)
      csproj_parse.get_project_from_project_file(params.projectPath)
    elseif method == "lsp/ready" then
      vim.print("LSP IS FULLY READY")
    else
      vim.print("Unknown server notification " .. method)
    end
  end)()
end

return M
