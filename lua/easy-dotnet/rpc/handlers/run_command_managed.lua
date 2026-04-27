---@class easy-dotnet.Job.TrackedJob
---@field jobId string
---@field slotId string|nil
---@field command easy-dotnet.Server.RunCommand

---@class easy-dotnet.Server.RunCommand
---@field executable string The executable to run (e.g., "dotnet")
---@field arguments string[] List of command-line arguments
---@field workingDirectory string Working directory for the command
---@field environmentVariables table<string, string> Environment variables to set

---@param params easy-dotnet.Job.TrackedJob
return function(params, response, throw, validate)
  local Tab = require("easy-dotnet.terminal.tab")
  local manager = require("easy-dotnet.terminal.manager")
  local tabline = require("easy-dotnet.terminal.tabline")

  local job_id_ok, job_id_err = validate({ jobId = "string" }, params)
  if not job_id_ok then
    throw({ code = -32602, message = job_id_err })
    return
  end

  local command = params.command
  if not command then
    throw({ code = -32602, message = "Missing nested 'command' object" })
    return
  end

  local slot_id = params.slotId or "default"
  local exec_basename = command.executable:match("([^/\\]+)$") or command.executable
  local label = slot_id == "default" and exec_basename or slot_id:match("^run:(.+)$") or slot_id
  local tab = manager.get_or_create(slot_id, label, "server")

  local prev_jid = Tab.job_id(tab)
  if prev_jid then pcall(vim.fn.jobstop, prev_jid) end

  local old_buf = tab.buf
  tab.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[tab.buf].bufhidden = "hide"
  vim.bo[tab.buf].buflisted = false

  tab.exec_name = exec_basename
  tab.full_args = table.concat(command.arguments or {}, " ")
  tab.last_status = "running"
  tab.last_exit_code = nil
  tab.owned_by = "server"

  manager.set_active(slot_id)
  local term = require("easy-dotnet.terminal")
  term.show()

  local cmd = vim.list_extend({ command.executable }, command.arguments or {})

  local job_id
  vim.api.nvim_buf_call(tab.buf, function()
    job_id = vim.fn.termopen(cmd, {
      cwd = command.workingDirectory,
      env = command.environmentVariables,
      on_exit = function(_, exit_code, _)
        local managed_terminal_opts = require("easy-dotnet.options").get_option("managed_terminal")

        vim.schedule(function()
          tab.last_status = "finished"
          tab.last_exit_code = exit_code

          tabline.render()

          if tab.owned_by == "server" and exit_code == 0 and managed_terminal_opts.auto_hide and manager.active_id == slot_id then
            local delay = managed_terminal_opts.auto_hide_delay or 0
            if delay > 0 then
              local hide_timer = vim.loop.new_timer()
              hide_timer:start(
                delay,
                0,
                vim.schedule_wrap(function()
                  hide_timer:stop()
                  if not hide_timer:is_closing() then hide_timer:close() end
                  term.hide()
                end)
              )
            else
              term.hide()
            end
          end
        end)

        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        if client._initialized then client._client.notify("processExited", { jobId = params.jobId, exitCode = exit_code }) end
      end,
    })
  end)

  if job_id <= 0 then
    throw({ code = -32000, message = "Failed to start terminal job" })
    return
  end

  if old_buf and vim.api.nvim_buf_is_valid(old_buf) then pcall(vim.api.nvim_buf_delete, old_buf, { force = true }) end

  vim.b[tab.buf].terminal_job_id = job_id
  vim.cmd("startinsert")

  tabline.ensure_timer()

  local pid_ok, pid = pcall(vim.fn.jobpid, job_id)
  response({ processId = pid_ok and pid or -1 })
end
