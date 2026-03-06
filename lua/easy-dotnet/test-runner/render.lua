--- Test runner render module.
--- Pure renderer — reads from state.lua, writes to a buffer.
--- No test logic, no tree building, no status aggregation.

local ns_id = require("easy-dotnet.constants").ns_id
local state = require("easy-dotnet.test-runner.state")

local M = {
  buf = nil,
  win = nil,
  header_buf = nil,
  header_win = nil,
  options = {},
}

local ns_header = vim.api.nvim_create_namespace("easy_dotnet_testrunner_header")
local ns_loader = vim.api.nvim_create_namespace("easy_dotnet_testrunner_loader")

-- ---------------------------------------------------------------------------
-- Sliding loader
-- ---------------------------------------------------------------------------

local loader = {
  timer = nil,
  pos = -180, -- start off left edge so segment grows in
  width = 180,
  step = 3,
  interval = 60,
}

local function loader_tick()
  if not M.header_buf or not vim.api.nvim_buf_is_valid(M.header_buf) then return end
  if not M.header_win or not vim.api.nvim_win_is_valid(M.header_win) then return end

  local win_width = vim.api.nvim_win_get_width(M.header_win)

  -- Uniform ▁ track across the full width — color does all the work
  local line = string.rep("▂", win_width)

  vim.api.nvim_buf_clear_namespace(M.header_buf, ns_loader, 0, -1)
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.header_buf })
  vim.api.nvim_buf_set_lines(M.header_buf, 1, 2, false, { line })
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.header_buf })

  local seg_start = math.max(loader.pos, 0)
  local seg_end = math.min(loader.pos + loader.width, win_width)
  if seg_start < seg_end then vim.api.nvim_buf_set_extmark(M.header_buf, ns_loader, 1, seg_start, {
    end_col = seg_end,
    hl_group = "EasyDotnetTestRunnerRunning",
    priority = 150,
  }) end

  loader.pos = loader.pos + loader.step
  if loader.pos >= win_width then loader.pos = -loader.width end
end

local function loader_start()
  if loader.timer then return end -- already running
  loader.pos = -loader.width
  loader.timer = vim.uv.new_timer()
  loader.timer:start(0, loader.interval, vim.schedule_wrap(loader_tick))
end

local function loader_stop()
  if not loader.timer then return end
  loader.timer:stop()
  loader.timer:close()
  loader.timer = nil
  if M.header_buf and vim.api.nvim_buf_is_valid(M.header_buf) then
    vim.api.nvim_buf_clear_namespace(M.header_buf, ns_loader, 0, -1)
    -- Restore the legend row — refresh_header will rewrite it on next render
    vim.api.nvim_set_option_value("modifiable", true, { buf = M.header_buf })
    vim.api.nvim_buf_set_lines(M.header_buf, 1, 2, false, { "" })
    vim.api.nvim_set_option_value("modifiable", false, { buf = M.header_buf })
  end
end

-- Maps action → { key fallback, display label }
local action_labels = {
  Run = { key = "r", label = "run" },
  Debug = { key = "d", label = "debug" },
  Invalidate = { key = "i", label = "invalidate" },
  GoToSource = { key = "gf", label = "source" },
  PeekResults = { key = "p", label = "peek" },
  GetBuildErrors = { key = "e", label = "build errors" },
  Cancel = { key = "<C-c>", label = "cancel" },
}

-- ---------------------------------------------------------------------------
-- Header content
-- ---------------------------------------------------------------------------

