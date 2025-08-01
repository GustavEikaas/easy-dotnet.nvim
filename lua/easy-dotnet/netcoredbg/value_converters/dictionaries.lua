local M = {}

function M.is_dictionary(class_name)
  class_name = vim.trim(class_name)
  if type(class_name) ~= "string" then return false end
  return class_name:match("^System%.Collections%.Generic%.Dictionary") ~= nil
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

      cb(result)
    end)
  end
  return {}
end

return M
