local tuple = require("easy-dotnet.netcoredbg.tuple")
local list = require("easy-dotnet.netcoredbg.list")
local dict = require("easy-dotnet.netcoredbg.dictionaries")
local anon = require("easy-dotnet.netcoredbg.anon")
local record = require("easy-dotnet.netcoredbg.record")

local M = {
  ---@type table<number, table<string, string | "pending">>
  pretty_cache = {},
}

local function fetch_variables(variables_reference, depth, callback)
  local dap = require("dap")
  local session = dap.session()
  if not session then
    callback({})
    return
  end

  session:request("variables", { variablesReference = variables_reference }, function(err, response)
    if err or not response or not response.variables then
      callback({})
      return
    end

    local result = {}
    local pending = #response.variables

    if pending == 0 then
      callback(result)
      return
    end

    for _, var in ipairs(response.variables) do
      local entry = {
        name = var.name,
        value = var.value,
        type = var.type,
        variablesReference = var.variablesReference,
        children = nil,
      }

      if var.variablesReference ~= 0 and depth > 0 then
        fetch_variables(var.variablesReference, depth - 1, function(child_vars)
          entry.children = child_vars
          pending = pending - 1
          if pending == 0 then
            table.insert(result, entry)
            callback(result)
          else
            table.insert(result, entry)
          end
        end)
      else
        table.insert(result, entry)
        pending = pending - 1
        if pending == 0 then callback(result) end
      end
    end
  end)
end

---Converts a list of DAP variables into a Lua table.
---Numeric-looking keys like [0], [1] go into array part.
---Named keys go into map part.
---
---@param vars table[] # List of DAP variable tables with .name and .value
---@return table # A Lua table with mixed array and map-style keys
local function vars_to_table(vars)
  local result = {}

  for _, c in ipairs(vars) do
    local index = c.name:match("^%[(%d+)%]$")
    if index then
      table.insert(result, c.value)
    else
      result[c.name] = c.value
    end
  end

  return result
end

function M.extract(vars, var_type)
  if list.is_list(var_type) then
    local list_value = list.extract(vars)
    return list_value
  elseif anon.is_anon(var_type) then
    local anon_table = anon.extract(vars)
    return anon_table
  elseif tuple.is_tuple(var_type) then
    local tuple_value = tuple.extract(vars)
    return tuple_value
  elseif dict.is_dictionary(var_type) then
    local dict_value = dict.extract(vars)
    return dict_value
  elseif record.is_record(vars) then
    local record_table = record.extract(vars)
    return record_table
  else
    return vars_to_table(vars)
  end
end

local function pretty_print_var_ref(var_ref, var_type, cb)
  fetch_variables(var_ref, 2, function(vars)
    if list.is_list(var_type) then
      local list_value = list.extract(vars)
      cb(vim.inspect(list_value, { newline = "", indent = " " }))
    elseif anon.is_anon(var_type) then
      local anon_table = anon.extract(vars)
      cb(vim.inspect(anon_table, { newline = "" }))
    elseif tuple.is_tuple(var_type) then
      local tuple_value = tuple.extract(vars)
      cb("(" .. table.concat(tuple_value, ", ") .. ")")
    elseif dict.is_dictionary(var_type) then
      local dict_value = dict.extract(vars)
      cb(vim.inspect(dict_value, { newline = "" }))
    elseif record.is_record(vars) then
      local record_table = record.extract(vars)
      cb(vim.inspect(record_table, { newline = "" }))
    else
      -- Default: treat as flat array/list
      vim.print("DEFAULT")
      local pretty = table.concat(
        vim.tbl_map(function(c)
          if c.name:match("^%[%d+%]$") then
            return c.value
          else
            return string.format("%s: %s", c.name, c.value)
          end
        end, vars),
        ", "
      )
      cb(pretty)
    end
  end)
end

--- Resolves and pretty-prints a debugger variable by name and type.
---
--- If the result has already been cached (per `id`), it is returned immediately.
--- Otherwise, it will evaluate the variable using the DAP session and invoke the callback (if provided).
---
--- @param id number The stack frame `id` used to scope the cache.
--- @param var_name string The evaluated name passed to the debugger.
---                        Typically set via `variable.evaluateName` or `variable.name`.
--- @param var_type string The variable type, e.g., `"System.Collections.Generic.List<string>"`.
--- @param cb fun(result: string|false)? Optional callback function to receive the result.
---                                      - If successful: receives a formatted string.
---                                      - If failed/unhandled: receives `false`.
--- @return string|false|nil If cached, returns the cached result immediately (string or false).
---                          If not cached and a callback is used, returns nil and calls the callback asynchronously.
function M.resolve(id, var_name, var_type, cb)
  local dap = require("dap")

  M.pretty_cache[id] = M.pretty_cache[id] or {}

  local cache = M.pretty_cache[id]

  if cache[var_name] and cache[var_name] ~= "pending" then return cache[var_name] end

  if cache[var_name] ~= "pending" then
    cache[var_name] = "pending"

    local eval_expr = var_name
    if var_type and var_type:match("^System%.Linq%.Enumerable%.") then eval_expr = "(" .. var_name .. ").ToArray()" end

    dap.session():request("evaluate", { expression = eval_expr, context = "hover" }, function(err, response)
      if err or not response or not response.variablesReference then
        cache[var_name] = nil
        vim.schedule(function() vim.notify("No variable reference found for: " .. var_name) end)
        if cb then cb(false) end
        return
      end

      pretty_print_var_ref(response.variablesReference, var_type, function(pretty_str)
        cache[var_name] = pretty_str
        if cb then return cb(pretty_str) end
      end)
    end)
  else
    return false
  end

  return "pending"
end

return M
