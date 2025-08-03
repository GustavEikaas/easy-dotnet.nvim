local M = {}

function M.is_tuple(className)
  className = vim.trim(className)
  if type(className) ~= "string" then return false end

  return className:match("^System%.Value?Tuple") ~= nil
end

function M.extract(var_path, vars, cb)
  local items = vim
    .iter(vars)
    :filter(function(v) return v.name:match("^Item%d+$") end)
    :map(function(item)
      return vim.tbl_extend("force", item, {
        var_path = var_path .. "." .. item.name,
      })
    end)
    :totable()

  cb(items, require("easy-dotnet.netcoredbg.pretty_printers.tuple").pretty_print(items))
end

return M
