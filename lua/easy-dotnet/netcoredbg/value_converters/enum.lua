---@type ValueConverter
return {
  satisfies_type = function(_, vars)
    if #vars < 2 then return false end
    local is_value__ = false
    local is_static_members = false
    for _, value in ipairs(vars) do
      if value.name == "value__" then
        is_value__ = true
      elseif value.name == "Static members" then
        is_static_members = true
      end
    end
    return is_value__ and is_static_members
  end,
  extract = function(frame_id, vars, var_path, _, cb)
    local value = nil

    for _, entry in ipairs(vars) do
      if entry.name == "value__" then value = entry end
    end

    if not value then error("Failed to extract value__ from " .. var_path) end

    local dap = require("dap")

    local eval_expression = var_path .. ".ToString()"

    dap.session():request("evaluate", { frameId = frame_id, expression = eval_expression, context = "hover" }, function(err, response)
      if err or not response or not response.variablesReference then error("No variable reference found for: " .. var_path) end
      local enum = {
        ["name"] = {
          value = response.result,
          type = response.type,
          variablesReference = response.variablesReference,
        },
        ["value"] = value,
      }
      cb(enum, string.format("%s = %d", response.result, value.value))
    end)
  end,
}
