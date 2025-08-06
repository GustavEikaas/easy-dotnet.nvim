local M = {}

---@param vars table # The top-level DAP variable representing the list object
---@param cb function
function M.extract(var_path, vars, cb)
  local var_ref = nil

  for _, entry in ipairs(vars) do
    if entry.name == "_values" then var_ref = tonumber(entry.variablesReference) end
  end

  if var_ref then
    ---@param r Variable[]
    require("easy-dotnet.netcoredbg").fetch_variables(var_ref, 0, function(r) require("easy-dotnet.netcoredbg.value_converters.list").extract(var_path .. "._values", r, cb) end)
  end
end

M.is_jarray = function(class_name)
  class_name = vim.trim(class_name)
  return class_name:match("^Newtonsoft%.Json%.Linq%.JArray$") ~= nil
end

return M
