local M = {}

--- Checks if the class is System.Collections.Immutable.ImmutableList<T>
---@param class_name string
---@return boolean
M.is_immutable_list = function(class_name) return type(class_name) == "string" and class_name:match("^System%.Collections%.Immutable%.ImmutableList") ~= nil end

local function traverse_node(var, cb, acc)
  local netcoredbg = require("easy-dotnet.netcoredbg")
  acc = acc or {}

  local left_ref, right_ref, value_var
  local is_empty = true

  for _, child in ipairs(var) do
    if child.name == "_left" then
      left_ref = child.variablesReference
    elseif child.name == "_right" then
      right_ref = child.variablesReference
    elseif child.name == "Value" then
      value_var = child
    elseif child.name == "IsEmpty" then
      is_empty = child.value == "true"
    end
  end

  local function process_current_and_right()
    if value_var and not is_empty then table.insert(acc, { value = value_var }) end

    if right_ref and right_ref ~= 0 then
      netcoredbg.fetch_variables(right_ref, 0, function(right_children) traverse_node(right_children, cb, acc) end)
    else
      cb(acc)
    end
  end

  if left_ref and left_ref ~= 0 then
    netcoredbg.fetch_variables(left_ref, 0, function(left_children) traverse_node(left_children, process_current_and_right, acc) end)
  else
    process_current_and_right()
  end
end

local function to_pretty_string(c)
  local max_elements = 5
  local max_chars = 50

  local all_unresolved = vim.iter(c):all(function(r) return r.variablesReference ~= 0 end)

  if all_unresolved and #c > 0 then return (string.format("[%d] - [%s...]", #c, c[1].value)) end

  local values = {}
  for i, r in ipairs(c) do
    if i > max_elements then break end
    local v = r.value
    if r.variablesReference == 0 then v = vim.inspect(v):gsub("\n", ""):gsub("%s+", " ") end
    table.insert(values, v)
  end

  local preview_str = "[" .. table.concat(values, ", ") .. "]"
  if #c > max_elements or #preview_str > max_chars then preview_str = preview_str:gsub("]$", ", ...]") end

  return (string.format("[%d] - %s", #values, preview_str))
end

--- Extract the internal list from ImmutableList<T> and delegate to list extractor
---@param vars table
---@param cb function
function M.extract(vars, cb)
  local netcoredbg = require("easy-dotnet.netcoredbg")
  local root_ref

  for _, entry in ipairs(vars) do
    if entry.name == "_root" and entry.variablesReference and entry.variablesReference ~= 0 then
      root_ref = entry.variablesReference
      break
    end
  end

  if not root_ref then
    cb({}, "[]")
    return
  end

  netcoredbg.fetch_variables(root_ref, 0, function(root_children)
    traverse_node(root_children, function(acc)
      local values = {}
      for _, v in ipairs(acc) do
        table.insert(values, v.value)
      end

      cb(values, to_pretty_string(values))
    end, {})
  end)
end
return M
