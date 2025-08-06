local M = {}

---@param vars table # The top-level DAP variable representing the list object
---@param cb function
function M.extract(frame_id, var_path, vars, cb)
  local var = nil
  for _, property in ipairs(vars) do
    if property.name == "Value" then var = property end
  end
  if not var then error("failed to unwrap " .. var_path .. ".Value") end
  if var and var.variablesReference ~= 0 then
    require("easy-dotnet.netcoredbg").resolve_by_vars_reference(frame_id, var.variablesReference, var_path .. ".Value", var.type, function(value) cb(value.value, "") end)
  else
    cb({ var }, var.value)
  end
end

M.is_jproperty = function(class_name)
  class_name = vim.trim(class_name)
  return class_name:match("^Newtonsoft%.Json%.Linq%.JProperty$") ~= nil
end

return M