local function build_status_line(rs)
  if not rs then return "", {} end

  local hls = {}
  local parts = {}
  local col = 0

  local function push(text, hl)
    if hl then table.insert(hls, { col, col + #text, hl }) end
    table.insert(parts, text)
    col = col + #text
  end

  local passed_str = string.format("  %d", rs.totalPassed)
  local failed_str = string.format("   %d", rs.totalFailed)
  local skipped_str = string.format("  ⊘ %d", rs.totalSkipped)
  local total_str = string.format("  %d tests", rs.totalTests or 0)

  -- No loading text — the sliding bar in ns_loader communicates activity
  push(" ", nil)
  push(passed_str, "EasyDotnetTestRunnerPassed")
  push(failed_str, "EasyDotnetTestRunnerFailed")
  push(skipped_str, "EasyDotnetTestRunnerSkipped")
  push(total_str, "Comment")

  if not rs.isLoading then push(string.format("   %s", rs.overallStatus or "Idle"), "Comment") end

  return table.concat(parts), hls
end

local function build_legend_line(node, opts)
  if not node or not node.availableActions or #node.availableActions == 0 then return " No actions available", {} end

  local km = opts and opts.mappings or {}
  local parts = {}
  local hls = {}
  local col = 1 -- starts at 1 to account for the leading " " prepended at the end

  for i, action in ipairs(node.availableActions) do
    local def = action_labels[action]
    if def then
      local key = (km[action:lower()] and km[action:lower()].lhs) or def.key
      local bracket = "[" .. key .. "]"
      local label = " " .. def.label

      if i > 1 then
        table.insert(parts, "  ")
        col = col + 2
      end

      -- [key] highlighted as Special
      table.insert(hls, { col, col + #bracket, "Special" })
      col = col + #bracket

      -- label highlighted as Comment
      table.insert(hls, { col, col + #label, "Comment" })
      col = col + #label

      table.insert(parts, bracket .. label)
    end
  end

  return " " .. table.concat(parts), hls
end

local function refresh_header(node)
  if not M.header_buf or not vim.api.nvim_buf_is_valid(M.header_buf) then return end
  if not M.header_win or not vim.api.nvim_win_is_valid(M.header_win) then return end

  vim.api.nvim_buf_clear_namespace(M.header_buf, ns_header, 0, -1)
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.header_buf })

  local rs = state.runner_status
  local status_line, status_hls = build_status_line(rs)

  -- When loading, the legend row is owned by the sliding bar — don't overwrite it
  if rs and rs.isLoading then
    local win_width = vim.api.nvim_win_get_width(M.header_win)
    local pad = win_width - vim.fn.strdisplaywidth(status_line)
    if pad > 0 then status_line = status_line .. string.rep(" ", pad) end

    vim.api.nvim_buf_set_lines(M.header_buf, 0, 1, false, { status_line })
    vim.api.nvim_set_option_value("modifiable", false, { buf = M.header_buf })

    for _, hl in ipairs(status_hls) do
      vim.api.nvim_buf_add_highlight(M.header_buf, ns_header, hl[3], 0, hl[1], hl[2])
    end

    loader_start()
    return
  end

  local legend_line, legend_hls = build_legend_line(node, M.options)
  vim.api.nvim_buf_set_lines(M.header_buf, 0, -1, false, { status_line, legend_line })
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.header_buf })

  for _, hl in ipairs(status_hls) do
    vim.api.nvim_buf_add_highlight(M.header_buf, ns_header, hl[3], 0, hl[1], hl[2])
  end
  for _, hl in ipairs(legend_hls) do
    vim.api.nvim_buf_add_highlight(M.header_buf, ns_header, hl[3], 1, hl[1], hl[2])
  end

  loader_stop()
end

-- ---------------------------------------------------------------------------
-- Opening windows
-- ---------------------------------------------------------------------------

local function make_header_buf()
  if M.header_buf and vim.api.nvim_buf_is_valid(M.header_buf) then return end
  M.header_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.header_buf })
  vim.api.nvim_set_option_value("filetype", "easy-dotnet", { buf = M.header_buf })
end

local function open_header_float(main_cfg)
  make_header_buf()
  M.header_win = vim.api.nvim_open_win(M.header_buf, false, {
    relative = "editor",
    width = main_cfg.width,
    height = 2,
    col = main_cfg.col,
    row = main_cfg.row,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 51, -- above the main float (default is 50)
  })
  vim.wo[M.header_win].cursorline = false
  vim.wo[M.header_win].winhighlight = "Normal:NormalFloat"
end

