local constants = require("easy-dotnet.constants")

---@type ValueConverter
return {
  satisfies_type = function(_, vars)
    return vim.iter(vars):any(function(r) return r.name == "HasBeenThrown" and r.value == "true" end)
  end,
  extract = function(_, vars, var_path, _, cb)
    local exception = {}

    for _, value in ipairs(vars) do
      value.var_path = var_path .. "." .. value.name
      if value.name == "_message" then
        exception["message"] = value
      elseif value.name == "_innerException" then
        exception["inner_exception"] = value
      elseif value.name == "_source" then
        exception["source"] = value
      elseif value.name == "_data" then
        exception["data"] = value
      elseif value.name == "StackTrace" then
        exception["stack_trace"] = value
      end
    end

    cb(exception, "󱐋 " .. (exception.message.value or "??"), constants.highlights.EasyDotnetDebuggerVirtualException)
  end,
}
