local ns_id = require("easy-dotnet.constants").ns_id
local state = require("easy-dotnet.test-runner.state")

local M = {
  buf = nil,
  win = nil,
  header_buf = nil,
  header_win = nil,
  footer_buf = nil,
  footer_win = nil,
  options = {},
}

local ns_header = vim.api.nvim_create_namespace("easy_dotnet_testrunner_header")
local ns_spinner = vim.api.nvim_create_namespace("easy_dotnet_testrunner_spinner")
local ns_footer = vim.api.nvim_create_namespace("easy_dotnet_testrunner_footer")

local spinner = {
  frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
  timer = nil,
  frame = 1,
  interval = 80,
}

local action_display = {
  Run = "Run",
  Debug = "Debug",
  Invalidate = "Invalidate",
  GoToSource = "Go To File",
  PeekResults = "Peek Stacktrace",
  GetBuildErrors = "Build Errors",
  Cancel = "Cancel",
}

local function build_right_counts(rs)
  local ic = M.options.icons
  local parts = {}
  local hls = {}
  local byte_col = 0

  local function push(text, hl)
    if hl then table.insert(hls, { byte_col, byte_col + #text, hl }) end
    table.insert(parts, text)
    byte_col = byte_col + #text
  end

  push(string.format("%s %d  ", ic.success, rs.totalPassed), "EasyDotnetTestRunnerPassed")
  push(string.format("%s %d  ", ic.failed, rs.totalFailed), "EasyDotnetTestRunnerFailed")
  push(string.format("%s %d  ", ic.skipped, rs.totalSkipped), "EasyDotnetTestRunnerSkipped")
  push(string.format("%d tests", rs.totalTests or 0), "Comment")

  local text = table.concat(parts)
  return text, hls, vim.fn.strdisplaywidth(text)
end

local function build_header_row(rs, frame)
  local win = M.header_win
  if not win or not vim.api.nvim_win_is_valid(win) then return "", {} end
  local win_width = vim.api.nvim_win_get_width(win)
  local loading = rs and rs.isLoading

  local left_text, left_hl, left_hl_end
  if loading then
    local op = rs.currentOperation or "Running"
    left_text = string.format(" %s %s", frame or spinner.frames[spinner.frame], op)
    left_hl = "EasyDotnetTestRunnerRunning"
    left_hl_end = #left_text
  else
    local status = (rs and rs.overallStatus and rs.overallStatus ~= "Idle") and rs.overallStatus or ""
    left_text = " " .. status
    if status ~= "" then
      left_hl = rs.overallStatus == "Failed" and "EasyDotnetTestRunnerFailed" or "EasyDotnetTestRunnerPassed"
      left_hl_end = #left_text
    end
  end

  local empty_rs = { totalPassed = 0, totalFailed = 0, totalSkipped = 0, totalTests = 0 }
  local right_text, right_hls, right_dw = build_right_counts(rs or empty_rs)
  local left_dw = vim.fn.strdisplaywidth(left_text)

  local line, hls = left_text, {}
  if left_hl then table.insert(hls, { 0, left_hl_end, left_hl }) end

  if left_dw + right_dw + 1 <= win_width then
    local pad = win_width - left_dw - right_dw
    local right_offset = #left_text + pad
    line = left_text .. string.rep(" ", pad) .. right_text
    for _, h in ipairs(right_hls) do
      table.insert(hls, { h[1] + right_offset, h[2] + right_offset, h[3] })
    end
  end

  return line, hls
end

local function render_header(frame)
  if not M.header_buf or not vim.api.nvim_buf_is_valid(M.header_buf) then return end
  if not M.header_win or not vim.api.nvim_win_is_valid(M.header_win) then return end

  local rs = state.runner_status
  local line, hls = build_header_row(rs, frame)

  vim.api.nvim_buf_clear_namespace(M.header_buf, ns_header, 0, -1)
  vim.api.nvim_buf_clear_namespace(M.header_buf, ns_spinner, 0, -1)
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.header_buf })
  vim.api.nvim_buf_set_lines(M.header_buf, 0, -1, false, { line })
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.header_buf })

  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(M.header_buf, ns_header, hl[3], 0, hl[1], hl[2])
  end
