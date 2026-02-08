local spinner_frames = require("easy-dotnet.ui-modules.jobs").spinner_frames

local function find_reusable_terminal_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.w[win].easy_dotnet_terminal then return win, buf end
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
    vim.cmd("normal! G")
  else
    vim.cmd("split")
    win = vim.api.nvim_get_current_win()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)

    vim.w[win].easy_dotnet_terminal = true

    vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(buf, "buflisted", false)
  end

  local header_buf = vim.api.nvim_create_buf(false, true)
  local header_win = vim.api.nvim_open_win(header_buf, false, {
    relative = "win",
    win = win,
    row = 0,
    col = 0,
    width = vim.api.nvim_win_get_width(win),
    height = 1,
    style = "minimal",
    focusable = false,
    zindex = 100,
  })

  vim.api.nvim_win_set_option(header_win, "winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder")

  local exec_name = command.executable:match("([^/\\]+)$") or command.executable
  local full_args = table.concat(command.arguments or {}, " ")
  local spinner_idx = 1
  local timer = vim.loop.new_timer()
  local ns_id = vim.api.nvim_create_namespace("EasyDotnetHeader")

  local function update_header(status, exit_code)
    if not vim.api.nvim_win_is_valid(win) then
      if vim.api.nvim_win_is_valid(header_win) then vim.api.nvim_win_close(header_win, true) end
      if timer then
        timer:stop()
        if not timer:is_closing() then timer:close() end
      end
      return
    end

    local curr_width = vim.api.nvim_win_get_width(win)
    if vim.api.nvim_win_get_width(header_win) ~= curr_width then vim.api.nvim_win_set_config(header_win, { width = curr_width, relative = "win", win = win, row = 0, col = 0 }) end

    local icon = ""
    local icon_hl = "DiagnosticInfo"

    if status == "running" then
      icon = spinner_frames[spinner_idx]
      spinner_idx = (spinner_idx % #spinner_frames) + 1
    elseif status == "finished" then
      if exit_code == 0 then
        icon = "✓"
        icon_hl = "String"
      else
        icon = ""
        icon_hl = "ErrorMsg"
      end
    end

    local max_len = math.floor(curr_width * 0.7)
    local display_args = full_args
    if #display_args > max_len then display_args = display_args:sub(1, max_len) .. "..." end

    local padding_left = 1
    local content_string = string.format("%s %s %s", icon, exec_name, display_args)
    local final_line = string.rep(" ", padding_left) .. content_string
    vim.api.nvim_buf_set_lines(header_buf, 0, -1, false, { final_line })
    vim.api.nvim_buf_clear_namespace(header_buf, ns_id, 0, -1)

    local start_icon = padding_left
    local end_icon = start_icon + #icon
    local start_exec = end_icon + 1
    local end_exec = start_exec + #exec_name
    local start_args = end_exec + 1
    local end_args = start_args + #display_args

    vim.api.nvim_buf_add_highlight(header_buf, ns_id, icon_hl, 0, start_icon, end_icon)
    vim.api.nvim_buf_add_highlight(header_buf, ns_id, "Title", 0, start_exec, end_exec)
    vim.api.nvim_buf_add_highlight(header_buf, ns_id, "Comment", 0, start_args, end_args)
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(header_win) then vim.api.nvim_win_close(header_win, true) end
      if timer then
        timer:stop()
        if not timer:is_closing() then timer:close() end
      end
    end,
    once = true,
  })

  local cmd = vim.list_extend({ command.executable }, command.arguments or {})

  local job_id = vim.fn.jobstart(cmd, {
    cwd = command.workingDirectory,
    env = command.environmentVariables,
    term = true,
    on_exit = function(_, exit_code, _)
      if timer then
        timer:stop()
        if not timer:is_closing() then timer:close() end
      end
      vim.schedule(function() update_header("finished", exit_code) end)

      local client = require("easy-dotnet.rpc.rpc").global_rpc_client
      if client._initialized then client._client.notify("processExited", { jobId = params.jobId, exitCode = exit_code }) end
    end,
  })

  if job_id <= 0 then
    throw({ code = -32000, message = "Failed to start terminal job" })
    return
  end

  vim.b[buf].terminal_job_id = job_id
  vim.cmd("startinsert")

  timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      local codes = vim.fn.jobwait({ job_id }, 0)
      local status_code = codes[1]

      if status_code == -1 then
        update_header("running")
      else
        timer:stop()
        if not timer:is_closing() then timer:close() end
        update_header("finished", status_code)
      end
    end)
  )

  local pid_ok, pid = pcall(vim.fn.jobpid, job_id)
  response({ processId = pid_ok and pid or -1 })
end
