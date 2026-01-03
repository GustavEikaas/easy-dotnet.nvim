local M = {}

---@param vars easy-dotnet.Debugger.Variable[]
M.pretty_print = function(vars)
  local max_elements = 5
  local max_chars = 50

  local all_unresolved = vim.iter(vars):all(function(r) return r.variablesReference ~= 0 end)

  if all_unresolved and #vars > 0 then return (string.format("[%d] - [%s...]", #vars, vars[1].value)) end

  local values = {}
  for i, r in ipairs(vars) do
    if i > max_elements then break end
    local v = r.value
    if r.variablesReference == 0 then v = vim.inspect(v):gsub("\n", ""):gsub("%s+", " ") end
    table.insert(values, v)
  end

  local preview_str = "[" .. table.concat(values, ", ") .. "]"
  if #vars > max_elements or #preview_str > max_chars then preview_str = preview_str:gsub("]$", ", ...]") end

  return (string.format("[%d] - %s", #values, preview_str))
end
return M
