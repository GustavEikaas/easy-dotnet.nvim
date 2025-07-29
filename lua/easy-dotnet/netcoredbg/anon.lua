local M = {}

function M.is_anon(class_name)
  class_name = vim.trim(class_name)
  if type(class_name) ~= "string" then return false end
  return class_name:match("^<>f__AnonymousType0") ~= nil
end

M.extract = function(vars)
  local result = {}

  for _, entry in ipairs(vars) do
    result[entry.name] = entry.value
  end

  return result
end

return M
