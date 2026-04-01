local Tab = require("easy-dotnet.terminal.tab")

---@class easy-dotnet.TerminalManager
---@field _tabs easy-dotnet.TerminalTab[]
---@field _tab_index table<string, easy-dotnet.TerminalTab>
---@field active_id string|nil
---@field panel_win integer|nil
---@field tabline_buf integer|nil
---@field tabline_win integer|nil
---@field header_buf integer|nil
---@field header_win integer|nil
---@field _user_counter integer
---@field _on_tab_activated fun(tab: easy-dotnet.TerminalTab)|nil

local M = {
  _tabs = {},
  _tab_index = {},
  active_id = nil,
  panel_win = nil,
  tabline_buf = nil,
  tabline_win = nil,
  header_buf = nil,
  header_win = nil,
  _user_counter = 0,
  _on_tab_activated = nil,
}

---Return a shallow copy of the ordered tab list.
---@return easy-dotnet.TerminalTab[]
function M.get_all()
  local out = {}
  for _, t in ipairs(M._tabs) do
    out[#out + 1] = t
  end
  return out
end

---Retrieve a tab by slot id.
---@param id string
---@return easy-dotnet.TerminalTab|nil
function M.get(id) return M._tab_index[id] end

---Get an existing tab or create a new one.
---@param id string
---@param label string
---@param owned_by "server"|"user"
---@return easy-dotnet.TerminalTab
function M.get_or_create(id, label, owned_by)
  local existing = M._tab_index[id]
  if existing then return existing end

  local tab = Tab.new(id, label, owned_by)
  M._tabs[#M._tabs + 1] = tab
  M._tab_index[id] = tab
  return tab
end

---Switch the panel to display the given tab.
---Swaps the buffer in panel_win, refreshes tabline + header.
---@param id string
function M.set_active(id)
  local tab = M._tab_index[id]
  if not tab then return end

  Tab.ensure_buf(tab)
  M.active_id = id

  if M.panel_win and vim.api.nvim_win_is_valid(M.panel_win) then
    pcall(vim.api.nvim_win_set_option, M.panel_win, "winfixbuf", false)
    vim.api.nvim_win_set_buf(M.panel_win, tab.buf)
    pcall(vim.api.nvim_win_set_option, M.panel_win, "winfixbuf", true)
    vim.api.nvim_win_call(M.panel_win, function() vim.cmd("normal! G") end)
  end

  if M._on_tab_activated then M._on_tab_activated(tab) end

  local ok_tl, tabline = pcall(require, "easy-dotnet.terminal.tabline")
  if ok_tl then tabline.render() end
  local ok_h, header = pcall(require, "easy-dotnet.terminal.header")
  if ok_h then header.render() end
end

---Remove a tab and free its buffer.
---If the removed tab was active, switch to an adjacent tab.
---@param id string
function M.remove(id)
  local tab = M._tab_index[id]
  if not tab then return end

  local pos = nil
  for i, t in ipairs(M._tabs) do
    if t.id == id then
      pos = i
      break
    end
  end

  local jid = Tab.job_id(tab)
  if jid then pcall(vim.fn.jobstop, jid) end

  table.remove(M._tabs, pos)
  M._tab_index[id] = nil

  if M.active_id == id then
    M.active_id = nil
    if #M._tabs > 0 then
      local prev_idx = pos > 1 and (pos - 1) or 1
      M.set_active(M._tabs[math.min(prev_idx, #M._tabs)].id)
    else
      local new_tab = M.new_user_terminal()
      M.set_active(new_tab.id)
    end
  else
    local ok_tl, tabline = pcall(require, "easy-dotnet.terminal.tabline")
    if ok_tl then tabline.render() end
  end

  if tab.buf and vim.api.nvim_buf_is_valid(tab.buf) then pcall(vim.api.nvim_buf_delete, tab.buf, { force = true }) end
end

---Create a new user-owned terminal running $SHELL.
---@return easy-dotnet.TerminalTab
function M.new_user_terminal()
  M._user_counter = M._user_counter + 1
  local id = "user:" .. M._user_counter
  local label = "Terminal " .. M._user_counter
  local tab = M.get_or_create(id, label, "user")
  Tab.ensure_buf(tab)

  local shell = vim.o.shell
  local job_id
  vim.api.nvim_buf_call(tab.buf, function()
    job_id = vim.fn.termopen({ shell }, {
      on_exit = function(_, exit_code, _)
        vim.schedule(function()
          tab.last_status = "finished"
          tab.last_exit_code = exit_code
          local ok_tl, tabline = pcall(require, "easy-dotnet.terminal.tabline")
          if ok_tl then tabline.render() end
          local ok_h, header = pcall(require, "easy-dotnet.terminal.header")
          if ok_h then header.render() end
        end)
      end,
    })
  end)

  if job_id and job_id > 0 then
    vim.b[tab.buf].terminal_job_id = job_id
    tab.last_status = "running"
    tab.exec_name = vim.fn.fnamemodify(shell, ":t")
    tab.full_args = ""
  end

  return tab
end

return M
