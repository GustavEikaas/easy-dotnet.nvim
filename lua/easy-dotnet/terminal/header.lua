local spinner_frames = require("easy-dotnet.ui-modules.jobs").spinner_frames

local function get_state() return require("easy-dotnet.terminal").state end

local spinner_idx = 1

local function cleanup_header()
  local state = get_state()
  if state.timer then
    state.timer:stop()
    if not state.timer:is_closing() then state.timer:close() end
    state.timer = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then pcall(vim.api.nvim_set_option_value, "winbar", "", { win = state.win }) end
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

  local curr_width = vim.api.nvim_win_get_width(state.win)

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

  local winbar = string.format(" %%#%s#%s%%* %%#Title#%s%%* %%#Comment#%s%%*", icon_hl, icon, exec_name, display_args)

  pcall(vim.api.nvim_set_option_value, "winbar", winbar, { win = state.win })
end

local function create_header_win()
  local state = get_state()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  pcall(vim.api.nvim_set_option_value, "winbar", " ", { win = state.win })
end

return {
  update_header = update_header,
  create_header_win = create_header_win,
  cleanup_header = cleanup_header,
}