end

local function build_footer_line(node, loading)
  if loading then return " Cancel", { { 1, 7, "Comment" } } end
  if not node or not node.availableActions or #node.availableActions == 0 then return "", {} end

  local text = " "
  local hls = {}

  for i, action in ipairs(node.availableActions) do
    local label = action_display[action]
    if label then
      if i > 1 then
        local sep = " · "
        table.insert(hls, { #text, #text + #sep, "Comment" })
        text = text .. sep
      end
      table.insert(hls, { #text, #text + #label, "Normal" })
      text = text .. label
    end
  end

  if text == " " then return "", {} end
  return text, hls
end

local function render_footer(node)
  if M.options.hide_legend then return end
  if not M.footer_buf or not vim.api.nvim_buf_is_valid(M.footer_buf) then return end
  if not M.footer_win or not vim.api.nvim_win_is_valid(M.footer_win) then return end

  local loading = state.runner_status and state.runner_status.isLoading
  local text, hls = build_footer_line(node, loading)

  vim.api.nvim_buf_clear_namespace(M.footer_buf, ns_footer, 0, -1)
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.footer_buf })
  vim.api.nvim_buf_set_lines(M.footer_buf, 0, -1, false, { text })
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.footer_buf })

  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(M.footer_buf, ns_footer, h[3], 0, h[1], h[2])
  end
end

local function spinner_stop()
  if not spinner.timer then return end
  spinner.timer:stop()
  spinner.timer:close()
  spinner.timer = nil
  if M.header_buf and vim.api.nvim_buf_is_valid(M.header_buf) then vim.api.nvim_buf_clear_namespace(M.header_buf, ns_spinner, 0, -1) end
end

local function spinner_tick()
  if not M.header_buf or not vim.api.nvim_buf_is_valid(M.header_buf) then
    spinner_stop()
    return
  end
  spinner.frame = (spinner.frame % #spinner.frames) + 1
  render_header(spinner.frames[spinner.frame])
end

local function spinner_start()
  if spinner.timer then return end
  spinner.frame = 1
  spinner.timer = vim.uv.new_timer()
  spinner.timer:start(0, spinner.interval, vim.schedule_wrap(spinner_tick))
end

local function make_scratch_buf(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "easy-dotnet", { buf = buf })
  if name then vim.api.nvim_buf_set_name(buf, name) end
  return buf
end

local function ensure_header_buf()
  if not M.header_buf or not vim.api.nvim_buf_is_valid(M.header_buf) then M.header_buf = make_scratch_buf() end
end

local function ensure_footer_buf()
  if not M.footer_buf or not vim.api.nvim_buf_is_valid(M.footer_buf) then M.footer_buf = make_scratch_buf() end
end

local function get_float_dims()
  local width = math.floor(vim.o.columns * 0.8)
  local main_height = math.floor(vim.o.lines * 0.7)
  local has_footer = not M.options.hide_legend
  local total_visual_height = main_height + (has_footer and 6 or 4)
  local start_visual_row = math.floor((vim.o.lines - total_visual_height) / 2) - 2
  start_visual_row = math.max(1, start_visual_row)

  local main_row = start_visual_row + 3
  local col = math.floor((vim.o.columns - width) / 2)

  return {
    width = width,
    height = main_height,
    col = col,
    row = main_row,
    header_row = main_row - 2,
    footer_row = main_row + main_height + 1,
  }
end

local function resize_floats()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end
  local dims = get_float_dims()

  vim.api.nvim_win_set_config(M.win, { width = dims.width, height = dims.height, col = dims.col, row = dims.row, relative = "editor" })

  if M.header_win and vim.api.nvim_win_is_valid(M.header_win) then
    vim.api.nvim_win_set_config(M.header_win, { width = dims.width, height = 1, col = dims.col, row = dims.header_row, relative = "editor" })
  end

  if M.footer_win and vim.api.nvim_win_is_valid(M.footer_win) then
    vim.api.nvim_win_set_config(M.footer_win, { width = dims.width, height = 1, col = dims.col, row = dims.footer_row, relative = "editor" })
  end

  M.refresh()
end

local function open_header_float(dims)
  ensure_header_buf()
  M.header_win = vim.api.nvim_open_win(M.header_buf, false, {
    relative = "editor",
    width = dims.width,
    height = 1,
    col = dims.col,
    row = dims.header_row,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 51,
  })
  vim.wo[M.header_win].cursorline = false
  vim.wo[M.header_win].winhighlight = "Normal:NormalFloat"
end

local function open_footer_float(dims)
  ensure_footer_buf()
  M.footer_win = vim.api.nvim_open_win(M.footer_buf, false, {
    relative = "editor",
    width = dims.width,
    height = 1,
    col = dims.col,
    row = dims.footer_row,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 51,
  })
  vim.wo[M.footer_win].cursorline = false
  vim.wo[M.footer_win].winhighlight = "Normal:NormalFloat"
end

local function open_header_split()
  ensure_header_buf()
  vim.cmd("aboveleft 1split")
  M.header_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.header_win, M.header_buf)
  vim.wo[M.header_win].cursorline = false
  vim.wo[M.header_win].statusline = ""
  vim.wo[M.header_win].winfixheight = true
  vim.wo[M.header_win].number = false
  vim.wo[M.header_win].relativenumber = false
  vim.wo[M.header_win].signcolumn = "no"
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.header_buf })
  vim.api.nvim_set_current_win(M.win)
