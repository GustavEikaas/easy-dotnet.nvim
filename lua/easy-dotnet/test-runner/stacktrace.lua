local M = {}
local runner_window = require("easy-dotnet.test-runner.render")
local window = require("easy-dotnet.test-runner.window")
local ns_id = vim.api.nvim_create_namespace("EasyDotnetEnhancedStackTrace")

--- @param line easy-dotnet.TestRunner.Node The test node containing pretty_stack_trace
function M.open_enhanced_stack_trace(line)
  if not line.pretty_stack_trace then return end

  if not line.file_path then
    vim.notify("Test adapter does not provide file path", vim.log.levels.WARN)
    return
  end
  local contents = vim.fn.readfile(line.file_path)

  local lines = {}
  local highlights = {}
  local frame_map = {}

  if line.error_message then
    for _, err in ipairs(line.error_message) do
      table.insert(lines, err)
      table.insert(highlights, { #lines - 1, "DiagnosticError" })
    end
    table.insert(lines, "")
  end

  for _, frame in ipairs(line.pretty_stack_trace) do
    table.insert(lines, frame.originalText)
    local current_row = #lines - 1

    if frame.isUserCode then
      table.insert(highlights, { current_row, "String" })
      frame_map[current_row] = frame
    else
      table.insert(highlights, { current_row, "Comment" })
    end
  end

  if line.std_out and #line.std_out > 0 then
    table.insert(lines, "")
    table.insert(lines, "--- Standard Output ---")
    table.insert(highlights, { #lines - 1, "DiagnosticWarn" })
    for _, out in ipairs(line.std_out) do
      table.insert(lines, out)
    end
  end

  local refocus_runner = function()
    local win_id = runner_window.win
    if not win_id then return end
    vim.api.nvim_set_current_win(win_id)
  end

  local file_float = window:new_float():pos_left():write_buf(contents):buf_set_filetype("csharp"):on_win_close(refocus_runner):create()
  vim.wo[file_float.win].number = true

  local stack_trace_float = window:new_float():link_close(file_float):pos_right():write_buf(lines):on_win_close(refocus_runner):create()

  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(stack_trace_float.buf, ns_id, hl[2], hl[1], 0, -1)
  end

  local function get_valid_line(line_num, buf)
    if not line_num then return nil end
    local max_line = vim.api.nvim_buf_line_count(buf)
    return math.max(1, math.min(line_num, max_line))
  end

  local failing_frame = line.failing_frame

  if failing_frame and failing_frame.line then
    local valid_line = get_valid_line(failing_frame.line, file_float.buf)
    if valid_line then
      vim.api.nvim_win_set_cursor(file_float.win, { valid_line, 0 })
      vim.api.nvim_win_call(file_float.win, function() vim.cmd("normal! zz") end)
      local frame_file = string.lower(vim.fs.normalize(failing_frame.file or ""))
      local source_file = string.lower(vim.fs.normalize(line.file_path or ""))

      if frame_file == source_file then vim.api.nvim_buf_add_highlight(file_float.buf, ns_id, "EasyDotnetTestRunnerFailed", valid_line - 1, 0, -1) end
    end
  elseif line.line_number then
    local valid_line = get_valid_line(line.line_number, file_float.buf)
    if valid_line then
      vim.api.nvim_win_set_cursor(file_float.win, { valid_line, 0 })
      vim.api.nvim_win_call(file_float.win, function() vim.cmd("normal! zz") end)
    end
  end

  local function jump_to_frame()
    local cursor = vim.api.nvim_win_get_cursor(stack_trace_float.win)
    local row = cursor[1] - 1

    local frame = frame_map[row]
    if not frame or not frame.file or not frame.line then
      vim.notify("Not a user-code frame or missing file data", vim.log.levels.WARN)
      return
    end

    runner_window.hide()
    vim.api.nvim_win_close(stack_trace_float.win, true)

    vim.cmd(string.format("edit %s", frame.file))

    pcall(vim.api.nvim_win_set_cursor, 0, { frame.line, 0 })
    vim.api.nvim_buf_add_highlight(0, ns_id, "EasyDotnetTestRunnerFailed", frame.line - 1, 0, -1)
  end

  local function go_to_file()
    runner_window.hide()
    vim.api.nvim_win_close(file_float.win, true)
    vim.cmd(string.format("edit %s", line.file_path))

    local target_line = failing_frame and failing_frame.line or line.line_number
    if target_line then
      pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
      vim.cmd("normal! zz")
      vim.api.nvim_buf_add_highlight(0, ns_id, "EasyDotnetTestRunnerFailed", target_line - 1, 0, -1)
    end
  end

  vim.keymap.set("n", "<CR>", jump_to_frame, { silent = true, noremap = true, buffer = stack_trace_float.buf, desc = "Jump to frame" })
  vim.keymap.set("n", "gf", jump_to_frame, { silent = true, noremap = true, buffer = stack_trace_float.buf, desc = "Jump to frame" })

  vim.keymap.set("n", "<leader>gf", go_to_file, { silent = true, noremap = true, buffer = file_float.buf })
  vim.keymap.set("n", "<leader>gf", go_to_file, { silent = true, noremap = true, buffer = stack_trace_float.buf })
end

return M
