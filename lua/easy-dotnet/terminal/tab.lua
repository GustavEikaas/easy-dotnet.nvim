---@class easy-dotnet.TerminalTab
---@field id string              -- slot id, e.g. "default", "run:MyProject", "user:1"
---@field label string           -- display name for tabline
---@field buf integer|nil        -- neovim buffer handle (filetype=terminal set automatically)
---@field owned_by "server"|"user"
---@field last_status "running"|"finished"|nil
---@field last_exit_code integer|nil
---@field exec_name string|nil   -- command executable basename
---@field full_args string|nil   -- joined command arguments

local M = {}

---Create a new TerminalTab (no buffer allocated yet).
---@param id string
---@param label string
---@param owned_by "server"|"user"
---@return easy-dotnet.TerminalTab
function M.new(id, label, owned_by)
  return {
    id = id,
    label = label,
    buf = nil,
    owned_by = owned_by,
    last_status = nil,
    last_exit_code = nil,
    exec_name = nil,
    full_args = nil,
  }
end

---Ensure the tab has a valid, hidden terminal buffer.
---Neovim sets filetype=terminal automatically when term=true is used in jobstart.
---@param tab easy-dotnet.TerminalTab
function M.ensure_buf(tab)
  if tab.buf and vim.api.nvim_buf_is_valid(tab.buf) then return end
  tab.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[tab.buf].bufhidden = "hide"
  vim.bo[tab.buf].buflisted = false
end

---Return the Neovim job id stored in the buffer variable, or nil.
---@param tab easy-dotnet.TerminalTab
---@return integer|nil
function M.job_id(tab)
  if not tab.buf or not vim.api.nvim_buf_is_valid(tab.buf) then return nil end
  local ok, id = pcall(vim.api.nvim_buf_get_var, tab.buf, "terminal_job_id")
  return ok and id or nil
end

---Poll whether the job is currently running using jobwait.
---@param tab easy-dotnet.TerminalTab
---@return boolean
function M.is_running(tab)
  local id = M.job_id(tab)
  if not id then return false end
  return vim.fn.jobwait({ id }, 0)[1] == -1
end

return M
