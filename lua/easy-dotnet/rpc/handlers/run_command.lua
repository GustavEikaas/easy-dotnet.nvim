local function find_reusable_terminal_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local is_easy_dotnet_terminal = vim.w[win].easy_dotnet_terminal
    if is_easy_dotnet_terminal then return win, buf end
  end
  return nil, nil
end

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
  local win, buf = find_reusable_terminal_window()

  if win and buf then
    local old_job = vim.b[buf].terminal_job_id
    if old_job then pcall(vim.fn.jobstop, old_job) end
    vim.api.nvim_buf_set_option(buf, "modified", false)
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("split")
    win = vim.api.nvim_get_current_win()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)

    vim.w[win].easy_dotnet_terminal = true

    vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(buf, "buflisted", false)
  end

  local cmd = vim.list_extend({ command.executable }, command.arguments or {})

  local job_id = vim.fn.jobstart(cmd, {
    cwd = command.workingDirectory,
    env = command.environmentVariables,
    term = true,
    on_exit = function(_, exit_code, _)
      local client = require("easy-dotnet.rpc.rpc").global_rpc_client
      if client._initialized then client._client.notify("processExited", { jobId = params.jobId, exitCode = exit_code }) end
    end,
  })

  if job_id <= 0 then
    throw({ code = -32000, message = "Failed to start terminal job" })
    return
  end

  vim.b[buf].terminal_job_id = job_id

  local pid_ok, pid = pcall(vim.fn.jobpid, job_id)

  response({ processId = pid_ok and pid or -1 })
end
