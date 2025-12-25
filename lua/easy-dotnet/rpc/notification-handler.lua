local jobs = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local M = {}

local active_server_finish_callbacks = {}

---@param client DotnetClient
local function nuget_restore_handler(client, target_path) client.nuget:nuget_restore(target_path) end

---@param client DotnetClient
M.handler = function(client, method, params)
  coroutine.wrap(function()
    if method == "$/progress" then
      local token = params.token
      local value = params.value

      if value.kind == "begin" then
        local job_data = {
          name = value.message or "Dotnet Task",
          on_success_text = value.message or "Done",
          timeout = -1,
          is_server_job = true,
          server_token = token,
        }

        active_server_finish_callbacks[token] = jobs.register_job(job_data)
      elseif value.kind == "report" then
        local msg = value.message or ""
        if value.percentage then msg = string.format("%s (%d%%)", msg, value.percentage) end
        jobs.update_server_job(token, msg)
      elseif value.kind == "end" then
        local finish_fn = active_server_finish_callbacks[token]
        if finish_fn then
          finish_fn(true)
          active_server_finish_callbacks[token] = nil
        end
      end
    elseif method == "request/restore" then
      logger.info("Server requested restore for " .. vim.fs.basename(params.targetPath))
      nuget_restore_handler(client, params.targetPath)
    elseif method == "_server/update-available" then
      logger.info(string.format("easy-dotnet-server %s update available, update using `:Dotnet _server update`", params.updateType))
    elseif method == "project/changed" then
      csproj_parse.invalidate(params.projectPath)
      csproj_parse.get_project_from_project_file(params.projectPath)
    elseif method == "displayError" then
      logger.error(params.message)
    elseif method == "displayWarning" then
      logger.warn(params.message)
    elseif method == "displayMessage" then
      logger.info(params.message)
    else
      vim.print("Unknown server notification " .. method)
    end
  end)()
end

return M
