local jobs = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local constants = require("easy-dotnet.constants")
local M = {}

local active_server_finish_callbacks = {}

local function handle_project_changed() end

local function handle_quickfix_set(params, silent)
  require("easy-dotnet.test-runner.render").hide()
  if not silent then require("easy-dotnet.project-view.render").hide() end
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
    elseif method == "_server/update-available" then
      logger.info(string.format("easy-dotnet-server %s update available, update using `:Dotnet _server update`", params.updateType))
    elseif method == "roslyn/update-available" then
      local lsp_opts = require("easy-dotnet.options").get_option("lsp")
      if lsp_opts and lsp_opts.suggest_updates == false then return end
      local current = params.currentVersion or "unknown"
      local latest = params.availableVersion or "unknown"
      if params.isBelowRecommended then
        logger.warn(string.format("roslyn-language-server %s is below the recommended version %s. Update using `dotnet-easydotnet roslyn update`", current, params.minimumRecommendedVersion or latest))
      else
        logger.info(string.format("roslyn-language-server update available: %s -> %s. Update using `dotnet-easydotnet roslyn update`", current, latest))
      end
    elseif method == "project/changed" then
      handle_project_changed()
    elseif method == "activeProject/changed" then
      require("easy-dotnet.active-project").set(params)
    elseif method == "runningProcesses/changed" then
      vim.schedule(function() require("easy-dotnet.running-sessions").set(params) end)
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
    elseif method == "solution/projects-loaded" then
      vim.notify("Solution loaded")
    elseif method == "registerTest" then
      local state = require("easy-dotnet.test-runner.state")
      local render = require("easy-dotnet.test-runner.render")
      local buffer = require("easy-dotnet.test-runner.buffer")
      if not params or not params.test then return end
      vim.schedule(function()
        state.register(params.test)
        if params.test.filePath then buffer.attach(params.test.filePath, client) end
        render.refresh()
        require("easy-dotnet.neotest.events").emit("registerTest", params.test)
      end)
    elseif method == "projectview/update" then
      local pv_state = require("easy-dotnet.project-view.state")
      local pv_render = require("easy-dotnet.project-view.render")
      if not params or not params.header then return end
      if pv_state.project_path and params.header.projectPath == pv_state.project_path then
        vim.schedule(function()
          pv_state.snapshot = params
          pv_render.schedule_refresh()
        end)
      end
    elseif method == "projectview/status" then
      local pv_state = require("easy-dotnet.project-view.state")
      local pv_render = require("easy-dotnet.project-view.render")
      if not params or not params.projectPath then return end
      if pv_state.project_path and params.projectPath == pv_state.project_path then
        vim.schedule(function()
          pv_state.set_status(params.isLoading and true or false, params.operation)
          pv_render.schedule_refresh()
        end)
      end
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
        render.schedule_refresh()
        require("easy-dotnet.neotest.events").emit("updateStatus", params.id, params.status)
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
        render.schedule_refresh()
      end)
    elseif method == "updateStatusBatch" then
      local state = require("easy-dotnet.test-runner.state")
      local render = require("easy-dotnet.test-runner.render")
      local buffer = require("easy-dotnet.test-runner.buffer")
      local events = require("easy-dotnet.neotest.events")
      if not params or not params.updates then return end
      vim.schedule(function()
        local affected_files = {}
        for _, update in ipairs(params.updates) do
          state.update_status(update.id, update.status, update.availableActions)
          local node = state.nodes[update.id]
          if node and node.filePath then affected_files[node.filePath] = true end
          events.emit("updateStatus", update.id, update.status)
        end
        for file in pairs(affected_files) do
          buffer.apply_signs(file)
        end
        render.schedule_refresh()
      end)
    else
      vim.print("Unknown server notification " .. method)
    end
  end)()
end

return M
