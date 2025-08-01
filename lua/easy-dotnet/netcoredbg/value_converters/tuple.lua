local M = {}

function M.extract(vars)
  local items = vim.tbl_filter(function(v) return v.name:match("^Item%d+$") end, vars)

  local values = vim.tbl_map(function(v) return v.value end, items)
  return values
end

function M.is_tuple(className)
  className = vim.trim(className)
  if type(className) ~= "string" then return false end

  return className:match("^System%.Value?Tuple") ~= nil
end

return M