end

local function open_footer_split()
  ensure_footer_buf()
  vim.cmd("belowright 1split")
  M.footer_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.footer_win, M.footer_buf)
  vim.wo[M.footer_win].cursorline = false
  vim.wo[M.footer_win].statusline = ""
  vim.wo[M.footer_win].winfixheight = true
  vim.wo[M.footer_win].number = false
  vim.wo[M.footer_win].relativenumber = false
  vim.wo[M.footer_win].signcolumn = "no"
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.footer_buf })
  vim.api.nvim_set_current_win(M.win)
end

local function close_aux_wins()
  for _, w in ipairs({ M.header_win, M.footer_win }) do
    if w and vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_close(w, true) end
  end
  M.header_win = nil
  M.footer_win = nil
end

---@param mode "float"|"split"|"vsplit"
function M.open(mode, options)
  M.options = options or M.options
  M.viewmode = mode

  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = make_scratch_buf("Test Runner")
    vim.api.nvim_buf_set_name(M.buf, "Test Runner")
  end

  if mode == "float" then
    local dims = get_float_dims()

    open_header_float(dims)
    if not M.options.hide_legend then open_footer_float(dims) end

    M.win = vim.api.nvim_open_win(M.buf, true, {
      relative = "editor",
      width = dims.width,
      height = dims.height,
      col = dims.col,
      row = dims.row,
      style = "minimal",
      border = "rounded",
      focusable = true,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(M.win),
      once = true,
      callback = function()
        spinner_stop()
        close_aux_wins()
        M.win = nil
        pcall(vim.api.nvim_del_augroup_by_name, "EasyDotnetTestRunnerResize")
      end,
    })
  elseif mode == "split" or mode == "vsplit" then
    if mode == "vsplit" then
      local w = options and options.vsplit_width or math.floor(vim.o.columns * 0.4)
      vim.cmd((options and options.vsplit_pos or "") .. tostring(w) .. "vsplit")
    else
      vim.cmd("split")
    end
    M.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.win, M.buf)

    open_header_split()
    if not M.options.hide_legend then open_footer_split() end

    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(M.win),
      once = true,
      callback = function()
        spinner_stop()
        close_aux_wins()
        M.win = nil
        pcall(vim.api.nvim_del_augroup_by_name, "EasyDotnetTestRunnerResize")
      end,
    })
  end

  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_set_option_value("cursorline", true, { win = M.win })
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = M.buf,
      callback = function() render_footer(M.node_at_cursor()) end,
    })
    vim.api.nvim_create_autocmd("VimResized", {
      group = vim.api.nvim_create_augroup("EasyDotnetTestRunnerResize", { clear = true }),
      callback = function()
        if M.viewmode == "float" then
          resize_floats()
        else
          M.refresh()
        end
      end,
    })
  end

  M.refresh()
