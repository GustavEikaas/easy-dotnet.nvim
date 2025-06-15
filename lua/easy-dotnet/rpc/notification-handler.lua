local logger = require("easy-dotnet.logger")
local M = {}

---@param client DotnetClient
local function nuget_restore_handler(client, target_path) client:nuget_restore(target_path) end

---@param client DotnetClient
M.handler = function(client, method, params)
  if method == "request/restore" then
    logger.info("Server requested restore for " .. vim.fs.basename(params.targetPath))
    nuget_restore_handler(client, params.targetPath)
  else
    vim.print("Unknown server notification " .. method)
  end
end

return M
