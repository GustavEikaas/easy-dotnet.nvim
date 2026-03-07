--- Results float with two layout modes:
---   "runner"  — file pane left + detail pane right (original testrunner context)
---   "buffer"  — single centred pane, failing frame first, no redundant file view

local ns_id = require("easy-dotnet.constants").ns_id
local window = require("easy-dotnet.test-runner.window")

local M = {}

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

local function jump_to(file, line, close_wins)
  for _, w in ipairs(close_wins or {}) do
    if w and vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_close(w, true) end
  end
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  if line then
    pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
    vim.cmd("normal! zz")
    vim.api.nvim_buf_add_highlight(0, ns_id, "EasyDotnetTestRunnerFailed", line - 1, 0, -1)
  end
end

local function build_frame_map(lines, highlights, frames)
  local frame_map = {}
  for _, frame in ipairs(frames or {}) do
    table.insert(lines, "  " .. frame.originalText)
    local row = #lines - 1
    if frame.isUserCode then
      table.insert(highlights, { row, "String" })
      frame_map[row] = frame
    else
      table.insert(highlights, { row, "Comment" })
    end
  end
  return frame_map
end

local function section(lines, highlights, label, hl)
  table.insert(lines, "")
  table.insert(lines, label)
  table.insert(highlights, { #lines - 1, hl or "Comment" })
end

local function attach_frame_jump(buf, win, frame_map, close_wins)
  local function jump()
    local row = vim.api.nvim_win_get_cursor(win)[1] - 1
    local frame = frame_map[row]
    if not frame or not frame.file or not frame.line then
      vim.notify("Not a user-code frame", vim.log.levels.WARN)
      return
    end
    jump_to(frame.file, frame.line, close_wins)
  end
  vim.keymap.set("n", "<CR>", jump, { buffer = buf, silent = true, noremap = true, desc = "Jump to frame" })
  vim.keymap.set("n", "gf", jump, { buffer = buf, silent = true, noremap = true, desc = "Jump to frame" })
end

-- ---------------------------------------------------------------------------
-- Buffer-context layout  (option 3)
-- Failing frame → error → dimmed trace → stdout
-- No file pane — user is already in the file.
-- ---------------------------------------------------------------------------

local function open_from_buffer(node, result, refocus)
  local lines, highlights = {}, {}
  local frame_map = {}

  -- 1. Failing frame — prominent, at the very top
  local ff = result.failingFrame
  if ff and ff.file and ff.line then
    local short = vim.fn.fnamemodify(ff.file, ":~:.")
    table.insert(lines, "  " .. short .. ":" .. ff.line)
    table.insert(highlights, { 0, "EasyDotnetTestRunnerFailed" })
    if ff.isUserCode then frame_map[0] = ff end
    table.insert(lines, "")
  end

  -- 2. Error message
  if result.errorMessage and #result.errorMessage > 0 then
    for _, line in ipairs(result.errorMessage) do
      table.insert(lines, "  " .. line)
      table.insert(highlights, { #lines - 1, "DiagnosticError" })
    end
  end

  -- 3. Stack trace (user frames bright, framework frames dimmed)
  if result.frames and #result.frames > 0 then
    section(lines, highlights, " Stack Trace", "Comment")
    local fmap = build_frame_map(lines, highlights, result.frames)
    for row, frame in pairs(fmap) do
      frame_map[row] = frame
    end
  end

  -- 4. Stdout
  if result.stdout and #result.stdout > 0 then
    section(lines, highlights, " Stdout", "DiagnosticWarn")
    for _, line in ipairs(result.stdout) do
      table.insert(lines, "  " .. line)
    end
  end

  local ui = vim.api.nvim_list_uis()[1] or { width = 200, height = 50 }
  local width = math.floor(ui.width * 0.80)
  local height = math.floor(ui.height * 0.65)
  local col = math.floor((ui.width - width) / 2)
  local row = math.floor((ui.height - height) / 2)

  local float = window:new_float():pos_center():write_buf(lines):on_win_close(refocus):create()

  -- Override the default pos_center sizing to something wider and taller
  if float.win and vim.api.nvim_win_is_valid(float.win) then
    vim.api.nvim_win_set_config(float.win, {
      relative = "editor",
      width = width,
      height = height,
      col = col,
      row = row,
    })
  end

  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(float.buf, ns_id, hl[2], hl[1], 0, -1)
  end

  attach_frame_jump(float.buf, float.win, frame_map, { float.win })

  -- <leader>gf: go to failing frame / test source
  vim.keymap.set("n", "<leader>gf", function()
    local target_file = (ff and ff.file) or node.filePath
    local target_line = (ff and ff.line) or (node.signatureLine and node.signatureLine + 1)
    if not target_file then return end
    jump_to(target_file, target_line, { float.win })
  end, { buffer = float.buf, silent = true, noremap = true, desc = "Go to failing frame" })
end

-- ---------------------------------------------------------------------------
-- Runner-context layout  (original)
-- File pane left scrolled to failing frame, detail pane right.
-- ---------------------------------------------------------------------------

local function open_from_runner(node, result, refocus)
  local file_float = nil
  if node.filePath and vim.fn.filereadable(node.filePath) == 1 then
    local contents = vim.fn.readfile(node.filePath)
    file_float = window:new_float():pos_left():write_buf(contents):buf_set_filetype("csharp"):on_win_close(refocus):create()
    vim.wo[file_float.win].number = true
  end

  local lines, highlights = {}, {}
  local frame_map = {}

  if result.errorMessage and #result.errorMessage > 0 then
    for _, line in ipairs(result.errorMessage) do
      table.insert(lines, line)
      table.insert(highlights, { #lines - 1, "DiagnosticError" })
    end
    table.insert(lines, "")
  end

  if result.frames and #result.frames > 0 then
    local fmap = build_frame_map(lines, highlights, result.frames)
    for row, frame in pairs(fmap) do
      frame_map[row] = frame
    end
  end

  if result.stdout and #result.stdout > 0 then
    section(lines, highlights, "--- stdout ---", "DiagnosticWarn")
    for _, line in ipairs(result.stdout) do
      table.insert(lines, line)
    end
  end

  local detail_float
  if file_float then
    detail_float = window:new_float():link_close(file_float):pos_right():write_buf(lines):on_win_close(refocus):create()
  else
    detail_float = window:new_float():pos_center():write_buf(lines):on_win_close(refocus):create()
  end

  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(detail_float.buf, ns_id, hl[2], hl[1], 0, -1)
  end

  local close_wins = { detail_float.win, file_float and file_float.win or nil }
  attach_frame_jump(detail_float.buf, detail_float.win, frame_map, close_wins)

  local function go_to_source()
    if not node.filePath then return end
    local target = (result.failingFrame and result.failingFrame.line) or (node.signatureLine and node.signatureLine + 1)
    jump_to(node.filePath, target, close_wins)
  end

  vim.keymap.set("n", "<leader>gf", go_to_source, { buffer = detail_float.buf, silent = true, noremap = true, desc = "Go to source" })
  if file_float then vim.keymap.set("n", "<leader>gf", go_to_source, { buffer = file_float.buf, silent = true, noremap = true, desc = "Go to source" }) end

  -- Scroll file pane to failing frame
  if file_float then
    local line = (result.failingFrame and result.failingFrame.line) or (node.signatureLine and node.signatureLine + 1)
    if line then
      local max = vim.api.nvim_buf_line_count(file_float.buf)
      line = math.max(1, math.min(line, max))
      vim.api.nvim_win_set_cursor(file_float.win, { line, 0 })
      vim.api.nvim_win_call(file_float.win, function() vim.cmd("normal! zz") end)
      vim.api.nvim_buf_add_highlight(file_float.buf, ns_id, "EasyDotnetTestRunnerFailed", line - 1, 0, -1)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---@param node   easy-dotnet.TestRunner.Node
---@param result easy-dotnet.TestRunner.Results   from testrunner/getResults
---@param opts?  { source: "buffer"|"runner" }    defaults to "runner"
function M.open(node, result, opts)
  local source = opts and opts.source or "runner"
  local render = require("easy-dotnet.test-runner.render")
  local refocus = function()
    local win = render.win
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
  end

  if source == "buffer" then
    open_from_buffer(node, result, refocus)
  else
    open_from_runner(node, result, refocus)
  end
end

return M
