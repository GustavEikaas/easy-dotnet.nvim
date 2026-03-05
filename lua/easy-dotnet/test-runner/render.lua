local ns_id = require("easy-dotnet.constants").ns_id
local state = require("easy-dotnet.test-runner.state")

local M = {
  buf = nil,
  win = nil,
  options = {},
}

-- Maps status type → highlight group
local status_highlights = {
  Passed = "EasyDotnetTestRunnerPassed",
  Failed = "EasyDotnetTestRunnerFailed",
  Skipped = "EasyDotnetTestRunnerSkipped",
  Running = "EasyDotnetTestRunnerRunning",
  Debugging = "EasyDotnetTestRunnerRunning",
  Building = "EasyDotnetTestRunnerRunning",
  Discovering = "EasyDotnetTestRunnerRunning",
  Cancelling = "EasyDotnetTestRunnerRunning",
  Cancelled = "EasyDotnetTestRunnerFailed",
}

-- Maps status type → icon suffix shown after node name
local status_icons = {
  Passed = "", -- shown via preIcon change or just green highlight
  Failed = " ✗",
  Skipped = " ⊘",
  Running = " ⟳",
  Debugging = " ⟳",
  Building = " ⟳",
  Discovering = " ⟳",
  Queued = " …",
  Cancelling = " ⟳",
  Cancelled = " ✗",
}

-- Maps node type → pre-icon
local function node_pre_icon(node_type, options)
  local icons = options.icons or {}
  local map = {
    Solution = icons.sln or "󰘼",
    Project = icons.project or "",
    Namespace = icons.dir or "",
    TestClass = icons.dir or "",
    TestMethod = icons.test or "󰙨",
    Subcase = icons.test or "󰙨",
  }
  return map[node_type] or "?"
end

---@param node easy-dotnet.TestRunner.Node
---@param depth integer
---@return string, string|nil  line_text, highlight_group
local function render_node(node, depth)
  local icons = M.options.icons or {}
  local indent = string.rep(" ", depth * 2)
  local pre = node_pre_icon(node.type and node.type.type or "", M.options)
  local expand_icon = ""

  -- Show expand/collapse indicator for nodes that have children
  local children = state.children(node.id)
  if #children > 0 then expand_icon = node.expanded and (icons.expanded or " ") or (icons.collapsed or " ") end

  local status_suffix = ""
  local hl = nil

  if node.status then
    local stype = node.status.type
    status_suffix = status_icons[stype] or ""
    hl = status_highlights[stype]
    if stype == "Passed" and node.status.durationDisplay then status_suffix = "  " .. node.status.durationDisplay end
  end

  -- When runner is loading and this node has no status, dim it
  if not hl and node.type then
    local type_hls = {
      Solution = "EasyDotnetTestRunnerSolution",
      Project = "EasyDotnetTestRunnerProject",
      Namespace = "EasyDotnetTestRunnerDir",
      TestClass = "EasyDotnetTestRunnerDir",
      TestMethod = "EasyDotnetTestRunnerTest",
      Subcase = "EasyDotnetTestRunnerSubcase",
    }
    hl = type_hls[node.type.type]
  end

  local line = string.format("%s%s%s %s%s", indent, expand_icon, pre, node.displayName, status_suffix)
  return line, hl
end

local function build_winbar(rs)
  if not rs then return "" end

  local counts =
    string.format("%%#EasyDotnetTestRunnerPassed#  %d%%*" .. " %%#EasyDotnetTestRunnerFailed#  %d%%*" .. " %%#EasyDotnetTestRunnerSkipped# ⊘ %d%%*", rs.totalPassed, rs.totalFailed, rs.totalSkipped)

  local total = string.format("  %d tests", rs.totalTests or 0)

  if rs.isLoading then
    local op = rs.currentOperation or "Loading"
    return string.format(" ⟳ %s  %s%s", op, counts, total)
  end

  return string.format(" %s%s   %s", counts, total, rs.overallStatus or "")
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
  vim.wo[M.win].winbar = build_winbar(state.runner_status)
end

--- Translate cursor line → node
---@return easy-dotnet.TestRunner.Node|nil
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
    local height = math.floor(vim.o.lines * 0.8) + 1
    M.win = vim.api.nvim_open_win(M.buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = "minimal",
      border = "rounded",
    })
    vim.wo[M.win].winfixbuf = true
  elseif mode == "split" then
    vim.cmd("split")

    M.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.win, M.buf)
    local win = M.win
    vim.api.nvim_create_autocmd("WinClosed", {
      once = true,
      win = M.win,
      callback = function()
        if M.win == win then M.win = nil end
      end,
    })
  elseif mode == "vsplit" then
    local w = options and options.vsplit_width or math.floor(vim.o.columns * 0.4)
    vim.cmd((options and options.vsplit_pos or "") .. tostring(w) .. "vsplit")
    M.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.win, M.buf)
    local win = M.win
    vim.api.nvim_create_autocmd("WinClosed", {
      once = true,
      win = M.win,
      callback = function()
        if M.win == win then M.win = nil end
      end,
    })
  end

  if M.win and vim.api.nvim_win_is_valid(M.win) then vim.api.nvim_set_option_value("cursorline", true, { win = M.win }) end

  M.refresh()
end

function M.hide()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, false)
    M.win = nil
  end
end

function M.toggle(mode, options)
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    M.hide()
  else
    M.open(mode, options)
  end
end

return M
