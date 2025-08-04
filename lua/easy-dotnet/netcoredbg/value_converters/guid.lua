local M = {}

M.is_guid = function(class_name)
  class_name = vim.trim(class_name)
  if type(class_name) ~= "string" then return false end
  return class_name:match("^System%.Guid") ~= nil
end

function M.extract(frame_id, var_path, cb)
  local dap = require("dap")

  local eval_expression = var_path .. ".ToString()"

  dap.session():request("evaluate", { frameId = frame_id, expression = eval_expression, context = "hover" }, function(err, response)
    if err or not response or not response.variablesReference then error("No variable reference found for: " .. var_path) end
    local guid = {
      value = {
        value = response.result,
        type = response.type,
        variablesReference = response.variablesReference,
      },
    }
    cb(guid, response.result)
  end)
end

return M
