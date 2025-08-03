local M = {}

local index_to_number = function(r) return tonumber(r:match("%[(%d+)%]")) or 0 end

--- Determines whether the class is a Stack<T>
function M.is_stack(class_name)
  class_name = vim.trim(class_name or "")
  return type(class_name) == "string" and class_name:match("^System%.Collections%.Generic%.Stack") ~= nil
end

---@param vars table[] Fields from the Stack<T> object
---@param cb fun(result: table, preview: string)
M.extract = function(var_path, vars, cb)
  local array_ref = nil
  local size = 0

  for _, entry in ipairs(vars) do
    if entry.name == "_array" then
      array_ref = tonumber(entry.variablesReference)
    elseif entry.name == "_size" then
      size = tonumber(entry.value) or 0
    end
  end

  if not array_ref or size == 0 then
    cb({}, "[]")
    return
  end

  require("easy-dotnet.netcoredbg").fetch_variables(array_ref, 0, function(children)
    table.sort(children, function(a, b) return index_to_number(a.name) < index_to_number(b.name) end)

    local result = vim.iter(children):slice(1, size):totable()

    table.sort(result, function(a, b) return index_to_number(a.name) > index_to_number(b.name) end)

    for _, value in ipairs(result) do
      value.var_path = var_path .. "._array" .. value.name
    end

    cb(result, require("easy-dotnet.netcoredbg.pretty_printers.list").pretty_print(result))
  end)

  return {}
end

return M
