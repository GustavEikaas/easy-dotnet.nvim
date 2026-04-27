local spinner_frames = require("easy-dotnet.ui-modules.jobs").spinner_frames
local manager = require("easy-dotnet.terminal.manager")

local ns_id = vim.api.nvim_create_namespace("EasyDotnetTabline")
local spinner_idx = 1
local timer = nil

local M = {}

local function is_server_running(tab) return tab.owned_by == "server" and tab.last_status == "running" end

local function any_server_running()
  for _, tab in ipairs(manager.get_all()) do
    if is_server_running(tab) then return true end
  end
  return false
end

local function tab_icon(tab)
  if is_server_running(tab) then
    return "▶", "DiagnosticInfo"
  elseif tab.last_status == "finished" then
    return tab.last_exit_code == 0 and "✓" or "✗", tab.last_exit_code == 0 and "String" or "ErrorMsg"
  else
    return "●", "Comment"
  end
end

local function header_icon(tab)
  if is_server_running(tab) then
    return spinner_frames[spinner_idx], "DiagnosticInfo"
  elseif tab.last_status == "finished" then
    return tab.last_exit_code == 0 and "✓" or "✗", tab.last_exit_code == 0 and "String" or "ErrorMsg"
  else
    return "●", "Comment"
  end
end

local function get_panel_screen_pos()
  if not manager.panel_win or not vim.api.nvim_win_is_valid(manager.panel_win) then return nil end
  local pos = vim.api.nvim_win_get_position(manager.panel_win)
  local width = vim.api.nvim_win_get_width(manager.panel_win)
  return math.max(0, pos[1] - 2), pos[2], width
end

local function sync_position()
  if not manager.tabline_win or not vim.api.nvim_win_is_valid(manager.tabline_win) then return end
  local row, col, width = get_panel_screen_pos()
  if not row then return end
  vim.api.nvim_win_set_config(manager.tabline_win, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = 2,
  })
end

function M.render()
  if not manager.tabline_buf or not vim.api.nvim_buf_is_valid(manager.tabline_buf) then return end
  if not manager.panel_win or not vim.api.nvim_win_is_valid(manager.panel_win) then return end

  sync_position()

  local panel_width = vim.api.nvim_win_get_width(manager.panel_win)
  local tabs = manager.get_all()
  local active_tab = manager.active_id and manager.get(manager.active_id)

  local tabline_str = ""
  local segments = {}
  for _, tab in ipairs(tabs) do
    local icon, icon_hl = tab_icon(tab)
    local seg_start = #tabline_str
    local piece = string.format(" %s %s ", icon, tab.label)
    tabline_str = tabline_str .. piece
    segments[#segments + 1] = {
      start = seg_start,
      icon_end = seg_start + 1 + #icon,
      label_end = seg_start + #piece - 1,
      icon_hl = icon_hl,
      is_active = tab.id == manager.active_id,
    }
  end
  local plus_start = #tabline_str
  tabline_str = tabline_str .. " [+]"

  local header_str = ""
  local header_segs = nil
  if active_tab then
    local icon, icon_hl = header_icon(active_tab)
    local exec = active_tab.exec_name or ""
    local args = active_tab.full_args or ""
    local max_args = math.floor(panel_width * 0.7)
    if #args > max_args then args = args:sub(1, max_args) .. "..." end
    local pad = 1
    header_str = string.rep(" ", pad) .. string.format("%s %s %s", icon, exec, args)
    header_segs = {
      icon_hl = icon_hl,
      icon_s = pad,
      icon_e = pad + #icon,
      exec_s = pad + #icon + 1,
      exec_e = pad + #icon + 1 + #exec,
      args_s = pad + #icon + 1 + #exec + 1,
      args_e = pad + #icon + 1 + #exec + 1 + #args,
    }
  end

  vim.api.nvim_buf_set_option(manager.tabline_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(manager.tabline_buf, 0, -1, false, { tabline_str, header_str })
  vim.api.nvim_buf_clear_namespace(manager.tabline_buf, ns_id, 0, -1)

  for _, seg in ipairs(segments) do
    local base_hl = seg.is_active and "TabLineSel" or "TabLine"
    vim.api.nvim_buf_add_highlight(manager.tabline_buf, ns_id, base_hl, 0, seg.start, seg.label_end + 1)
    vim.api.nvim_buf_add_highlight(manager.tabline_buf, ns_id, seg.icon_hl, 0, seg.start + 1, seg.icon_end)
  end
  vim.api.nvim_buf_add_highlight(manager.tabline_buf, ns_id, "Special", 0, plus_start, plus_start + 4)

  if header_segs then
    vim.api.nvim_buf_add_highlight(manager.tabline_buf, ns_id, header_segs.icon_hl, 1, header_segs.icon_s, header_segs.icon_e)
    vim.api.nvim_buf_add_highlight(manager.tabline_buf, ns_id, "Title", 1, header_segs.exec_s, header_segs.exec_e)
    vim.api.nvim_buf_add_highlight(manager.tabline_buf, ns_id, "Comment", 1, header_segs.args_s, header_segs.args_e)
  end

  vim.api.nvim_buf_set_option(manager.tabline_buf, "modifiable", false)
end

local function start_timer()
  if timer then return end
  timer = vim.loop.new_timer()
  timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      spinner_idx = (spinner_idx % #spinner_frames) + 1
      M.render()
      if not any_server_running() then M.stop_timer() end
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

  if not manager.tabline_buf or not vim.api.nvim_buf_is_valid(manager.tabline_buf) then
    manager.tabline_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(manager.tabline_buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(manager.tabline_buf, "modifiable", false)
  end

  if manager.tabline_win and vim.api.nvim_win_is_valid(manager.tabline_win) then vim.api.nvim_win_close(manager.tabline_win, true) end

  local row, col, width = get_panel_screen_pos()
  manager.tabline_win = vim.api.nvim_open_win(manager.tabline_buf, false, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = 2,
    style = "minimal",
    focusable = false,
    zindex = 101,
  })
  vim.api.nvim_win_set_option(manager.tabline_win, "winhighlight", "Normal:TabLineFill,FloatBorder:TabLineFill")

  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = vim.api.nvim_create_augroup("EasyDotnetOverlaySync", { clear = true }),
    callback = function()
      if not manager.panel_win or not vim.api.nvim_win_is_valid(manager.panel_win) then return end
      if not manager.tabline_win or not vim.api.nvim_win_is_valid(manager.tabline_win) then return end
      sync_position()
      M.render()
    end,
  })

  M.render()
end

function M.destroy()
  M.stop_timer()
  pcall(vim.api.nvim_del_augroup_by_name, "EasyDotnetOverlaySync")
  if manager.tabline_win and vim.api.nvim_win_is_valid(manager.tabline_win) then vim.api.nvim_win_close(manager.tabline_win, true) end
  manager.tabline_win = nil
end

return M
