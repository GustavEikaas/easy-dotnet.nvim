local list = require("easy-dotnet.netcoredbg.value_converters.list")
local readonly_list = require("easy-dotnet.netcoredbg.value_converters.readonly_list")
local tuple = require("easy-dotnet.netcoredbg.value_converters.tuple")
local hashset = require("easy-dotnet.netcoredbg.value_converters.hashset")
local queue = require("easy-dotnet.netcoredbg.value_converters.queue")
local stack = require("easy-dotnet.netcoredbg.value_converters.stack")
local dict = require("easy-dotnet.netcoredbg.value_converters.dictionaries")
local readonly_dict = require("easy-dotnet.netcoredbg.value_converters.readonly_dictionary")
local concurrent_dict = require("easy-dotnet.netcoredbg.value_converters.concurrent_dictionary")

---@class Variable
---@field name string The variable's name.
---@field value string A one-line or multi-line string representing the variable.
---@field type? string The type of the variable, shown in the UI on hover.
---@field variablesReference integer Reference ID for child variables (0 = none).
---@field children? table<Variable>

---@class ResolvedVariable
---@field formatted_value string
---@field value table | string
---@field type string
---@field vars Variable[]
---@field variablesReference integer

local M = {
  ---@type table<integer, table<string, ResolvedVariable | "pending">>
  variable_cache = {},
  ---@type table<integer, table<string, (fun(value: ResolvedVariable))[]>>
  pending_callbacks = {},
}

