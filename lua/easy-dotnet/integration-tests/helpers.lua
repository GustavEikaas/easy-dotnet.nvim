local M = {}

---@class WaitOptions
---@field timeout integer Timeout in milliseconds
---@field interval integer Interval between checks in milliseconds

---Waits until a predicate returns true or a timeout occurs.
---
---This function must be called inside a coroutine. It yields and resumes based on interval checks.
---
---Can be used for polling state, like waiting for a filetype to appear or a buffer to load.
---
---```lua
---coroutine.wrap(function()
---  local ok = M.wait_interval(function()
---    return vim.bo.filetype == "TelescopePrompt"
---  end, { timeout = 3000, interval = 100 })
---  if ok then
---    print("Telescope is active!")
---  else
---    print("Timeout waiting for Telescope.")
---  end
---end)()
---```
---
---@async
---@param predicate function|boolean A function returning boolean, or a boolean value directly
---@param opts WaitOptions
---@return boolean success True if the predicate became true within the timeout
function M.wait_interval(predicate, opts)
  assert(type(predicate) == "function" or type(predicate) == "boolean", "predicate must be a function or boolean")
  assert(type(opts) == "table", "opts must be a table")
  assert(type(opts.timeout) == "number", "opts.timeout must be a number")
  assert(type(opts.interval) == "number", "opts.interval must be a number")

  local timeout = opts.timeout
  local interval = opts.interval
  local time = 0
  local co = coroutine.running()
  assert(co, "M.wait_interval must be called within a coroutine")

  local function loop()
    if type(predicate) == "function" and predicate() or predicate then
      return true
    else
      vim.defer_fn(function() coroutine.resume(co) end, interval)
    end
    coroutine.yield()
  end

  while time < timeout do
    local res = loop()
    if res == true then return true end
    time = time + interval
  end
  return false
end

return M
