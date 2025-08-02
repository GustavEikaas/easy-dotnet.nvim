local M = {}

function M.is_tuple(className)
  className = vim.trim(className)
  if type(className) ~= "string" then return false end

  return className:match("^System%.Value?Tuple") ~= nil
end

function M.extract(vars, cb)
  local items = vim.tbl_filter(function(v) return v.name:match("^Item%d+$") end, vars)

  cb(items, require("easy-dotnet.netcoredbg.pretty_printers.tuple").pretty_print(items))
end

return M
