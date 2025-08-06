---@type ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    if type(class_name) ~= "string" then return false end
    return class_name:match("^System%.Version$") ~= nil
  end,
  extract = function(frame_id, _, var_path, _, cb)
    local dap = require("dap")

    local eval_expression = var_path .. ".ToString()"

    dap.session():request("evaluate", { frameId = frame_id, expression = eval_expression, context = "hover" }, function(err, response)
      if err or not response or not response.variablesReference then error("No variable reference found for: " .. var_path) end
      local version = {
        value = {
          value = response.result,
          type = response.type,
          variablesReference = response.variablesReference,
        },
      }
      cb(version, response.result)
    end)
  end,
}
