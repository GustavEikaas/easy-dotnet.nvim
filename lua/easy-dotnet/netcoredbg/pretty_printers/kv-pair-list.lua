local M = {}

---@param vars Variable[]
M.pretty_print = function(vars)
  local max_items = 5
  local max_chars = 50

  local preview = {}
  local count = 0
  local unresolved_count = 0
  local first_unresolved = nil

  for _, pair in ipairs(vars) do
    count = count + 1

    local key = nil
    local val = nil

    for _, item in ipairs(pair.children or {}) do
      if item.name == "Key" then key = item end
      if item.name == "Value" then val = item end
    end

    if not key or not val then
      unresolved_count = unresolved_count + 1
      if not first_unresolved then first_unresolved = val and val.value or "?" end
    elseif key.variablesReference ~= 0 or val.variablesReference ~= 0 then
      unresolved_count = unresolved_count + 1
      if not first_unresolved then first_unresolved = val.value end
    elseif #preview < max_items then
      local k = vim.inspect(key.value):gsub("\n", ""):gsub("%s+", " ")
      local v = vim.inspect(val.value):gsub("\n", ""):gsub("%s+", " ")
      table.insert(preview, string.format("%s = %s", k, v))
    end
  end

  if unresolved_count == count and first_unresolved then return string.format("[%d] - [%s%s]", count, first_unresolved, count > 1 and "..." or "") end

  local preview_str = "[" .. table.concat(preview, ", ") .. "]"
  if count > max_items or #preview_str > max_chars then preview_str = preview_str:gsub("]$", ", ...]") end

  return string.format("[%d] - %s", count, preview_str)
end

return M