local function open_header_split()
  make_header_buf()
  vim.cmd("2split")
  M.header_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.header_win, M.header_buf)
  vim.wo[M.header_win].cursorline = false
  vim.wo[M.header_win].statusline = ""
  vim.wo[M.header_win].winfixheight = true
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.header_buf })
  -- Return focus to the caller so the main buf opens below
  vim.cmd("wincmd j")
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---@param mode "float"|"split"|"vsplit"
function M.open(mode, options)
  M.options = options or M.options

  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(M.buf, "Test Runner")
    vim.api.nvim_set_option_value("filetype", "easy-dotnet", { buf = M.buf })
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.buf })
  end

  if mode == "float" then
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local col = math.floor((vim.o.columns - width) / 2)
    local row = math.floor((vim.o.lines - height) / 2)

    -- Header sits above the main float
    open_header_float({ width = width, height = height, col = col, row = row - 3 })

    -- Main float: shifted down to give header room (header=2 lines + 1 gap)
    M.win = vim.api.nvim_open_win(M.buf, true, {
      relative = "editor",
      width = width,
      height = height - 3,
      col = col,
      row = row,
      style = "minimal",
      border = "rounded",
      focusable = true,
    })

    -- Close header when float is closed
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(M.win),
      once = true,
      callback = function()
        loader_stop()
        if M.header_win and vim.api.nvim_win_is_valid(M.header_win) then vim.api.nvim_win_close(M.header_win, true) end
        M.win = nil
        M.header_win = nil
      end,
    })
  elseif mode == "split" or mode == "vsplit" then
    if mode == "vsplit" then
      local w = options and options.vsplit_width or math.floor(vim.o.columns * 0.4)
      vim.cmd((options and options.vsplit_pos or "") .. tostring(w) .. "vsplit")
      M.win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(M.win, M.buf)
    else
      vim.cmd("split")
      M.win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(M.win, M.buf)
    end

    -- Pin header above the main split
    open_header_split()

    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(M.win),
      once = true,
      callback = function()
        if M.header_win and vim.api.nvim_win_is_valid(M.header_win) then vim.api.nvim_win_close(M.header_win, true) end
        M.win = nil
        M.header_win = nil
      end,
    })
  end

  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_set_option_value("cursorline", true, { win = M.win })
    -- Update legend on cursor move
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = M.buf,
      callback = function() refresh_header(M.node_at_cursor()) end,
    })
  end

  M.refresh()
end

function M.hide()
  if M.header_win and vim.api.nvim_win_is_valid(M.header_win) then
    vim.api.nvim_win_close(M.header_win, true)
    M.header_win = nil
  end
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, false)
    M.win = nil
  end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local status_highlights = {
  Passed = "EasyDotnetTestRunnerPassed",
  Failed = "EasyDotnetTestRunnerFailed",
  Skipped = "EasyDotnetTestRunnerSkipped",
  Running = "EasyDotnetTestRunnerRunning",
  Debugging = "EasyDotnetTestRunnerRunning",
  Building = "EasyDotnetTestRunnerRunning",
  Discovering = "EasyDotnetTestRunnerRunning",
  Queued = "EasyDotnetTestRunnerRunning",
  Cancelling = "EasyDotnetTestRunnerRunning",
  Cancelled = "EasyDotnetTestRunnerFailed",
}

local status_icons = {
  Failed = " ✗",
  Skipped = " ⊘",
  Running = " ⟳",
  Debugging = " ⟳",
  Building = " ⟳",
  Discovering = "⟳",
  Queued = " …",
  Cancelling = " ⟳",
  Cancelled = " ✗",
}

local function node_pre_icon(node_type, opts)
  local icons = opts and opts.icons or {}
  return ({
    Solution = icons.sln or "󰘼",
    Project = icons.project or "",
    Namespace = icons.dir or "",
    TestClass = icons.dir or "",
    TheoryGroup = icons.package or "",
    TestMethod = icons.test or "󰙨",
    Subcase = icons.test or "󰙨",
  })[node_type] or "?"
end

local function render_node(node, depth)
  local indent = string.rep(" ", depth * 2)
  local ntype = node.type and node.type.type or ""
  local pre = node_pre_icon(ntype, M.options)
  local icons = M.options.icons or {}
  local children = state.children(node.id)
  local expand_icon
  if #children > 0 then
    expand_icon = node.expanded and (icons.expanded or " ") or (icons.collapsed or " ")
  else
    expand_icon = " "
  end

  local status_suffix = ""
  local hl = nil
  if node.status then
    local stype = node.status.type
    status_suffix = status_icons[stype] or ""
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

  return string.format("%s%s%s %s%s", indent, expand_icon, pre, node.displayName, status_suffix), hl
end

function M.refresh()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
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

  -- Update header: status always, legend based on node under cursor
  refresh_header(M.node_at_cursor())
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
