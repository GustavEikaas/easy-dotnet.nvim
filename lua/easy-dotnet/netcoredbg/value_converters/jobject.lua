local M = {}

---@param vars table # The top-level DAP variable representing the list object
---@param cb function
function M.extract(var_path, vars, cb)
  local var_ref = nil

  for _, property in ipairs(vars) do
    if property.name == "_properties" then var_ref = property.variablesReference end
  end

  if not var_ref then error("failed to get _properties from JObject") end
  local netcoredbg = require("easy-dotnet.netcoredbg")
  netcoredbg.fetch_variables(var_ref, 1, function(entries)
    for _, value in ipairs(entries) do
      if value.name == "_dictionary" then require("easy-dotnet.netcoredbg.value_converters.dictionaries").extract(var_path .. "._properties._dictionary", value.children, cb) end
    end
  end)
end

M.is_jobject = function(class_name)
  class_name = vim.trim(class_name)
  return class_name:match("^Newtonsoft%.Json%.Linq%.JObject$") ~= nil
end

return M
