local ns_id = require("easy-dotnet.constants").ns_id
local window = require("easy-dotnet.test-runner.window")

local M = {}

---@param node easy-dotnet.TestRunner.Node
---@param result easy-dotnet.TestRunner.Results  from testrunner/getResults
function M.open(node, result)
  local render = require("easy-dotnet.test-runner.render")

  local refocus = function()
    local win = render.win
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
  end

  -- Left pane: source file if available
  local file_float = nil
  if node.filePath and vim.fn.filereadable(node.filePath) == 1 then
    local contents = vim.fn.readfile(node.filePath)
    file_float = window:new_float():pos_left():write_buf(contents):buf_set_filetype("csharp"):on_win_close(refocus):create()
    vim.wo[file_float.win].number = true
  end

  -- Right pane: error message + stack frames + stdout
  local detail_lines = {}
  local highlights = {} -- { row, hl_group }

  if result.errorMessage and #result.errorMessage > 0 then
    for _, line in ipairs(result.errorMessage) do
      table.insert(detail_lines, line)
      table.insert(highlights, { #detail_lines - 1, "DiagnosticError" })
    end
    table.insert(detail_lines, "")
  end

  -- frame_map: row (0-based) → frame, for jump-to-frame on <CR>
  local frame_map = {}
  if result.frames and #result.frames > 0 then
    for _, frame in ipairs(result.frames) do
      table.insert(detail_lines, frame.originalText)
      local row = #detail_lines - 1
      if frame.isUserCode then
        table.insert(highlights, { row, "String" })
        frame_map[row] = frame
      else
        table.insert(highlights, { row, "Comment" })
      end
    end
  end

  if result.stdout and #result.stdout > 0 then
    table.insert(detail_lines, "")
    table.insert(detail_lines, "--- stdout ---")
    table.insert(highlights, { #detail_lines - 1, "DiagnosticWarn" })
    for _, line in ipairs(result.stdout) do
      table.insert(detail_lines, line)
    end
  end

  local detail_float
  if file_float then
    detail_float = window:new_float():link_close(file_float):pos_right():write_buf(detail_lines):on_win_close(refocus):create()
  else
    detail_float = window:new_float():pos_center():write_buf(detail_lines):on_win_close(refocus):create()
  end

  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(detail_float.buf, ns_id, hl[2], hl[1], 0, -1)
  end

  -- Scroll source file to failing frame
  if file_float and result.failingFrame and result.failingFrame.line then
    local line = result.failingFrame.line -- 1-based from server
    local max = vim.api.nvim_buf_line_count(file_float.buf)
    line = math.max(1, math.min(line, max))
    vim.api.nvim_win_set_cursor(file_float.win, { line, 0 })
    vim.api.nvim_win_call(file_float.win, function() vim.cmd("normal! zz") end)
    vim.api.nvim_buf_add_highlight(file_float.buf, ns_id, "EasyDotnetTestRunnerFailed", line - 1, 0, -1)
  elseif file_float and node.lineNumber then
    local line = node.lineNumber + 1 -- convert 0-based to 1-based
    local max = vim.api.nvim_buf_line_count(file_float.buf)
    line = math.max(1, math.min(line, max))
    vim.api.nvim_win_set_cursor(file_float.win, { line, 0 })
    vim.api.nvim_win_call(file_float.win, function() vim.cmd("normal! zz") end)
  end

  -- <CR> / gf in detail pane: jump to that stack frame
  local function jump_to_frame()
    local cursor = vim.api.nvim_win_get_cursor(detail_float.win)
    local frame = frame_map[cursor[1] - 1]
    if not frame or not frame.file or not frame.line then
      vim.notify("Not a user-code frame", vim.log.levels.WARN)
      return
    end
    render.hide()
    vim.api.nvim_win_close(detail_float.win, true)
    vim.cmd("edit " .. vim.fn.fnameescape(frame.file))
    pcall(vim.api.nvim_win_set_cursor, 0, { frame.line, 0 })
    vim.cmd("normal! zz")
    vim.api.nvim_buf_add_highlight(0, ns_id, "EasyDotnetTestRunnerFailed", frame.line - 1, 0, -1)
  end

  local function go_to_source()
    if not node.filePath then return end
    render.hide()
    if file_float then vim.api.nvim_win_close(file_float.win, true) end
    vim.cmd("edit " .. vim.fn.fnameescape(node.filePath))
    local target = (result.failingFrame and result.failingFrame.line) or (node.lineNumber and node.lineNumber + 1)
    if target then
      pcall(vim.api.nvim_win_set_cursor, 0, { target, 0 })
      vim.cmd("normal! zz")
      vim.api.nvim_buf_add_highlight(0, ns_id, "EasyDotnetTestRunnerFailed", target - 1, 0, -1)
    end
  end

  vim.keymap.set("n", "<CR>", jump_to_frame, { buffer = detail_float.buf, silent = true, noremap = true, desc = "Jump to frame" })
  vim.keymap.set("n", "gf", jump_to_frame, { buffer = detail_float.buf, silent = true, noremap = true, desc = "Jump to frame" })
  vim.keymap.set("n", "<leader>gf", go_to_source, { buffer = detail_float.buf, silent = true, noremap = true, desc = "Go to source" })
  if file_float then vim.keymap.set("n", "<leader>gf", go_to_source, { buffer = file_float.buf, silent = true, noremap = true, desc = "Go to source" }) end
end

return M
