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

M.extract = require("easy-dotnet.netcoredbg.value_converters").extract

---@param stack_frame_id integer
---@param vars_reference integer
---@param var_type string
---@param cb fun(value: ResolvedVariable): nil
---@return false | nil
function M.resolve_by_vars_reference(stack_frame_id, vars_reference, var_path, var_type, cb)
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
    M.extract(stack_frame_id, children, var_path, var_type, function(lua_type, res, hi)
      ---@type ResolvedVariable
      local value = {
        formatted_value = "",
        hi = hi,
        vars = children,
        type = var_type,
        value = lua_type,
        variablesReference = vars_reference,
      }

      value.formatted_value = res
      cache[vars_reference] = value

      for _, f in ipairs(callback_queue[vars_reference]) do
        f(value)
      end
      callback_queue[vars_reference] = nil
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

  dap.session():request("evaluate", { frameId = stack_frame_id, expression = eval_expr, context = "hover" }, function(err, response)
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
        var_path = var_name,
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
        M.extract(stack_frame_id, children, var_name, response.type, function(lua_type, res, hi)
          ---@type ResolvedVariable
          local value = {
            formatted_value = "",
            var_path = var_name,
            hi = hi,
            vars = children,
            type = response.type,
            value = lua_type,
            variablesReference = response.variablesReference,
          }

          value.formatted_value = res
          cache[var_name] = value

          for _, f in ipairs(callback_queue[var_name]) do
            f(value)
          end
          callback_queue[var_name] = nil
        end)
      end)
    end
  end)
end

M.register_dap_variables_viewer = require("easy-dotnet.netcoredbg.dap-listener").register_listener

return M
