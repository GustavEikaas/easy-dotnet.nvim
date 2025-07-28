local M = {}

---Extracts key-value pairs from a C# Dictionary
---
---Finds a `_count` entry to limit the number of extracted pairs.
---Returns a Lua table 
---If a value is missing, it will be represented as the string `"null"`.
---
---@param vars table[] A list of variable tables to extract from.
---@return table<string, string> Extracted key-value pairs.
M.extract = function(vars)
  local result = {}
  local max_count = 0

  -- Get max count from _count
  for _, entry in ipairs(vars) do
    if entry.name == "_count" and tonumber(entry.value) then
      ---@diagnostic disable-next-line: cast-local-type
      max_count = tonumber(entry.value)
    end
  end

  local added = 0
  for _, entry in ipairs(vars) do
    if entry.name ~= "_count" and entry.children and #entry.children > 0 then
      for _, mid_child in ipairs(entry.children) do
        if added >= max_count then break end
        if mid_child.children and #mid_child.children > 0 then
          local key, value = nil, nil
          for _, kv in ipairs(mid_child.children) do
            if kv.name == "key" or kv.name == "Key" then
              key = kv.value
            elseif kv.name == "value" or kv.name == "Value" then
              value = kv.value
            end
          end
          if key then
            result[key] = value ~= nil and value or "null"
            added = added + 1
          end
        end
      end
    end
  end

  return result
end

return M
