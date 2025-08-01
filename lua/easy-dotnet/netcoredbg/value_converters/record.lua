local M = {}

function M.is_record(vars)
  for _, entry in ipairs(vars) do
    if entry.value == "{System.RuntimeType}" and entry.children then
      for _, value in ipairs(entry.children) do
        if value.name == "IsClass" then return value.value == "true" end
      end
    end
  end
  return false
end

local banned_types = {
  "EqualityContract",
}

M.extract = function(vars)
  local result = {}

  for _, entry in ipairs(vars) do
    if not vim.tbl_contains(banned_types, entry.name) then result[entry.name] = entry.value end
  end

  return result
end

return M