function M.fetch_variables(variables_reference, depth, callback)
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
        M.fetch_variables(var.variablesReference, depth - 1, function(child_vars)
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
local function vars_to_table(vars, cb)
  local result = {}

  for _, c in ipairs(vars) do
    local index = c.name:match("^%[(%d+)%]$")
    if index then
      if c.variablesReference == 0 then
        table.insert(result, c.value)
      else
        table.insert(result, c)
      end
    else
      if c.variablesReference == 0 then
        result[c.name] = c.value
      else
        result[c.name] = c
      end
    end
  end
  cb(result)
end

function M.extract(vars, var_type, cb)
  if list.is_list(var_type) then
    local list_value = list.extract(vars, cb)
    return list_value
  elseif tuple.is_tuple(var_type) then
    local tuple_value = tuple.extract(vars, cb)
    return tuple_value
  elseif dict.is_dictionary(var_type) then
    local dict_value = dict.extract(vars, cb)
    return dict_value
  elseif concurrent_dict.is_concurrent_dictionary(var_type) then
    concurrent_dict.extract(vars, cb)
  elseif queue.is_queue(var_type) then
    queue.extract(vars, cb)
  elseif stack.is_stack(var_type) then
    stack.extract(vars, cb)
  elseif hashset.is_hashset(var_type) then
    hashset.extract(vars, cb)
  elseif readonly_dict.is_readonly_dictionary(var_type) then
    readonly_dict.extract(vars, cb)
  elseif readonly_list.is_readonly_list(var_type) then
    readonly_list.extract(vars, cb)
  else
    return vars_to_table(vars, cb)
  end
end

local banned_fields = {
  "EqualityContract",
}

local function format_catchall(val, cb)
  local max_items = 5
  local max_chars = 60

  local vars = val.vars or {}

  -- Partition into list vs record entries
  local list_items = vim.iter(vars):filter(function(c) return c.name:match("^%[%d+%]$") end):map(function(c) return tostring(c.value):gsub("\n", ""):gsub("%s+", " ") end):totable()

  local is_list = #list_items > 0

  local preview, count

  if is_list then
    count = #list_items
    preview = vim.iter(list_items):take(max_items):totable()
  else
    local kv_items = vim
      .iter(vars)
      :filter(function(c) return not c.name:match("^%[%d+%]$") and not vim.list_contains(banned_fields, c.name) end)
      :map(function(c) return string.format("%s: %s", c.name, tostring(c.value):gsub("\n", ""):gsub("%s+", " ")) end)
      :totable()
    count = #kv_items
    preview = vim.iter(kv_items):take(max_items):totable()
  end

  -- Join and format
  local joined = table.concat(preview, ", ")
  local too_long = count > max_items or #joined > max_chars

  local formatted
  if is_list then
    formatted = string.format("[%d] - [%s%s]", count, joined, too_long and ", ..." or "")
  else
    formatted = string.format("{%s%s}", joined, too_long and ", ..." or "")
  end

  cb(formatted)
end

---@param val ResolvedVariable
local function pretty_print_var_ref(val, cb)
  if list.is_list(val.type) then
    list.extract(val.vars, function(_, pretty_string) cb(pretty_string) end)
  elseif tuple.is_tuple(val.type) then
    tuple.extract(val.vars, function(_, pretty_string) cb(pretty_string) end)
  elseif dict.is_dictionary(val.type) then
    dict.extract(val.vars, function(_, pretty_string) cb(pretty_string) end)
  elseif concurrent_dict.is_concurrent_dictionary(val.type) then
    concurrent_dict.extract(val.vars, function(_, pretty_string) cb(pretty_string) end)
  elseif queue.is_queue(val.type) then
    queue.extract(val.vars, function(_, pretty_string) cb(pretty_string) end)
  elseif stack.is_stack(val.type) then
    stack.extract(val.vars, function(_, pretty_string) cb(pretty_string) end)
  elseif hashset.is_hashset(val.type) then
    hashset.extract(val.vars, function(_, pretty_string) cb(pretty_string) end)
  elseif readonly_dict.is_readonly_dictionary(val.type) then
    readonly_dict.extract(val.vars, function(_, pretty_string) cb(pretty_string) end)
  elseif readonly_list.is_readonly_list(val.type) then
    readonly_list.extract(val.vars, function(_, pretty_string) cb(pretty_string) end)
  elseif val.value.HasBeenThrown == "true" then
    cb("󱐋 " .. val.value.Message)
  else
    format_catchall(val, function(p) cb(p) end)
  end
end

---@param stack_frame_id integer
---@param vars_reference integer
---@param var_type string
---@param cb fun(value: ResolvedVariable): nil
---@return false | nil
function M.resolve_by_vars_reference(stack_frame_id, vars_reference, var_type, cb)
  if stack_frame_id == nil then error("Stack frame id cannot be nil") end
  if vars_reference == nil then error("vars ref  id cannot be nil") end

  M.variable_cache[stack_frame_id] = M.variable_cache[stack_frame_id] or {}
  M.pending_callbacks[stack_frame_id] = M.pending_callbacks[stack_frame_id] or {}
  local cache = M.variable_cache[stack_frame_id]
  local callback_queue = M.pending_callbacks[stack_frame_id]
  callback_queue[vars_reference] = callback_queue[vars_reference] or {}

  if cache[vars_reference] and cache[vars_reference] ~= "pending" then return cb(cache[vars_reference]) end

  if cache[vars_reference] == "pending" then
    table.insert(callback_queue[vars_reference], cb)
    return
  end

  cache[vars_reference] = "pending"
  callback_queue[vars_reference] = { cb }

  ---@param children table<Variable>
  M.fetch_variables(vars_reference, 0, function(children)
    M.extract(children, var_type, function(lua_type)
      ---@type ResolvedVariable
      local value = {
        formatted_value = "",
        vars = children,
        type = var_type,
        value = lua_type,
        variablesReference = vars_reference,
      }
      pretty_print_var_ref(value, function(res)
        value.formatted_value = res
        cache[vars_reference] = value

        for _, f in ipairs(callback_queue[vars_reference]) do
          f(value)
        end
        callback_queue[vars_reference] = nil
      end)
    end)
  end)
end

---@param stack_frame_id integer
---@param var_name string
---@param cb fun(value: ResolvedVariable): nil
---@return false | nil
function M.resolve_by_var_name(stack_frame_id, var_name, cb)
  local dap = require("dap")

  M.variable_cache[stack_frame_id] = M.variable_cache[stack_frame_id] or {}
  M.pending_callbacks[stack_frame_id] = M.pending_callbacks[stack_frame_id] or {}
  local cache = M.variable_cache[stack_frame_id]
  local callback_queue = M.pending_callbacks[stack_frame_id]
  callback_queue[var_name] = callback_queue[var_name] or {}

  if cache[var_name] and cache[var_name] ~= "pending" then return cb(cache[var_name]) end

  if cache[var_name] == "pending" then
    table.insert(callback_queue[var_name], cb)
    return
  end

  cache[var_name] = "pending"
  callback_queue[var_name] = { cb }

  local eval_expr = var_name
  --TODO: implement another way
  -- if var_type and var_type:match("^System%.Linq%.Enumerable%.") then eval_expr = "(" .. var_name .. ").ToArray()" end

  dap.session():request("evaluate", { expression = eval_expr, context = "hover" }, function(err, response)
    if err or not response or not response.variablesReference then
      cache[var_name] = nil
      callback_queue[var_name] = nil
      error("No variable reference found for: " .. var_name)
    end

    if response.variablesReference == 0 then
      --TODO: its a primitive

      ---@type ResolvedVariable
      local value = {
        formatted_value = response.result,
        vars = {},
        type = response.type,
        value = { [eval_expr] = {
          name = eval_expr,
          value = response.result,
          type = response.type,
          variablesReference = 0,
        } },
        variablesReference = response.variablesReference,
      }

      cache[var_name] = value

      for _, f in ipairs(callback_queue[var_name]) do
        f(value)
      end
      callback_queue[var_name] = nil
    else
      ---@param children table<Variable>
      M.fetch_variables(response.variablesReference, 0, function(children)
        M.extract(children, response.type, function(lua_type)
          ---@type ResolvedVariable
          local value = {
            formatted_value = "",
            vars = children,
            type = response.type,
            value = lua_type,
            variablesReference = response.variablesReference,
          }
          pretty_print_var_ref(value, function(res)
            value.formatted_value = res

            cache[var_name] = value

            for _, f in ipairs(callback_queue[var_name]) do
              f(value)
            end
            callback_queue[var_name] = nil
          end)
        end)
      end)
    end
  end)
end

M.register_dap_variables_viewer = require("easy-dotnet.netcoredbg.dap-listener").register_listener

return M
