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
M.extract = function(var_path, vars, cb)
  local max_count = 0
  local var_ref = 0
  local is_complex_keys = false

  for _, entry in ipairs(vars) do
    if entry.name == "_count" and tonumber(entry.value) then
      max_count = tonumber(entry.value) or 0
    elseif entry.name == "_entries" then
      var_ref = tonumber(entry.variablesReference) or 0
    end
  end

  if var_ref == 0 then
    cb({}, "{}")
    return
  end

  local netcoredbg = require("easy-dotnet.netcoredbg")

  netcoredbg.fetch_variables(var_ref, 1, function(entries)
    local result = {}
    local added = 0

    for i, entry in ipairs(entries) do
      if added >= max_count then break end
      if entry.children then
        local key_var = nil
        local value_var = nil

        for _, child in ipairs(entry.children) do
          if child.name == "key" then
            key_var = vim.deepcopy(child)
            key_var.var_path = var_path .. "._entries" .. entry.name .. "." .. child.name
          elseif child.name == "value" or child.name == "Value" then
            value_var = vim.deepcopy(child)
            value_var.var_path = var_path .. "._entries" .. entry.name .. "." .. child.name
            value_var.name = "Value"
          end
        end

        if key_var then
          if key_var.variablesReference ~= 0 then
            is_complex_keys = true
            key_var.name = "Key"
            table.insert(result, {
              name = tostring(i),
              type = "easy_dotnet_kv_wrapper",
              value = "",
              variablesReference = 999999,
              children = {
                key_var,
                value_var,
              },
            })
          else
            key_var.name = key_var.value
            result[key_var.name] = value_var
          end
          added = added + 1
        end
      end
    end

    cb(
      result,
      is_complex_keys and require("easy-dotnet.netcoredbg.pretty_printers.kv-pair-list").pretty_print(result) or require("easy-dotnet.netcoredbg.pretty_printers.catch-all").pretty_print(result)
    )
  end)
end

return M
