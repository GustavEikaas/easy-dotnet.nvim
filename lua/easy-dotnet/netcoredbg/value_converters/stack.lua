local M = {}

local index_to_number = function(r) return tonumber(r:match("%[(%d+)%]")) or 0 end

--- Determines whether the class is a Stack<T>
function M.is_stack(class_name)
  class_name = vim.trim(class_name or "")
  return type(class_name) == "string" and class_name:match("^System%.Collections%.Generic%.Stack") ~= nil
end

--- Formats a stack preview
local function format_list(list)
  local max_items = 5
  local max_chars = 50
  local preview, count = {}, 0
  local unresolved_count, first_unresolved_value = 0, nil

  for _, item in ipairs(list) do
    count = count + 1
    if item.variablesReference ~= 0 then
      unresolved_count = unresolved_count + 1
      if not first_unresolved_value then first_unresolved_value = item.value end
    elseif #preview < max_items then
      local val = vim.inspect(item.value):gsub("\n", ""):gsub("%s+", " ")
      table.insert(preview, val)
    end
  end

  if unresolved_count == count and first_unresolved_value then return string.format("[%d] - [%s%s]", count, first_unresolved_value, count > 1 and "..." or "") end

  local preview_str = "(" .. table.concat(preview, ", ") .. ")"
  if count > max_items or #preview_str > max_chars then preview_str = preview_str:gsub("%)$", ", ...)") end

  return string.format("[%d] - %s", count, preview_str)
end

---@param vars table[] Fields from the Stack<T> object
---@param cb fun(result: table, preview: string)
M.extract = function(vars, cb)
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

  require("easy-dotnet.netcoredbg").fetch_variables(array_ref, 1, function(children)
    table.sort(children, function(a, b) return index_to_number(a.name) < index_to_number(b.name) end)

    local result = vim.iter(children):slice(1, size):totable()

    table.sort(result, function(a, b) return index_to_number(a.name) > index_to_number(b.name) end)

    cb(result, format_list(result))
  end)

  return {}
end

return M
