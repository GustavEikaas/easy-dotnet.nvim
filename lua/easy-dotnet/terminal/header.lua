local spinner_frames = require("easy-dotnet.ui-modules.jobs").spinner_frames

local function get_state() return require("easy-dotnet.terminal").state end

local ns_id = vim.api.nvim_create_namespace("EasyDotnetHeader")
local spinner_idx = 1

local function cleanup_header()
  local state = get_state()
  if state.timer then
    state.timer:stop()
    if not state.timer:is_closing() then state.timer:close() end
    state.timer = nil
  end
  if state.header_win and vim.api.nvim_win_is_valid(state.header_win) then vim.api.nvim_win_close(state.header_win, true) end
  state.header_win = nil
  state.header_buf = nil
end

---@param status string "running"|"finished"
---@param exit_code integer|nil
local function update_header(status, exit_code)
  local state = get_state()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    cleanup_header()
    return
  end
  if not state.header_buf or not vim.api.nvim_win_is_valid(state.header_win) then return end

  local curr_width = vim.api.nvim_win_get_width(state.win)
  if vim.api.nvim_win_get_width(state.header_win) ~= curr_width then
    vim.api.nvim_win_set_config(state.header_win, {
      width = curr_width,
      relative = "win",
      win = state.win,
      row = 0,
      col = 0,
    })
  end

  local icon, icon_hl
  if status == "running" then
    icon = spinner_frames[spinner_idx]
    spinner_idx = (spinner_idx % #spinner_frames) + 1
    icon_hl = "DiagnosticInfo"
  elseif status == "finished" then
    if exit_code == 0 then
      icon = "✓"
      icon_hl = "String"
    else
      icon = ""
      icon_hl = "ErrorMsg"
    end
  else
    icon = ""
    icon_hl = "DiagnosticInfo"
  end

  local exec_name = state.exec_name or ""
  local full_args = state.full_args or ""
  local max_len = math.floor(curr_width * 0.7)
  local display_args = full_args
  if #display_args > max_len then display_args = display_args:sub(1, max_len) .. "..." end

  local padding_left = 1
  local content_string = string.format("%s %s %s", icon, exec_name, display_args)
  local final_line = string.rep(" ", padding_left) .. content_string

  vim.api.nvim_buf_set_lines(state.header_buf, 0, -1, false, { final_line })
  vim.api.nvim_buf_clear_namespace(state.header_buf, ns_id, 0, -1)

  local start_icon = padding_left
  local end_icon = start_icon + #icon
  local start_exec = end_icon + 1
  local end_exec = start_exec + #exec_name
  local start_args = end_exec + 1
  local end_args = start_args + #display_args

  vim.api.nvim_buf_add_highlight(state.header_buf, ns_id, icon_hl, 0, start_icon, end_icon)
  vim.api.nvim_buf_add_highlight(state.header_buf, ns_id, "Title", 0, start_exec, end_exec)
  vim.api.nvim_buf_add_highlight(state.header_buf, ns_id, "Comment", 0, start_args, end_args)
end

local function create_header_win()
  local state = get_state()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  if state.header_win and vim.api.nvim_win_is_valid(state.header_win) then vim.api.nvim_win_close(state.header_win, true) end

  state.header_buf = vim.api.nvim_create_buf(false, true)
  state.header_win = vim.api.nvim_open_win(state.header_buf, false, {
    relative = "win",
    win = state.win,
    row = 0,
    col = 0,
    width = vim.api.nvim_win_get_width(state.win),
    height = 1,
    style = "minimal",
    focusable = false,
    zindex = 100,
  })
  vim.api.nvim_win_set_option(state.header_win, "winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder")
end

return {
  update_header = update_header,
  create_header_win = create_header_win,
  cleanup_header = cleanup_header,
}
