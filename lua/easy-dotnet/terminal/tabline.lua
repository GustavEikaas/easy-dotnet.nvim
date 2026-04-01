local spinner_frames = require("easy-dotnet.ui-modules.jobs").spinner_frames
local Tab = require("easy-dotnet.terminal.tab")
local manager = require("easy-dotnet.terminal.manager")

local ns_id = vim.api.nvim_create_namespace("EasyDotnetTabline")
local spinner_idx = 1
local timer = nil

local M = {}

local function get_icon(tab)
  if tab.owned_by == "server" and Tab.is_running(tab) then
    local icon = spinner_frames[spinner_idx]
    spinner_idx = (spinner_idx % #spinner_frames) + 1
    return icon, "DiagnosticInfo"
  elseif tab.last_status == "finished" then
    if tab.last_exit_code == 0 then
      return "✓", "String"
    else
      return "", "ErrorMsg"
    end
  else
    return "●", "Comment"
  end
end

function M.render()
  local state = manager
  if not state.tabline_buf or not vim.api.nvim_buf_is_valid(state.tabline_buf) then return end
  if not state.panel_win or not vim.api.nvim_win_is_valid(state.panel_win) then return end

  local panel_width = vim.api.nvim_win_get_width(state.panel_win)
  if state.tabline_win and vim.api.nvim_win_is_valid(state.tabline_win) then
    local cfg = vim.api.nvim_win_get_config(state.tabline_win)
    if cfg.width ~= panel_width then vim.api.nvim_win_set_config(state.tabline_win, { width = panel_width }) end
  end

  local tabs = manager.get_all()
  local line = ""
  local segments = {}

  for _, tab in ipairs(tabs) do
    local icon, icon_hl = get_icon(tab)
    local is_active = tab.id == manager.active_id
    local segment_start = #line
    local piece = string.format(" %s %s ", icon, tab.label)
    line = line .. piece
    segments[#segments + 1] = {
      start = segment_start,
      icon_end = segment_start + 1 + #icon,
      label_start = segment_start + 1 + #icon + 1,
      label_end = segment_start + #piece - 1,
      tab_id = tab.id,
      icon_hl = icon_hl,
      is_active = is_active,
    }
  end
  line = line .. " [+]"
  local plus_start = #line - 4

  vim.api.nvim_buf_set_option(state.tabline_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.tabline_buf, 0, -1, false, { line })
  vim.api.nvim_buf_clear_namespace(state.tabline_buf, ns_id, 0, -1)

  for _, seg in ipairs(segments) do
    local base_hl = seg.is_active and "TabLineSel" or "TabLine"
    vim.api.nvim_buf_add_highlight(state.tabline_buf, ns_id, base_hl, 0, seg.start, seg.label_end + 1)
    vim.api.nvim_buf_add_highlight(state.tabline_buf, ns_id, seg.icon_hl, 0, seg.start + 1, seg.icon_end)
  end
  vim.api.nvim_buf_add_highlight(state.tabline_buf, ns_id, "Special", 0, plus_start, plus_start + 4)

  vim.api.nvim_buf_set_option(state.tabline_buf, "modifiable", false)
end

local function start_timer()
  if timer then return end
  timer = vim.loop.new_timer()
  timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      local tabs = manager.get_all()
      local any_server_running = false
      for _, tab in ipairs(tabs) do
        if tab.owned_by == "server" and Tab.is_running(tab) then
          any_server_running = true
          break
        end
      end
      M.render()
      local ok, header = pcall(require, "easy-dotnet.terminal.header")
      if ok then header.render() end
      if not any_server_running then M.stop_timer() end
    end)
  )
end

function M.stop_timer()
  if timer then
    timer:stop()
    if not timer:is_closing() then timer:close() end
    timer = nil
  end
end

function M.ensure_timer() start_timer() end

function M.create(panel_win)
  manager.panel_win = panel_win

  if manager.tabline_buf and vim.api.nvim_buf_is_valid(manager.tabline_buf) then
    if manager.tabline_win and vim.api.nvim_win_is_valid(manager.tabline_win) then return end
  else
    manager.tabline_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(manager.tabline_buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(manager.tabline_buf, "modifiable", false)

    vim.keymap.set("n", "<CR>", function()
      local col = vim.fn.col(".") - 1
      local pos = 0
      for _, tab in ipairs(manager.get_all()) do
        local icon, _ = get_icon(tab)
        local piece = string.format(" %s %s ", icon, tab.label)
        if col >= pos and col < pos + #piece then
          manager.set_active(tab.id)
          return
        end
        pos = pos + #piece
      end
      if col >= pos then
        local new_tab = manager.new_user_terminal()
        manager.set_active(new_tab.id)
        local ok, term = pcall(require, "easy-dotnet.terminal")
        if ok then term.show() end
      end
    end, { buffer = manager.tabline_buf, nowait = true })

    vim.keymap.set("n", "l", function()
      local tabs = manager.get_all()
      for i, tab in ipairs(tabs) do
        if tab.id == manager.active_id then
          local next = tabs[i + 1] or tabs[1]
          manager.set_active(next.id)
          return
        end
      end
    end, { buffer = manager.tabline_buf, nowait = true })

    vim.keymap.set("n", "h", function()
      local tabs = manager.get_all()
      for i, tab in ipairs(tabs) do
        if tab.id == manager.active_id then
          local prev = tabs[i - 1] or tabs[#tabs]
          manager.set_active(prev.id)
          return
        end
      end
    end, { buffer = manager.tabline_buf, nowait = true })

    vim.keymap.set("n", "d", function()
      if manager.active_id then manager.remove(manager.active_id) end
    end, { buffer = manager.tabline_buf, nowait = true })
  end

  local width = vim.api.nvim_win_get_width(panel_win)
  manager.tabline_win = vim.api.nvim_open_win(manager.tabline_buf, false, {
    relative = "win",
    win = panel_win,
    row = 0,
    col = 0,
    width = width,
    height = 1,
    style = "minimal",
    focusable = false,
    zindex = 101,
  })
  vim.api.nvim_win_set_option(manager.tabline_win, "winhighlight", "Normal:TabLineFill,FloatBorder:TabLineFill")

  M.render()
end

function M.destroy()
  M.stop_timer()
  if manager.tabline_win and vim.api.nvim_win_is_valid(manager.tabline_win) then vim.api.nvim_win_close(manager.tabline_win, true) end
  manager.tabline_win = nil
end

return M
