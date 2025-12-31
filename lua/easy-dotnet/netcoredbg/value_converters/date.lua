---@type easy-dotnet.Debugger.ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    if type(class_name) ~= "string" then return false end
    return class_name:match("^System%.DateOnly$") ~= nil
      or class_name:match("^System%.DateTime$") ~= nil
      or class_name:match("^System%.DateTimeOffset$") ~= nil
      or class_name:match("^System%.TimeOnly$") ~= nil
      or class_name:match("^System%.TimeSpan$") ~= nil
  end,
  extract = function(frame_id, vars, var_path, _, cb)
    local dap = require("dap")

    local eval_expression = var_path .. ".ToString()"

    dap.session():request("evaluate", { frameId = frame_id, expression = eval_expression, context = "hover" }, function(err, response)
      if err or not response or not response.variablesReference then error("No variable reference found for: " .. var_path) end

      require("easy-dotnet.netcoredbg.value_converters").vars_to_table(var_path, vars, function(val)
        val["result"] = {
          value = response.result,
          type = response.type,
          variablesReference = response.variablesReference,
        }
        cb(val, response.result)
      end)
    end)
  end,
}
