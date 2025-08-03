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
  vim.print("enumerable", vars)
  return {
    name = "enumerable",
    type = "easy_dotnet_enumerable_wrapper",
    value = "<enumeration needed>",
    variablesReference = 99,
  }
  -- local max_count = 0
  -- local var_ref = nil
  --
  -- for _, entry in ipairs(vars) do
  --   if entry.name == "_size" and tonumber(entry.value) then
  --     ---@diagnostic disable-next-line: cast-local-type
  --     max_count = tonumber(entry.value)
  --   elseif entry.name == "_items" then
  --     var_ref = tonumber(entry.variablesReference)
  --   end
  -- end
  --
  -- if var_ref then
  --   local result = {}
  --   local added = 0
  --   ---@param r Variable[]
  --   require("easy-dotnet.netcoredbg").fetch_variables(var_ref, 0, function(r)
  --     table.sort(r, function(a, b)
  --       local a_index = index_to_number(a.name)
  --       local b_index = index_to_number(b.name)
  --       return a_index < b_index
  --     end)
  --
  --     for _, children_ref in ipairs(r) do
  --       if added >= max_count then break end
  --       table.insert(result, children_ref)
  --       added = added + 1
  --     end
  --
  --     cb(result, require("easy-dotnet.netcoredbg.pretty_printers.list").pretty_print(result))
  --   end)
  -- end
end

M.is_enumerable = function(class_name)
  class_name = vim.trim(class_name)
  if type(class_name) ~= "string" then return false end
  return class_name:match("^System%.Linq%.Enumerable%.ListWhereIterator") ~= nil
end

return M
