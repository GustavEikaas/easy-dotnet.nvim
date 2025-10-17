local M = {}

---@param params table|nil The parameters to validate
---@param rules table<string, string|string[]> Map of key -> allowed type(s)
---@return boolean, string? true if valid, false + error message otherwise
function M.validate_params(params, rules)
  if type(params) ~= "table" then return false, "Params must be a table" end

  for key, allowed_types in pairs(rules) do
    local value = params[key]

    if value == nil then return false, ("Missing required parameter: '%s'"):format(key) end

    -- Convert single string to table for uniform processing
    if type(allowed_types) == "string" then allowed_types = { allowed_types } end

    local value_type = type(value)
    local match = false
    for _, t in ipairs(allowed_types) do
      if value_type == t then
        match = true
        break
      end
    end

    if not match then
      local expected = table.concat(allowed_types, "/")
      return false, ("Parameter '%s' must be of type %s, got %s"):format(key, expected, value_type)
    end
  end

  return true
end

return M
