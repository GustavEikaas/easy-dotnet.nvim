local M = {}

local index_to_number = function(r) return tonumber(r:match("%[(%d+)%]")) or 0 end

---Converts a List-like DAP variable into a Lua array.
---
---Used with NetCoreDbg DAP variables representing .NET collections like `List<T>`.
---It expects the variable to contain:
---  - A child with `name == "_size"` and a numeric `value`
---  - A child with `name == "_items"` and a `.children` array of element entries
---
---Only the first `_size` elements are extracted from `_items.children`.
---
---@param vars table # The top-level DAP variable representing the list object
---@param cb function
function M.extract(vars, cb)
  local max_count = 0
  local keys_ref = nil
  local values_ref = nil

  for _, entry in ipairs(vars) do
    if entry.name == "_size" and tonumber(entry.value) then
      max_count = tonumber(entry.value) or 0
    elseif entry.name == "keys" then
      keys_ref = tonumber(entry.variablesReference)
    elseif entry.name == "values" then
      values_ref = tonumber(entry.variablesReference)
    end
  end

  if keys_ref and values_ref then
    local result = {}

    ---@param r Variable[]
    require("easy-dotnet.netcoredbg").fetch_variables(keys_ref, 0, function(r)
      table.sort(r, function(a, b)
        local a_index = index_to_number(a.name)
        local b_index = index_to_number(b.name)
        return a_index < b_index
      end)

      local s = vim.iter(r):slice(1, max_count):totable()

      for i, value in ipairs(s) do
        value.name = "Key"
        table.insert(result, {
          name = i,
          type = "easy_dotnet_kv_wrapper",
          variablesReference = 999999,
          value = "",
          children = {
            value,
          },
        })
      end

      require("easy-dotnet.netcoredbg").fetch_variables(values_ref, 0, function(values)
        table.sort(values, function(a, b)
          local a_index = index_to_number(a.name)
          local b_index = index_to_number(b.name)
          return a_index < b_index
        end)

        local sliced_values = vim.iter(values):slice(1, max_count):totable()
        for index, value in ipairs(sliced_values) do
          value.name = "Value"
          table.insert(result[index].children, value)
        end

        cb(result, require("easy-dotnet.netcoredbg.pretty_printers.kv-pair-list").pretty_print(result))
      end)
    end)
  end
end

M.is_sorted_list = function(class_name)
  class_name = vim.trim(class_name)
  if type(class_name) ~= "string" then return false end
  return class_name:match("^System%.Collections%.Generic%.SortedList") ~= nil
end

return M
