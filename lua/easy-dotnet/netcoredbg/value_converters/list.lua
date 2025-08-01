local M = {}

local index_to_number = function(r) return tonumber(r:match("%[(%d+)%]")) or 0 end

local function to_pretty_string(c)
  local max_elements = 5
  local max_chars = 50

  local all_unresolved = vim.iter(c):all(function(r) return r.variablesReference ~= 0 end)

  if all_unresolved and #c > 0 then return (string.format("[%d] - [%s...]", #c, c[1].value)) end

  local values = {}
  for i, r in ipairs(c) do
    if i > max_elements then break end
    local v = r.value
    if r.variablesReference == 0 then v = vim.inspect(v):gsub("\n", ""):gsub("%s+", " ") end
    table.insert(values, v)
  end

  local preview_str = "[" .. table.concat(values, ", ") .. "]"
  if #c > max_elements or #preview_str > max_chars then preview_str = preview_str:gsub("]$", ", ...]") end

  return (string.format("[%d] - %s", #values, preview_str))
end

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
  local var_ref = nil

  for _, entry in ipairs(vars) do
    if entry.name == "_size" and tonumber(entry.value) then
      ---@diagnostic disable-next-line: cast-local-type
      max_count = tonumber(entry.value)
    elseif entry.name == "_items" then
      var_ref = tonumber(entry.variablesReference)
    end
  end

  if var_ref then
    local result = {}
    local added = 0
    ---@param r Variable[]
    require("easy-dotnet.netcoredbg").fetch_variables(var_ref, 1, function(r)
      table.sort(r, function(a, b)
        local a_index = index_to_number(a.name)
        local b_index = index_to_number(b.name)
        return a_index < b_index
      end)

      for _, children_ref in ipairs(r) do
        if added >= max_count then break end
        table.insert(result, children_ref)
        added = added + 1
      end

      cb(result, to_pretty_string(result))
    end)
  end
end

M.is_list = function(class_name)
  class_name = vim.trim(class_name)
  if type(class_name) ~= "string" then return false end
  return class_name:match("^System%.Collections%.Generic%.List") ~= nil
end

return M
