local M = {}

local index_to_number = function(r) return tonumber(r:match("%[(%d+)%]")) or 0 end

function M.is_hashset(class_name)
  class_name = vim.trim(class_name or "")
  return type(class_name) == "string" and class_name:match("^System%.Collections%.Generic%.HashSet") ~= nil
end

local function format_hashset(values)
  local max_items = 5
  local max_chars = 50
  local preview = {}
  local count = 0
  local unresolved_count, first_unresolved_value = 0, nil

  for _, item in ipairs(values) do
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

  local preview_str = "{" .. table.concat(preview, ", ") .. "}"
  if count > max_items or #preview_str > max_chars then preview_str = preview_str:gsub("}$", ", ...}") end

  return string.format("[%d] - %s", count, preview_str)
end

---@param vars table[] Fields from the HashSet<T> object
---@param cb fun(result: table[], preview: string)
M.extract = function(vars, cb)
  local entries = nil
  local count = 0

  for _, entry in ipairs(vars) do
    if entry.name == "_entries" then
      entries = tonumber(entry.variablesReference)
    elseif entry.name == "_count" then
      count = tonumber(entry.value) or 0
    end
  end

  if not entries or count == 0 then
    cb({}, "{}")
    return
  end

  require("easy-dotnet.netcoredbg").fetch_variables(entries, 2, function(slot_entries)
    table.sort(slot_entries, function(a, b) return index_to_number(a.name) < index_to_number(b.name) end)

    local result = vim
      .iter(slot_entries)
      :slice(1, count)
      :map(function(r)
        return vim.iter(r.children):find(function(child) return child.name == "Value" end)
      end)
      :totable()

    cb(result, format_hashset(result))
  end)
end

return M
