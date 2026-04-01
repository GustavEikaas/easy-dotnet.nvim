local spinner_frames = require("easy-dotnet.ui-modules.jobs").spinner_frames
local Tab = require("easy-dotnet.terminal.tab")
local manager = require("easy-dotnet.terminal.manager")

local ns_id = vim.api.nvim_create_namespace("EasyDotnetHeader")
local spinner_idx = 1

local M = {}

function M.render()
  local panel_win = manager.panel_win
  if not panel_win or not vim.api.nvim_win_is_valid(panel_win) then
    M.destroy()
    return
  end
  if not manager.header_buf or not vim.api.nvim_win_is_valid(manager.header_win) then return end

  local tab = manager.active_id and manager.get(manager.active_id)
  if not tab then return end

  local curr_width = vim.api.nvim_win_get_width(panel_win)
  if vim.api.nvim_win_get_width(manager.header_win) ~= curr_width then
    vim.api.nvim_win_set_config(manager.header_win, {
      width = curr_width,
      relative = "win",
      win = panel_win,
      row = 1,
      col = 0,
    })
  end

  local icon, icon_hl
  local running = tab.owned_by == "server" and Tab.is_running(tab)
  if running then
    icon = spinner_frames[spinner_idx]
    spinner_idx = (spinner_idx % #spinner_frames) + 1
    icon_hl = "DiagnosticInfo"
  elseif tab.last_status == "finished" then
    if tab.last_exit_code == 0 then
      icon = "✓"
      icon_hl = "String"
    else
      icon = ""
      icon_hl = "ErrorMsg"
    end
  else
    icon = "●"
    icon_hl = "Comment"
  end

  local exec_name = tab.exec_name or ""
  local full_args = tab.full_args or ""
  local max_len = math.floor(curr_width * 0.7)
  local display_args = full_args
  if #display_args > max_len then display_args = display_args:sub(1, max_len) .. "..." end

  local padding_left = 1
  local content_string = string.format("%s %s %s", icon, exec_name, display_args)
  local final_line = string.rep(" ", padding_left) .. content_string

  vim.api.nvim_buf_set_option(manager.header_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(manager.header_buf, 0, -1, false, { final_line })
  vim.api.nvim_buf_clear_namespace(manager.header_buf, ns_id, 0, -1)

  local start_icon = padding_left
  local end_icon = start_icon + #icon
  local start_exec = end_icon + 1
  local end_exec = start_exec + #exec_name
  local start_args = end_exec + 1
  local end_args = start_args + #display_args

  vim.api.nvim_buf_add_highlight(manager.header_buf, ns_id, icon_hl, 0, start_icon, end_icon)
  vim.api.nvim_buf_add_highlight(manager.header_buf, ns_id, "Title", 0, start_exec, end_exec)
  vim.api.nvim_buf_add_highlight(manager.header_buf, ns_id, "Comment", 0, start_args, end_args)
  vim.api.nvim_buf_set_option(manager.header_buf, "modifiable", false)
end

function M.create(panel_win)
  if manager.header_win and vim.api.nvim_win_is_valid(manager.header_win) then vim.api.nvim_win_close(manager.header_win, true) end

  if not manager.header_buf or not vim.api.nvim_buf_is_valid(manager.header_buf) then
    manager.header_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(manager.header_buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(manager.header_buf, "modifiable", false)
  end

  manager.header_win = vim.api.nvim_open_win(manager.header_buf, false, {
    relative = "win",
    win = panel_win,
    row = 1,
    col = 0,
    width = vim.api.nvim_win_get_width(panel_win),
    height = 1,
    style = "minimal",
    focusable = false,
    zindex = 100,
  })
  vim.api.nvim_win_set_option(manager.header_win, "winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder")
  M.render()
end

function M.destroy()
  if manager.header_win and vim.api.nvim_win_is_valid(manager.header_win) then vim.api.nvim_win_close(manager.header_win, true) end
  manager.header_win = nil
end

return M
