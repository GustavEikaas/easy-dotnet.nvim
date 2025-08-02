local M = {}

function M.is_exception(vars)
  return vim.iter(vars):any(function(r) return r.name == "HasBeenThrown" and r.value == "true" end)
end

function M.extract(vars, cb)
  local exception = {}

  for _, value in ipairs(vars) do
    if value.name == "_message" then
      exception["message"] = value
    elseif value.name == "_innerException" then
      exception["inner_exception"] = value
    elseif value.name == "_source" then
      exception["source"] = value
    elseif value.name == "_data" then
      exception["data"] = value
    elseif value.name == "StackTrace" then
      exception["stack_trace"] = value
    end
  end

  cb(exception, exception.message.value or "??")
end

return M
