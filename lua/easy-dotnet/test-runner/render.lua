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

local last_run_time = nil
local was_loading = false
local refresh_pending = false

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

  if rs.totalRunning > 0 then push(string.format("%s %d  ", ic.reload, rs.totalRunning), "EasyDotnetTestRunnerRunning") end
  push(string.format("%s %d  ", ic.success, rs.totalPassed), "EasyDotnetTestRunnerPassed")
  push(string.format("%s %d  ", ic.failed, rs.totalFailed), "EasyDotnetTestRunnerFailed")
  push(string.format("%s %d  ", ic.skipped, rs.totalSkipped), "EasyDotnetTestRunnerSkipped")
  if (rs.totalInconclusive or 0) > 0 then push(string.format("%s %d  ", ic.inconclusive or ic.skipped, rs.totalInconclusive), "EasyDotnetTestRunnerInconclusive") end
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
  local status = (rs and rs.overallStatus) or "Idle"

  if loading then
    left_text = string.format(" %s %s", frame or spinner.frames[spinner.frame], status)
    left_hl = "EasyDotnetTestRunnerRunning"
    left_hl_end = #left_text
  else
    local shown = status ~= "Idle" and status or ""
    left_text = " " .. shown
    if shown ~= "" then
      if shown == "Killed" then
        left_hl = "EasyDotnetTestRunnerFailed"
      elseif shown == "Cancelled" then
        left_hl = "Comment"
      elseif shown == "Failed" then
        left_hl = "EasyDotnetTestRunnerFailed"
      elseif shown == "Inconclusive" then
        left_hl = "EasyDotnetTestRunnerInconclusive"
      else
        left_hl = "EasyDotnetTestRunnerPassed"
      end
      left_hl_end = #left_text
    end
    if last_run_time then left_text = left_text .. "  " .. last_run_time end
  end

  local empty_rs = { totalRunning = 0, totalPassed = 0, totalFailed = 0, totalSkipped = 0, totalInconclusive = 0, totalTests = 0 }
  local right_text, right_hls, right_dw = build_right_counts(rs or empty_rs)
  local left_dw = vim.fn.strdisplaywidth(left_text)

  local line, hls = left_text, {}
  if left_hl then table.insert(hls, { 0, left_hl_end, left_hl }) end
  if last_run_time and not loading then
    local ts_text = "  " .. last_run_time
    table.insert(hls, { #left_text - #ts_text, #left_text, "Comment" })
  end

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
    vim.hl.range(M.header_buf, ns_header, hl[3], { 0, hl[1] }, { 0, hl[2] })
  end
end

local function build_footer_line(node, loading)
  if loading then
    local rs = state.runner_status
    if rs and rs.overallStatus == "Cancelling" then return " Kill", { { 1, 5, "EasyDotnetTestRunnerFailed" } } end
    if rs and rs.overallStatus == "Killing" then return "", {} end
    return " Cancel", { { 1, 7, "Comment" } }
  end
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
    vim.hl.range(M.footer_buf, ns_footer, h[3], { 0, h[1] }, { 0, h[2] })
  end
end

-- ── single-window float chrome (border title + footer) ──────────────────────
local has_footer_support = vim.fn.has("nvim-0.10") == 1

local function build_right_count_chunks(rs)
  local ic = M.options.icons or {}
  local chunks, dw = {}, 0
  local function push(text, hl)
    chunks[#chunks + 1] = { text, hl }
    dw = dw + vim.fn.strdisplaywidth(text)
  end
  if (rs.totalRunning or 0) > 0 then push(string.format("%s %d  ", ic.reload, rs.totalRunning), "EasyDotnetTestRunnerRunning") end
  push(string.format("%s %d  ", ic.success, rs.totalPassed or 0), "EasyDotnetTestRunnerPassed")
  push(string.format("%s %d  ", ic.failed, rs.totalFailed or 0), "EasyDotnetTestRunnerFailed")
  push(string.format("%s %d  ", ic.skipped, rs.totalSkipped or 0), "EasyDotnetTestRunnerSkipped")
  if (rs.totalInconclusive or 0) > 0 then push(string.format("%s %d  ", ic.inconclusive or ic.skipped, rs.totalInconclusive), "EasyDotnetTestRunnerInconclusive") end
  push(string.format("%d tests ", rs.totalTests or 0), "Comment")
  return chunks, dw
end

-- Top border: status on the left, live counts pushed to the right edge.
local function build_title_chunks(rs, frame)
  rs = rs or {}
  local width = (M.win and vim.api.nvim_win_is_valid(M.win)) and vim.api.nvim_win_get_width(M.win) or math.floor(vim.o.columns * 0.8)
  local status = rs.overallStatus or "Idle"

  local left_text, left_hl
  if rs.isLoading then
    left_text = " " .. (frame or spinner.frames[spinner.frame]) .. "  " .. status .. " "
    left_hl = "EasyDotnetTestRunnerRunning"
  elseif status == "Idle" then
    left_text = "  Test Runner "
    left_hl = "EasyDotnetTestRunnerSolution"
  else
    left_text = "  " .. status .. " "
    if status == "Failed" or status == "Killed" then
      left_hl = "EasyDotnetTestRunnerFailed"
    elseif status == "Cancelled" then
      left_hl = "Comment"
    elseif status == "Inconclusive" then
      left_hl = "EasyDotnetTestRunnerInconclusive"
    else
      left_hl = "EasyDotnetTestRunnerPassed"
    end
  end

  local right_chunks, right_dw = build_right_count_chunks(rs)
  local pad = math.max(1, width - vim.fn.strdisplaywidth(left_text) - right_dw)
  local chunks = { { left_text, left_hl }, { string.rep(" ", pad) } }
  for _, c in ipairs(right_chunks) do
    chunks[#chunks + 1] = c
  end
  return chunks
end

local footer_label = {
  Run = "run",
  Debug = "debug",
  Invalidate = "reset",
  GoToSource = "go to file",
  PeekResults = "peek",
  GetBuildErrors = "errors",
  Cancel = "cancel",
}
local footer_map = {
  Run = "run",
  Debug = "debug_test",
  Invalidate = "refresh_testrunner",
  GoToSource = "go_to_file",
  PeekResults = "peek_stacktrace",
  GetBuildErrors = "get_build_errors",
  Cancel = "cancel",
}

local function key_for(map_name)
  local m = (M.options.mappings or {})[map_name]
  return m and m.lhs or "?"
end

-- Bottom border: contextual "key action" legend for the node under the cursor.
local function build_footer_chunks(node)
  local rs = state.runner_status
  if rs and rs.isLoading then
    if rs.overallStatus == "Killing" then return nil end
    local label = rs.overallStatus == "Cancelling" and "kill" or "cancel"
    return { { " " .. key_for("cancel") .. " ", "EasyDotnetTestRunnerFailed" }, { label .. " ", "Comment" } }
  end

  if not node or not node.availableActions or #node.availableActions == 0 then return nil end

  local chunks = { { " " } }
  for _, action in ipairs(node.availableActions) do
    local label = footer_label[action]
    local map_name = footer_map[action]
    if label and map_name then
      chunks[#chunks + 1] = { key_for(map_name) .. " ", "Special" }
      chunks[#chunks + 1] = { label .. "   ", "Comment" }
    end
  end
  if #chunks <= 1 then return nil end
  return chunks
end

local function set_float_chrome(frame)
  if M.viewmode ~= "float" then return end
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end
  local g = M.float_geom
  if not g then return end
  local cfg = {
    relative = "editor",
    row = g.row,
    col = g.col,
    width = g.width,
    height = g.height,
    border = "rounded",
    title = build_title_chunks(state.runner_status, frame),
    title_pos = "left",
  }
  if has_footer_support then
    local f = (not M.options.hide_legend) and build_footer_chunks(M.node_at_cursor()) or nil
    cfg.footer = f or ""
    cfg.footer_pos = "left"
  end
  pcall(vim.api.nvim_win_set_config, M.win, cfg)
end

local function spinner_stop()
  if not spinner.timer then return end
  spinner.timer:stop()
  spinner.timer:close()
  spinner.timer = nil
  if M.header_buf and vim.api.nvim_buf_is_valid(M.header_buf) then vim.api.nvim_buf_clear_namespace(M.header_buf, ns_spinner, 0, -1) end
end

local function spinner_tick()
  if M.viewmode == "float" then
    if not M.win or not vim.api.nvim_win_is_valid(M.win) then
      spinner_stop()
      return
    end
    spinner.frame = (spinner.frame % #spinner.frames) + 1
    set_float_chrome(spinner.frames[spinner.frame])
    return
  end
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
  local height = math.floor(vim.o.lines * 0.8)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)
  return { width = width, height = height, col = col, row = row }
end

local function resize_floats()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end
  local dims = get_float_dims()
  M.float_geom = dims
  vim.api.nvim_win_set_config(M.win, { width = dims.width, height = dims.height, col = dims.col, row = dims.row, relative = "editor" })
  M.refresh()
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

local function lock_aux_focus()
  local group = vim.api.nvim_create_augroup("EasyDotnetTestRunnerAuxFocus", { clear = true })
  local function create_redirect_autocmd(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.api.nvim_create_autocmd("WinEnter", {
      group = group,
      buffer = buf,
      callback = function()
        if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end
        local current = vim.api.nvim_get_current_win()
        local in_header = M.header_win and vim.api.nvim_win_is_valid(M.header_win) and current == M.header_win
        local in_footer = M.footer_win and vim.api.nvim_win_is_valid(M.footer_win) and current == M.footer_win
        if not in_header and not in_footer then return end
        pcall(vim.api.nvim_set_current_win, M.win)
      end,
    })
  end

  create_redirect_autocmd(M.header_buf)
  create_redirect_autocmd(M.footer_buf)
end

local function close_aux_wins()
  for _, w in ipairs({ M.header_win, M.footer_win }) do
    if w and vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_close(w, true) end
  end
  M.header_win = nil
  M.footer_win = nil
end

local function disable_gutter(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  pcall(vim.api.nvim_set_option_value, "statuscolumn", "", { win = win })
end

---@param mode "float"|"split"|"vsplit"
function M.open(mode, options)
  M.options = options or M.options
  M.viewmode = mode

  local term_mgr = require("easy-dotnet.terminal.manager")
  if term_mgr.panel_win and vim.api.nvim_win_is_valid(term_mgr.panel_win) then require("easy-dotnet.terminal").hide() end

  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = make_scratch_buf("Test Runner")
    vim.api.nvim_buf_set_name(M.buf, "Test Runner")
  end

  if mode == "float" then
    local dims = get_float_dims()
    M.float_geom = dims

    M.win = vim.api.nvim_open_win(M.buf, true, {
      relative = "editor",
      width = dims.width,
      height = dims.height,
      col = dims.col,
      row = dims.row,
      style = "minimal",
      border = "rounded",
      focusable = true,
      title = build_title_chunks(state.runner_status),
      title_pos = "left",
    })
    disable_gutter(M.win)

    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(M.win),
      once = true,
      callback = function()
        spinner_stop()
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
    disable_gutter(M.win)

    open_header_split()
    if not M.options.hide_legend then open_footer_split() end
    lock_aux_focus()

    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(M.win),
      once = true,
      callback = function()
        spinner_stop()
        close_aux_wins()
        M.win = nil
        pcall(vim.api.nvim_del_augroup_by_name, "EasyDotnetTestRunnerAuxFocus")
        pcall(vim.api.nvim_del_augroup_by_name, "EasyDotnetTestRunnerResize")
      end,
    })
  end

  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_set_option_value("cursorline", true, { win = M.win })
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = M.buf,
      callback = function()
        if M.viewmode == "float" then
          set_float_chrome()
        else
          render_footer(M.node_at_cursor())
        end
      end,
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
  pcall(vim.api.nvim_del_augroup_by_name, "EasyDotnetTestRunnerAuxFocus")
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, false)
    M.win = nil
  end
end

local status_highlights = {
  Passed = "EasyDotnetTestRunnerPassed",
  Failed = "EasyDotnetTestRunnerFailed",
  Inconclusive = "EasyDotnetTestRunnerInconclusive",
  Skipped = "EasyDotnetTestRunnerSkipped",
  Running = "EasyDotnetTestRunnerRunning",
  Debugging = "EasyDotnetTestRunnerRunning",
  Building = "EasyDotnetTestRunnerRunning",
  BuildFailed = "EasyDotnetTestRunnerFailed",
  NotRun = "EasyDotnetTestRunnerFailed",
  Discovering = "EasyDotnetTestRunnerRunning",
  Queued = "EasyDotnetTestRunnerQueued",
  Cancelling = "EasyDotnetTestRunnerRunning",
  Cancelled = "Comment",
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
    ProbableTest = icons.test,
  })[node_type] or "?"
end

local function get_status_icon(stype)
  local icons = M.options.icons
  return ({
    Failed = " " .. icons.failed,
    Inconclusive = " " .. (icons.inconclusive or icons.skipped),
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

local function render_node(node, prefix)
  local ntype = node.type and node.type.type or ""
  local pre = node_pre_icon(ntype)

  local status_suffix = ""
  local hl = nil
  if node.status then
    local stype = node.status.type
    status_suffix = get_status_icon(stype)
    hl = status_highlights[stype]
    if node.status.durationDisplay then status_suffix = status_suffix .. "  " .. node.status.durationDisplay end
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
      ProbableTest = "EasyDotnetTestRunnerProbable",
    })[ntype]
  end

  return string.format("%s%s %s%s", prefix, pre, node.displayName, status_suffix), hl
end

function M.refresh()
  refresh_pending = false

  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  local rs = state.runner_status
  if rs and rs.isLoading then
    was_loading = true
    spinner_start()
  else
    if was_loading then
      last_run_time = os.date("%H:%M:%S")
      was_loading = false
    end
    spinner_stop()
  end

  if M.viewmode == "float" then
    set_float_chrome()
  else
    render_header()
    render_footer(M.node_at_cursor())
  end

  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end

  vim.api.nvim_buf_clear_namespace(M.buf, ns_id, 0, -1)
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.buf })

  local lines = {}
  local highlights = {}
  local lasts = {}
  state.traverse_visible(function(node, depth, is_last)
    lasts[depth] = is_last
    local prefix = " "
    if depth > 0 then
      for i = 1, depth - 1 do
        prefix = prefix .. (lasts[i] and "   " or "│  ")
      end
      prefix = prefix .. (is_last and "└─ " or "├─ ")
    end

    local line, hl = render_node(node, prefix)
    lines[#lines + 1] = line
    local row = #lines - 1
    highlights[#highlights + 1] = { row = row, hl = "Comment", s = 0, e = #prefix }
    if hl then highlights[#highlights + 1] = { row = row, hl = hl, s = #prefix, e = -1 } end
  end)

  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.buf })

  for _, h in ipairs(highlights) do
    vim.hl.range(M.buf, ns_id, h.hl, { h.row, h.s }, { h.row, h.e })
  end
end

function M.schedule_refresh()
  if refresh_pending then return end
  refresh_pending = true
  vim.schedule(function() M.refresh() end)
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

--- Expand the ancestors of node_id so it becomes visible, then move the cursor to it.
---@param node_id string
function M.focus_node(node_id)
  local node = state.nodes[node_id]
  if not node then return end

  local parent_id = node.parentId
  while parent_id do
    local parent = state.nodes[parent_id]
    if not parent then break end
    parent.expanded = true
    parent_id = parent.parentId
  end

  M.refresh()

  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end

  local target_row, row = nil, 0
  state.traverse_visible(function(n)
    row = row + 1
    if n.id == node_id and not target_row then target_row = row end
  end)

  if target_row then
    pcall(vim.api.nvim_win_set_cursor, M.win, { target_row, 0 })
    vim.api.nvim_win_call(M.win, function() vim.cmd("normal! zz") end)
    render_footer(M.node_at_cursor())
  end
end

return M
