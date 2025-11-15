---@class ProgressMessage
---@field stage string                 # e.g. "Discovering tests...", "Building project..."
---@field message string               # the actual log / status

---@alias ProgressCallback fun(msg: ProgressMessage)

local M = {
  callbacks = {},
}

---Generate a token and register a callback for progress messages
---@param cb ProgressCallback
---@return string, fun() unsubscribe
function M.generate_token(cb)
  local token = tostring(math.random(100000, 999999))
  M.callbacks[token] = cb
  local unsubscribe = function() M.callbacks[token] = nil end
  return token, unsubscribe
end

---Report progress messages to the registered callback(s)
---@param token string
---@param message ProgressMessage
function M.report(token, message)
  local cb = M.callbacks[token]
  if cb then cb(message) end
end

return M
