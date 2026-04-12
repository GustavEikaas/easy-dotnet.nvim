local M = {}

---@type table<string, function[]>
local listeners = {}

---@param event string
---@param cb function
---@return function unsubscribe
function M.subscribe(event, cb)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], cb)
  return function()
    listeners[event] = vim.tbl_filter(function(f) return f ~= cb end, listeners[event] or {})
  end
end

---@param event string
function M.emit(event, ...)
  for _, cb in ipairs(listeners[event] or {}) do
    cb(...)
  end
end

return M
