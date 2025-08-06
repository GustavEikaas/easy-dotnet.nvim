---@class ValueConverter
---@field extract fun(stack_frame_id: integer, vars: Variable[], var_path: string, var_type: string, cb: fun(result: table, pretty_string: string, highlight?: string))
---@field satisfies_type fun(var_type: string, vars: Variable[]): boolean

local M = {}

---@type ValueConverter[]
M.value_converters = {
  require("easy-dotnet.netcoredbg.value_converters.exception"),
  require("easy-dotnet.netcoredbg.value_converters.enum"),
  require("easy-dotnet.netcoredbg.value_converters.date"),
  require("easy-dotnet.netcoredbg.value_converters.version"),
  require("easy-dotnet.netcoredbg.value_converters.jobject"),
  require("easy-dotnet.netcoredbg.value_converters.jarray"),
  require("easy-dotnet.netcoredbg.value_converters.jvalue"),
  require("easy-dotnet.netcoredbg.value_converters.jproperty"),
  require("easy-dotnet.netcoredbg.value_converters.guid"),
  require("easy-dotnet.netcoredbg.value_converters.list"),
  require("easy-dotnet.netcoredbg.value_converters.sorted_list"),
  require("easy-dotnet.netcoredbg.value_converters.immutable_list"),
  require("easy-dotnet.netcoredbg.value_converters.readonly_list"),
  require("easy-dotnet.netcoredbg.value_converters.tuple"),
  require("easy-dotnet.netcoredbg.value_converters.hashset"),
  require("easy-dotnet.netcoredbg.value_converters.queue"),
  require("easy-dotnet.netcoredbg.value_converters.stack"),
  require("easy-dotnet.netcoredbg.value_converters.dictionaries"),
  require("easy-dotnet.netcoredbg.value_converters.readonly_dictionary"),
  require("easy-dotnet.netcoredbg.value_converters.concurrent_dictionary"),
  require("easy-dotnet.netcoredbg.value_converters.json_object"),
  require("easy-dotnet.netcoredbg.value_converters.json_element"),
  require("easy-dotnet.netcoredbg.value_converters.json_value_of_element"),
  require("easy-dotnet.netcoredbg.value_converters.json_array"),
}

function M.simple_unwrap(unwrap_key, frame_id, vars, var_path, cb)
  local var = nil
  for _, property in ipairs(vars) do
    if property.name == unwrap_key then var = property end
  end
  if not var then error("Failed to unwrap " .. var_path .. "." .. unwrap_key) end
  if var and var.variablesReference ~= 0 then
    require("easy-dotnet.netcoredbg").resolve_by_vars_reference(frame_id, var.variablesReference, var_path .. "." .. unwrap_key, var.type, function(value) cb(value.value, value.formatted_value) end)
  else
    cb({ var }, var.value)
  end
end

---Converts a list of DAP variables into a Lua table.
---Numeric-looking keys like [0], [1] go into array part.
---Named keys go into map part.
---
---@param vars table[] # List of DAP variable tables with .name and .value
function M.vars_to_table(var_path, vars, cb)
  local result = {}

  for _, c in ipairs(vars) do
    local index = c.name:match("^%[(%d+)%]$")
    if index then
      c.var_path = var_path .. c.name
      table.insert(result, c)
    else
      c.var_path = var_path .. "." .. c.name
      result[c.name] = c
    end
  end
  cb(result, require("easy-dotnet.netcoredbg.pretty_printers.catch-all").pretty_print(result))
end

---Resolves any C# type and invokes the given callback with the lua result
---@param stack_frame_id integer
---@param vars Variable[]
---@param var_path string
---@param var_type string
---@param cb fun(result: table, pretty_string: string, highlight?: string)
M.extract = function(stack_frame_id, vars, var_path, var_type, cb)
  ---@param r ValueConverter
  ---@type ValueConverter[]
  local matches = vim.iter(M.value_converters):filter(function(r) return r.satisfies_type(var_type, vars) end):totable()

  if #matches > 1 then
    error("More than one value converter found for type " .. var_type)
  elseif #matches == 1 then
    matches[1].extract(stack_frame_id, vars, var_path, var_type, cb)
  else
    M.vars_to_table(var_path, vars, cb)
  end
end

return M
