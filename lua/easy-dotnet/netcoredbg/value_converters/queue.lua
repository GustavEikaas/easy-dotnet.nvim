local M = {}

local index_to_number = function(r) return tonumber(r:match("%[(%d+)%]")) or 0 end

function M.is_queue(class_name)
  class_name = vim.trim(class_name or "")
  return type(class_name) == "string" and class_name:match("^System%.Collections%.Generic%.Queue") ~= nil
end

---@param vars table[] Fields from the Queue<T> object
---@param cb fun(result: table, preview: string)
M.extract = function(var_path, vars, cb)
  local array_ref = nil
  local size = nil

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

  local result = {}
  local added = 0
  require("easy-dotnet.netcoredbg").fetch_variables(array_ref, 0, function(children)
    table.sort(children, function(a, b)
      local a_index = index_to_number(a.name)
      local b_index = index_to_number(b.name)
      return a_index < b_index
    end)

    for _, children_ref in ipairs(children) do
      if added >= size then break end
      children_ref.var_path = var_path .. "._array" .. children_ref.name
      table.insert(result, children_ref)
      added = added + 1
    end

    cb(result, require("easy-dotnet.netcoredbg.pretty_printers.list").pretty_print(result))
  end)

  return {}
end

return M