end

function M.hide()
  spinner_stop()
  close_aux_wins()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, false)
    M.win = nil
  end
end

local status_highlights = {
  Passed = "EasyDotnetTestRunnerPassed",
  Failed = "EasyDotnetTestRunnerFailed",
  Skipped = "EasyDotnetTestRunnerSkipped",
  Running = "EasyDotnetTestRunnerRunning",
  Debugging = "EasyDotnetTestRunnerRunning",
  Building = "EasyDotnetTestRunnerRunning",
  BuildFailed = "EasyDotnetTestRunnerFailed",
  NotRun = "EasyDotnetTestRunnerFailed",
  Discovering = "EasyDotnetTestRunnerRunning",
  Queued = "EasyDotnetTestRunnerRunning",
  Cancelling = "EasyDotnetTestRunnerRunning",
  Cancelled = "EasyDotnetTestRunnerFailed",
}

local function node_pre_icon(node_type)
  local icons = M.options.icons
  return ({
    Solution = icons.sln,
    Project = icons.project,
    Namespace = icons.dir,
    TestClass = icons.class,
    TheoryGroup = icons.package,
    TestMethod = icons.test,
    Subcase = icons.test,
  })[node_type] or "?"
end

local function get_status_icon(stype)
  local icons = M.options.icons
  return ({
    Failed = " " .. icons.failed,
    Skipped = " " .. icons.skipped,
    Cancelled = " " .. icons.failed,
    NotRun = " " .. icons.build_failed,
    Running = " " .. icons.reload,
    Debugging = " " .. icons.reload,
    Building = " " .. icons.reload,
    Discovering = icons.reload,
    BuildFailed = " " .. icons.build_failed,
    Queued = " …",
    Cancelling = " " .. icons.reload,
  })[stype] or ""
end

local function render_node(node, depth)
  local indent = string.rep(" ", depth * 2)
  local ntype = node.type and node.type.type or ""
  local pre = node_pre_icon(ntype)

  local status_suffix = ""
  local hl = nil
  if node.status then
    local stype = node.status.type
    status_suffix = get_status_icon(stype)
    hl = status_highlights[stype]
    if stype == "Passed" and node.status.durationDisplay then status_suffix = "  " .. node.status.durationDisplay end
  end

  if not hl then
    hl = ({
      Solution = "EasyDotnetTestRunnerSolution",
      Project = "EasyDotnetTestRunnerProject",
      Namespace = "EasyDotnetTestRunnerDir",
      TestClass = "EasyDotnetTestRunnerDir",
      TheoryGroup = "EasyDotnetTestRunnerTest",
      TestMethod = "EasyDotnetTestRunnerTest",
      Subcase = "EasyDotnetTestRunnerSubcase",
    })[ntype]
  end

  return string.format("%s%s %s%s", indent, pre, node.displayName, status_suffix), hl
end

function M.refresh()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  local rs = state.runner_status
  if rs and rs.isLoading then
    spinner_start()
  else
    spinner_stop()
  end

  render_header()
  render_footer(M.node_at_cursor())

  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end

  vim.api.nvim_buf_clear_namespace(M.buf, ns_id, 0, -1)
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.buf })

  local lines = {}
  local highlights = {}
  state.traverse_visible(function(node, depth)
    local line, hl = render_node(node, depth)
    table.insert(lines, line)
    if hl then table.insert(highlights, { row = #lines - 1, hl = hl }) end
  end)

  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.buf })

  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(M.buf, ns_id, h.hl, h.row, 0, -1)
  end
end

function M.node_at_cursor()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return nil end
  local row = vim.api.nvim_win_get_cursor(M.win)[1]
  local current = 0
  local found = nil
  state.traverse_visible(function(node)
    current = current + 1
    if current == row and not found then found = node end
  end)
  return found
end

return M
