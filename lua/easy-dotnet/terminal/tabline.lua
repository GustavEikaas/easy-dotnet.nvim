local spinner_frames = require("easy-dotnet.ui-modules.jobs").spinner_frames
local manager = require("easy-dotnet.terminal.manager")

local ns_id = vim.api.nvim_create_namespace("EasyDotnetTabline")
local spinner_idx = 1
local timer = nil

local M = {}

M._click_regions = { tabs = {}, plus = nil }

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

function M.render()
  if not manager.tabline_buf or not vim.api.nvim_buf_is_valid(manager.tabline_buf) then return end
  if not manager.panel_win or not vim.api.nvim_win_is_valid(manager.panel_win) then return end

  local panel_width = vim.api.nvim_win_get_width(manager.panel_win)
  local tabs = manager.get_all()
  local active_tab = manager.active_id and manager.get(manager.active_id)

  local tabline_str = ""
  local segments = {}
  local click_tabs = {}
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
    click_tabs[#click_tabs + 1] = { id = tab.id, s = seg_start, e = seg_start + #piece - 1 }
  end
  local plus_start = #tabline_str
  tabline_str = tabline_str .. " [+]"
  M._click_regions.tabs = click_tabs
  M._click_regions.plus = { s = plus_start, e = plus_start + 3 }

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

local function refocus_panel()
  if manager.panel_win and vim.api.nvim_win_is_valid(manager.panel_win) then vim.api.nvim_set_current_win(manager.panel_win) end
end

local function find_clicked_tab(col)
  for _, r in ipairs(M._click_regions.tabs) do
    if col >= r.s and col <= r.e then return r.id end
  end
end

local function in_plus(col)
  local p = M._click_regions.plus
  return p and col >= p.s and col <= p.e
end

local function on_left_click()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= manager.tabline_win then return end
  if pos.line ~= 1 then
    refocus_panel()
    return
  end
  local col = pos.column - 1
  local id = find_clicked_tab(col)
  if id then
    manager.set_active(id)
  elseif in_plus(col) then
    local new_tab = manager.new_user_terminal()
    manager.set_active(new_tab.id)
    M.ensure_timer()
  end
  refocus_panel()
end

local function on_middle_click()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= manager.tabline_win then return end
  if pos.line == 1 then
    local col = pos.column - 1
    local id = find_clicked_tab(col)
    if id then manager.remove(id) end
  end
  refocus_panel()
end

function M._attach_mouse_keymaps()
  local function in_tabline()
    local pos = vim.fn.getmousepos()
    return manager.tabline_win and pos.winid == manager.tabline_win
  end

  vim.keymap.set("n", "<LeftMouse>", function()
    if in_tabline() then
      vim.schedule(on_left_click)
      return ""
    end
    return "<LeftMouse>"
  end, { expr = true, replace_keycodes = true, silent = true, desc = "EasyDotnet terminal tabline click" })

  vim.keymap.set("n", "<2-LeftMouse>", function()
    if in_tabline() then
      vim.schedule(on_left_click)
      return ""
    end
    return "<2-LeftMouse>"
  end, { expr = true, replace_keycodes = true, silent = true })

  vim.keymap.set("n", "<MiddleMouse>", function()
    if in_tabline() then
      vim.schedule(on_middle_click)
      return ""
    end
    return "<MiddleMouse>"
  end, { expr = true, replace_keycodes = true, silent = true })
end

function M.create(panel_win)
  manager.panel_win = panel_win

  if not manager.tabline_buf or not vim.api.nvim_buf_is_valid(manager.tabline_buf) then
    manager.tabline_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(manager.tabline_buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(manager.tabline_buf, "modifiable", false)
  end

  if manager.tabline_win and vim.api.nvim_win_is_valid(manager.tabline_win) then vim.api.nvim_win_close(manager.tabline_win, true) end

  -- Real 2-line split directly above the terminal so the header owns its own
  -- screen rows instead of floating over (and hiding) neighbouring content.
  vim.api.nvim_set_current_win(panel_win)
  vim.cmd("aboveleft split")
  manager.tabline_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(manager.tabline_win, manager.tabline_buf)
  vim.api.nvim_win_set_height(manager.tabline_win, 2)

  local wo = vim.wo[manager.tabline_win]
  wo.winfixheight = true
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.cursorline = false
  wo.cursorcolumn = false
  wo.list = false
  wo.wrap = false
  wo.winhighlight = "Normal:TabLineFill,EndOfBuffer:TabLineFill,StatusLine:TabLineFill,StatusLineNC:TabLineFill"

  -- Keep focus on the terminal, not the header.
  if vim.api.nvim_win_is_valid(panel_win) then vim.api.nvim_set_current_win(panel_win) end

  M._attach_mouse_keymaps()

  local group = vim.api.nvim_create_augroup("EasyDotnetOverlaySync", { clear = true })

  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = group,
    callback = function()
      if not manager.panel_win or not vim.api.nvim_win_is_valid(manager.panel_win) then return end
      if not manager.tabline_win or not vim.api.nvim_win_is_valid(manager.tabline_win) then return end
      M.render()
    end,
  })

  -- The header is a real window, so it can be focused (e.g. <C-w>k). It is not
  -- interactive, so skip over it in the direction of travel: coming up from the
  -- terminal continue up to the window above; otherwise drop into the terminal
  -- where the panel keymaps (+, <Tab>, X, q, ...) live.
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      if not manager.tabline_win or not vim.api.nvim_win_is_valid(manager.tabline_win) then return end
      if vim.api.nvim_get_current_win() ~= manager.tabline_win then return end
      local from_terminal = vim.fn.win_getid(vim.fn.winnr("#")) == manager.panel_win
      vim.schedule(function()
        if not manager.tabline_win or not vim.api.nvim_win_is_valid(manager.tabline_win) then return end
        if vim.api.nvim_get_current_win() ~= manager.tabline_win then return end
        if from_terminal then
          vim.cmd("wincmd k")
          -- No window above the header: fall back to the terminal so we never trap focus here.
          if vim.api.nvim_get_current_win() ~= manager.tabline_win then return end
        end
        if manager.panel_win and vim.api.nvim_win_is_valid(manager.panel_win) then vim.api.nvim_set_current_win(manager.panel_win) end
      end)
    end,
  })

  M.render()
end

function M.destroy()
  M.stop_timer()
  pcall(vim.api.nvim_del_augroup_by_name, "EasyDotnetOverlaySync")
  pcall(vim.keymap.del, "n", "<LeftMouse>")
  pcall(vim.keymap.del, "n", "<2-LeftMouse>")
  pcall(vim.keymap.del, "n", "<MiddleMouse>")
  if manager.tabline_win and vim.api.nvim_win_is_valid(manager.tabline_win) then vim.api.nvim_win_close(manager.tabline_win, true) end
  manager.tabline_win = nil
end

return M
