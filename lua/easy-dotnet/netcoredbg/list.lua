local M = {}

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
---@return string[] # A Lua array of the list elements (as strings)
function M.extract(vars)
  local size = 0
  local sliced = {}

  for _, entry in ipairs(vars) do
    if entry.name == "_size" and tonumber(entry.value) then
      ---@diagnostic disable-next-line: cast-local-type
      size = tonumber(entry.value)
    elseif entry.name == "_items" and entry.children then
      for i = 1, size do
        local child = entry.children[i]
        if child then table.insert(sliced, child.value) end
      end
    end
  end

  return sliced
end

M.is_list = function(class_name)
  class_name = vim.trim(class_name)
  if type(class_name) ~= "string" then return false end
  return class_name:match("^System%.Collections%.Generic%.List") ~= nil
end

return M
