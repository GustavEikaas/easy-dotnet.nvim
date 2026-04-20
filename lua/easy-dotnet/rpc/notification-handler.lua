local jobs = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local constants = require("easy-dotnet.constants")
local M = {}

local active_server_finish_callbacks = {}

local function handle_quickfix_set(params, silent)
  require("easy-dotnet.test-runner.render").hide()
  local items = vim.tbl_map(
    function(value)
      return {
        filename = value.fileName,
        lnum = value.lineNumber,
        col = value.columnNumber,
        text = value.text,
        type = value.type == 2 and "E" or value.type == 1 and "W" or "I",
      }
    end,
    params
  )
  vim.fn.setqflist({}, " ", {
    title = constants.server_quickfix_title,
    items = items,
  })
  if not silent then vim.cmd("copen") end
end

---@param client easy-dotnet.RPC.Client.Dotnet
local function nuget_restore_handler(client, target_path) client.nuget:nuget_restore(target_path) end

---@param client easy-dotnet.RPC.Client.Dotnet
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
    elseif method == "quickfix/set" then
      handle_quickfix_set(params, false)
    elseif method == "quickfix/set-silent" then
      handle_quickfix_set(params, true)
    elseif method == "quickfix/close" then
      local info = vim.fn.getqflist({ title = 1 })
      local our_qf = info.title == constants.server_quickfix_title
      if our_qf then
        vim.fn.setqflist({})
        vim.cmd("cclose")
      end
    elseif method == "registerTest" then
      local state = require("easy-dotnet.test-runner.state")
      local render = require("easy-dotnet.test-runner.render")
      local buffer = require("easy-dotnet.test-runner.buffer")
      if not params or not params.test then return end
      vim.schedule(function()
        state.register(params.test)
        if params.test.filePath then buffer.attach(params.test.filePath, client) end
        render.refresh()
      end)
    elseif method == "removeTest" then
      local state = require("easy-dotnet.test-runner.state")
      local render = require("easy-dotnet.test-runner.render")
      local buffer = require("easy-dotnet.test-runner.buffer")
      if not params or not params.id then return end
      vim.schedule(function()
        local node = state.nodes[params.id]
        state.nodes[params.id] = nil
        if node and node.filePath then buffer.apply_signs(node.filePath) end
        render.refresh()
      end)
    elseif method == "updateStatus" then
      local state = require("easy-dotnet.test-runner.state")
      local render = require("easy-dotnet.test-runner.render")
      local buffer = require("easy-dotnet.test-runner.buffer")
      if not params or not params.id then return end
      vim.schedule(function()
        state.update_status(params.id, params.status, params.availableActions)
        local node = state.nodes[params.id]
        if node then buffer.on_status_update(node) end
        render.refresh()
      end)
    elseif method == "refreshTestSigns" then
      local buffer = require("easy-dotnet.test-runner.buffer")
      local project_id = params and params.projectId or nil
      vim.schedule(function() buffer.refresh_signs(project_id) end)
    elseif method == "testrunner/statusUpdate" then
      local state = require("easy-dotnet.test-runner.state")
      local render = require("easy-dotnet.test-runner.render")
      if not params then return end
      vim.schedule(function()
        state.update_runner_status(params)
        render.refresh()
      end)
    elseif method == "updateStatusBatch" then
      local state = require("easy-dotnet.test-runner.state")
      local render = require("easy-dotnet.test-runner.render")
      local buffer = require("easy-dotnet.test-runner.buffer")
      if not params or not params.updates then return end
      vim.schedule(function()
        for _, update in ipairs(params.updates) do
          state.update_status(update.id, update.status, update.availableActions)
          local node = state.nodes[update.id]
          if node then buffer.on_status_update(node) end
        end
        render.refresh()
      end)
    elseif method == "upgradeWizard/initialized" then
      local state = require("easy-dotnet.package-upgrade.state")
      local render = require("easy-dotnet.package-upgrade.render")
      if not params or not params.candidates then return end
      vim.schedule(function()
        state.candidates = params.candidates
        state.auto_select_safe()
        render.refresh()
      end)
    elseif method == "upgradeWizard/status" then
      local state = require("easy-dotnet.package-upgrade.state")
      local render = require("easy-dotnet.package-upgrade.render")
      if not params then return end
      vim.schedule(function()
        state.status = params
        render.refresh()
      end)
    elseif method == "upgradeWizard/progress" then
      local state = require("easy-dotnet.package-upgrade.state")
      local render = require("easy-dotnet.package-upgrade.render")
      if not params then return end
      vim.schedule(function()
        state.progress = params
        render.refresh()
      end)
    elseif method == "upgradeWizard/result" then
      local state = require("easy-dotnet.package-upgrade.state")
      local render = require("easy-dotnet.package-upgrade.render")
      if not params then return end
      vim.schedule(function()
        state.result = params
        render.refresh()
      end)
    else
      vim.print("Unknown server notification " .. method)
    end
  end)()
end

return M
