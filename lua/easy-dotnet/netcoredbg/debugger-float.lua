local Window = require("easy-dotnet.test-runner.window")
local netcoredbg = require("easy-dotnet.netcoredbg")

local M = {}

local state = {
  root_vars = {},
  lines = {},
  line_to_var = {},
  current_frame_id = nil,
}

-- Recursively flatten variable tree into display lines
local function build_lines(vars, indent, line_counter)
  indent = indent or ""
  line_counter = line_counter or { count = 0 }
  local lines = {}

  for _, var in ipairs(vars) do
    local prefix = var.variablesReference and var.variablesReference > 0 and (var.expanded and "▼ " or "▶ ") or "• "
    local label = indent .. prefix .. var.name .. ": " .. (var.loading and "Loading..." or var.value or "")

    line_counter.count = line_counter.count + 1
    table.insert(lines, label)
    state.line_to_var[line_counter.count] = var

    if var.expanded and var.children then
      local sub = build_lines(var.children, indent .. "  ", line_counter)
      vim.list_extend(lines, sub)
    end
  end

  return lines
end

local function redraw(window)
  state.line_to_var = {}
  state.lines = build_lines(state.root_vars)
  window:write_buf(state.lines)
end

function M.redraw()
  if M._current_window then redraw(M._current_window) end
end

local function is_list(tbl) return type(tbl) == "table" and tbl[1] ~= nil end

-- Expand/collapse variable at cursor
function M.toggle_under_cursor(window)
  local cursor = vim.api.nvim_win_get_cursor(window.win)
  local line = cursor[1]
  local var = state.line_to_var[line]

  if not var or not var.variablesReference or var.variablesReference == 0 then return end

  -- Collapse
  if var.expanded then
    var.expanded = false
    redraw(window)
    return
  end

  -- Already loaded → expand
  if var.children then
    var.expanded = true
    redraw(window)
    return
  end

  -- Async load and expand
  var.loading = true
  var.expanded = true
  redraw(window)

  netcoredbg.resolve_by_vars_reference(state.current_frame_id, var.variablesReference, var.type, function(children)
    netcoredbg.extract(children.vars, children.type, function(converted_value)
      if is_list(converted_value) then
        --key pair value

        var.children = vim.tbl_map(
          function(r)
            return {
              name = r.name,
              type = r.type,
              value = r.value,
              variablesReference = r.variablesReference,
              expanded = false,
            }
          end,
          converted_value
        )
      else
        local root_vars = {}
        for key, value in pairs(converted_value) do
          table.insert(root_vars, {
            name = key,
            value = value.value or value,
            type = value.type,
            variablesReference = value.variablesReference,
            expanded = false,
          })
        end
        var.children = root_vars

        --key pair value
      end

      var.loading = false
      redraw(window)
    end)
  end)
end

--- Show debugger variable UI
---@param varlist table[] List of DAP-style variables
---@param frame_id number Frame ID to use for async resolution
function M.show(varlist, frame_id)
  state.current_frame_id = frame_id

  local root_vars = {}
  for key, value in pairs(varlist) do
    table.insert(root_vars, {
      name = key,
      value = value.value or value,
      type = value.type,
      variablesReference = value.variablesReference,
      expanded = false,
    })
  end

  state.root_vars = root_vars

  local float = Window.new_float():pos_center():create()
  M._current_window = float
  M.redraw()

  vim.keymap.set("n", "<CR>", function() M.toggle_under_cursor(float) end, { buffer = float.buf, noremap = true, silent = true })

  return float
end

return M
