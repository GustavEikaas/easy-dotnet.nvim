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
local function build_lines(vars, indent)
  indent = indent or ""
  local lines = {}
  for _, var in ipairs(vars) do
    local prefix = var.variablesReference and var.variablesReference > 0 and (var.expanded and "▼ " or "▶ ") or "• "
    local label = indent .. prefix .. var.name .. ": " .. (var.loading and "Loading..." or var.value or "")
    local line_index = #lines + 1
    table.insert(lines, label)
    state.line_to_var[#state.lines + line_index] = var

    if var.expanded and var.children then
      local sub = build_lines(var.children, indent .. "  ")
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
    vim.print(children)
    vim.schedule(function()
      var.children = vim.tbl_map(
        function(child)
          return {
            name = child.name,
            value = child.value,
            variablesReference = child.variablesReference,
            type = child.type,
          }
        end,
        children.vars
      )
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
  state.root_vars = vim.tbl_map(
    function(v)
      return {
        name = v.name,
        value = v.value,
        variablesReference = v.variablesReference,
        type = v.type,
        expanded = false,
      }
    end,
    varlist
  )

  local lines = build_lines(state.root_vars)
  state.lines = lines

  local float = Window.new_float():pos_center():write_buf(lines):create()
  M._current_window = float

  vim.keymap.set("n", "<CR>", function() M.toggle_under_cursor(float) end, { buffer = float.buf, noremap = true, silent = true })

  vim.keymap.set("n", "q", function() float:close() end, { buffer = float.buf, noremap = true, silent = true })

  return float
end

return M
