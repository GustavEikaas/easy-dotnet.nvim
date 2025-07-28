local tuple = require("easy-dotnet.netcoredbg.tuple")
local dict = require("easy-dotnet.netcoredbg.dictionaries")

local M = {
  ---@type table<number, table<string, string | "pending">>
  pretty_cache = {},
}

local primitives = require("easy-dotnet.netcoredbg.primitives")

local function generate_list_types()
  local results = {}
  for _, primitive in ipairs(primitives) do
    table.insert(results, "System.Collections.Generic.List<" .. primitive .. ">")
  end
  return results
end

local function generate_array_types()
  local results = {}
  for _, primitive in ipairs(primitives) do
    table.insert(results, primitive .. "[]")
  end
  return results
end

local arr_primitives = generate_array_types()
local list_primitives = generate_list_types()

local anon_like = {
  "<>f__AnonymousType0<string, int>",
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

local function pretty_print_var_ref(var_ref, var_type, cb)
  fetch_variables(var_ref, 2, function(vars)
    -- vars is list of child variables of the evaluated variable

    -- Detect if it's a List<string> backing object:
    -- Try to find the backing array field (_items or Items)
    local backing_array_var = nil
    local size = nil
    for _, v in ipairs(vars) do
      if size and backing_array_var then break end

      if v.name == "_items" or v.name == "Items" or v.name == "_array" then
        backing_array_var = v
      elseif v.name == "_size" then
        size = tonumber(v.value)
      end
    end

    if backing_array_var and backing_array_var.variablesReference and backing_array_var.variablesReference ~= 0 then
      fetch_variables(backing_array_var.variablesReference, 1, function(array_elements)
        local effective_elements = array_elements
        if size and size > 0 and size <= #array_elements then
          effective_elements = {}
          for i = 1, size do
            table.insert(effective_elements, array_elements[i])
          end
        end

        local pretty = table.concat(vim.tbl_map(function(c) return c.value end, effective_elements), ", ")
        cb(pretty)
      end)
    -- Handle AnonymousType0<string, any> as key-value structure
    elseif vim.tbl_contains(anon_like, var_type) then
      local entries = vim.tbl_map(function(v) return string.format("%s: %s", v.name, v.value) end, vars)
      cb(table.concat(entries, ", "))
    elseif tuple.is_tuple(var_type) then
      local tuple_value = tuple.extract(vars)
      cb("(" .. table.concat(tuple_value, ", ") .. ")")
    elseif dict.is_dictionary(var_type) then
      local dict_value = require("easy-dotnet.netcoredbg.dictionaries").extract(vars)
      cb(vim.inspect(dict_value, { newline = "" }))
    else
      -- Default: treat as flat array/list
      local pretty = table.concat(vim.tbl_map(function(c) return c.value end, vars), ", ")
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

  if
    (
      tuple.is_tuple(var_type)
      or dict.is_dictionary(var_type)
      or vim.tbl_contains(anon_like, var_type)
      or vim.tbl_contains(list_primitives, var_type)
      or vim.tbl_contains(arr_primitives, var_type)
    ) and cache[var_name] ~= "pending"
  then
    cache[var_name] = "pending"
    dap.session():request("evaluate", { expression = var_name, context = "hover" }, function(err, response)
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
