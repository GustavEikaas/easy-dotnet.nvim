local M = {}

function M.is_dictionary(class_name)
  class_name = vim.trim(class_name)
  if type(class_name) ~= "string" then return false end
  return class_name:match("^System%.Collections%.Generic%.Dictionary") ~= nil
end

local function format_dict(dict)
  local max_items = 5
  local max_chars = 50

  local preview = {}
  local count = 0
  local unresolved_count = 0
  local first_unresolved_value = nil

  for key, item in pairs(dict) do
    count = count + 1

    if item.variablesReference ~= 0 then
      unresolved_count = unresolved_count + 1
      if not first_unresolved_value then first_unresolved_value = item.value end
    elseif #preview < max_items then
      local val = vim.inspect(item.value):gsub("\n", ""):gsub("%s+", " ")
      table.insert(preview, string.format("%s = %s", key, val))
    end
  end

  if unresolved_count == count and first_unresolved_value then return string.format("[%d] - [%s%s]", count, first_unresolved_value, count > 1 and "..." or "") end

  local preview_str = "[" .. table.concat(preview, ", ") .. "]"
  if count > max_items or #preview_str > max_chars then preview_str = preview_str:gsub("]$", ", ...]") end

  return string.format("[%d] - %s", count, preview_str)
end

---Extracts key-value pairs from a C# Dictionary
---
---Finds a `_count` entry to limit the number of extracted pairs.
---Returns a Lua table
---If a value is missing, it will be represented as the string `"null"`.
---
---@param vars table[] A list of variable tables to extract from.
---@return table<string, Variable> Extracted key-value pairs.
M.extract = function(vars, cb)
  local max_count = 0
  local var_ref = nil

  for _, entry in ipairs(vars) do
    if entry.name == "_count" and tonumber(entry.value) then
      ---@diagnostic disable-next-line: cast-local-type
      max_count = tonumber(entry.value)
    elseif entry.name == "_entries" then
      var_ref = tonumber(entry.variablesReference)
    end
  end

  if var_ref then
    local result = {}
    local added = 0
    ---@param r Variable[]
    require("easy-dotnet.netcoredbg").fetch_variables(var_ref, 1, function(r)
      for _, children_ref in ipairs(r) do
        if added > max_count then break end
        if children_ref.children then
          local key, value = nil, nil
          for _, kv in ipairs(children_ref.children) do
            if kv.name == "key" then
              key = kv.value
            elseif kv.name == "value" or kv.name == "Value" then
              value = kv
            end

            if key then
              result[key] = value ~= nil and value or "null"
              added = added + 1
            end
          end
        end
      end

      cb(result, format_dict(result))
    end)
  end
  return {}
end

return M
