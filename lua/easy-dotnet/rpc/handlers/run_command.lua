local header = require("easy-dotnet.terminal.header")

local function get_state() return require("easy-dotnet.terminal").state end

---@class easy-dotnet.Job.TrackedJob
---@field jobId string
---@field command easy-dotnet.Server.RunCommand

---@class easy-dotnet.Server.RunCommand
---@field executable string The executable to run (e.g., "dotnet")
---@field arguments string[] List of command-line arguments
---@field workingDirectory string Working directory for the command
---@field environmentVariables table<string, string> Environment variables to set

---@param params easy-dotnet.Job.TrackedJob
return function(params, response, throw, validate)
  local state = get_state()
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

  if state.is_running then
    throw({ code = -32000, message = "A job is already running in the terminal" })
    return
  end

  state.exec_name = command.executable:match("([^/\\]+)$") or command.executable
  state.full_args = table.concat(command.arguments or {}, " ")

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    if state.job_id then pcall(vim.fn.jobstop, state.job_id) end
    vim.api.nvim_buf_set_option(state.buf, "modified", false)
  else
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(state.buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(state.buf, "buflisted", false)
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  else
    vim.cmd("split")
    state.win = vim.api.nvim_get_current_win()
    vim.w[state.win].easy_dotnet_terminal = true
  end

  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.cmd("normal! G")

  header.create_header_win()

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win),
    callback = function()
      state.win = nil
      header.cleanup_header()
    end,
    once = true,
  })

  vim.keymap.set("n", "q", function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, false) end
  end, { buffer = state.buf, nowait = true })

  local cmd = vim.list_extend({ command.executable }, command.arguments or {})

  local job_id = vim.fn.jobstart(cmd, {
    cwd = command.workingDirectory,
    env = command.environmentVariables,
    term = true,
    on_exit = function(_, exit_code, _)
      local managed_terminal_opts = require("easy-dotnet.options").get_option("managed_terminal")
      local terminal = require("easy-dotnet.terminal")
      state.is_running = false
      state.last_status = "finished"
      state.last_exit_code = exit_code

      vim.schedule(function()
        header.cleanup_header()
        if state.win and vim.api.nvim_win_is_valid(state.win) then
          header.create_header_win()
          header.update_header("finished", exit_code)
        end

        if exit_code == 0 and managed_terminal_opts.auto_hide then
          local delay = managed_terminal_opts.auto_hide_delay or 0
          if delay > 0 then
            local hide_timer = vim.loop.new_timer()
            hide_timer:start(
              delay,
              0,
              vim.schedule_wrap(function()
                hide_timer:stop()
                if not hide_timer:is_closing() then hide_timer:close() end
                if not state.is_running then terminal.hide() end
              end)
            )
          else
            terminal.hide()
          end
        end
      end)

      local client = require("easy-dotnet.rpc.rpc").global_rpc_client
      if client._initialized then client._client.notify("processExited", { jobId = params.jobId, exitCode = exit_code }) end
    end,
  })

  if job_id <= 0 then
    throw({ code = -32000, message = "Failed to start terminal job" })
    return
  end

  state.job_id = job_id
  state.is_running = true
  state.last_status = "running"
  state.last_exit_code = nil

  vim.b[state.buf].terminal_job_id = job_id
  vim.cmd("startinsert")

  local timer = vim.loop.new_timer()
  state.timer = timer
  timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      local codes = vim.fn.jobwait({ job_id }, 0)
      if codes[1] == -1 then
        header.update_header("running")
      else
        timer:stop()
        if not timer:is_closing() then timer:close() end
      end
    end)
  )

  local pid_ok, pid = pcall(vim.fn.jobpid, job_id)
  response({ processId = pid_ok and pid or -1 })
end
