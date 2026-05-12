local M = {}

local SCOPE_HEADERS = {
  Locals = true,
  Arguments = true,
  Globals = true,
  Registers = true,
}

local function is_valid_expression(expr)
  if expr == nil then
    return false
  end

  expr = vim.trim(tostring(expr))
  return expr ~= "" and expr:match("[%w_%.$%[%]]") ~= nil
end

local function first_valid_expression(...)
  for i = 1, select("#", ...) do
    local expr = select(i, ...)
    if is_valid_expression(expr) then
      return expr
    end
  end

  return nil
end

local function join_expression(parts)
  if #parts == 0 then
    return nil
  end

  local expr = parts[1]
  for i = 2, #parts do
    local part = parts[i]
    expr = part:match("^%[.+%]$") and (expr .. part) or (expr .. "." .. part)
  end
  return expr
end

local function get_current_frame_id(session)
  return session and session.current_frame and session.current_frame.id or nil
end

local function get_dap_layer()
  local ok, layer = pcall(function()
    return require("dap.ui").get_layer(vim.api.nvim_get_current_buf())
  end)
  return ok and layer or nil
end

local function get_dap_item_under_cursor()
  local layer = get_dap_layer()
  if not layer then
    return nil
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local node = layer.get(line)
  return node and node.item or nil
end

local function build_expression_from_dap_node(node)
  local item = node and node.item
  if not item then
    return nil
  end

  local expr = first_valid_expression(
    item.evaluateName,
    item.expression,
    type(item.variable) == "table" and item.variable.evaluateName or nil,
    type(item.variable) == "table" and item.variable.name or nil
  )
  if expr then
    return expr
  end

  local parts = {}
  local cur = node
  while cur and cur.item do
    local name = cur.item.name
    if is_valid_expression(name) and not SCOPE_HEADERS[name] then
      table.insert(parts, 1, name)
    end
    cur = cur.parent
  end

  return join_expression(parts)
end

local function is_dapui_scopes_buffer(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local ft = vim.bo[buf].filetype
  local bt = vim.bo[buf].buftype

  return name:find("DAP Scopes", 1, true)
    or ft == "dapui_scopes"
    or ft == "dapui"
    or (bt == "nofile" and name:lower():find("scopes", 1, true))
end

local function parse_scopes_line(line)
  if not line or line == "" then
    return nil
  end

  local trimmed = vim.trim(line)
  if trimmed == "" then
    return nil
  end

  local content = trimmed
  local first, rest = trimmed:match("^(%S+)%s+(.*)$")
  if first and rest and not first:match("^[%w_]+$") then
    content = rest
  end

  local name = content:match("^([^%s=]+)")
  if not name then
    return nil
  end

  name = name:gsub(":$", "")
  return {
    indent = #(line:match("^(%s*)") or ""),
    name = name,
    is_scope = SCOPE_HEADERS[name] == true,
  }
end

local function build_expression_from_dapui_scopes_buffer()
  local buf = vim.api.nvim_get_current_buf()
  if not is_dapui_scopes_buffer(buf) then
    return nil
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, cursor_line, false)
  local stack = {}

  for i, line in ipairs(lines) do
    local parsed = parse_scopes_line(line)
    if parsed and not parsed.is_scope then
      while #stack > 0 and stack[#stack].indent >= parsed.indent do
        table.remove(stack)
      end
      table.insert(stack, parsed)

      if i == cursor_line then
        local names = vim.tbl_map(function(entry) return entry.name end, stack)
        return join_expression(names)
      end
    end
  end

  return nil
end

local function get_dapui_scopes_cursor_value()
  local buf = vim.api.nvim_get_current_buf()
  if not is_dapui_scopes_buffer(buf) then
    return nil
  end

  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(buf, line_nr - 1, line_nr, false)[1]
  local rhs = line and line:match("=%s*(.*)$") or nil
  return (rhs and rhs ~= "") and rhs or nil
end

local function get_expression_from_cursor(opts)
  opts = opts or {}

  local layer = get_dap_layer()
  if layer then
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local expr = first_valid_expression(build_expression_from_dap_node(layer.get(line)))
    if expr then
      return expr
    end
  end

  local expr = first_valid_expression(
    build_expression_from_dapui_scopes_buffer(),
    vim.fn.expand("<cexpr>"),
    vim.fn.expand("<cword>")
  )
  if expr then
    return expr
  end

  if not opts.no_prompt then
    return first_valid_expression(vim.fn.input("DAP expression: "))
  end

  return nil
end

local function close_window_if_valid(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function open_preview_float(text, opts)
  opts = opts or {}

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = opts.filetype or "txt"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
  vim.bo[buf].modifiable = false

  local width = math.floor(vim.o.columns * 0.75)
  local height = math.floor(vim.o.lines * 0.75)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = opts.title or " Evaluate Preview ",
    title_pos = "center",
  })

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.keymap.set("n", "q", function() close_window_if_valid(win) end, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", function() close_window_if_valid(win) end, { buffer = buf, silent = true })
end

local function fetch_variables_recursive(session, variables_reference, depth, cb)
  if depth <= 0 or variables_reference == 0 then
    cb({})
    return
  end

  session:request("variables", { variablesReference = variables_reference }, function(err, response)
    local vars = (not err and response and response.variables) or nil
    if not vars or #vars == 0 then
      cb({})
      return
    end

    local result = {}
    local pending = #vars

    local function done()
      pending = pending - 1
      if pending == 0 then
        cb(result)
      end
    end

    for _, var in ipairs(vars) do
      local entry = {
        name = var.name,
        value = var.value,
        type = var.type,
        variablesReference = var.variablesReference,
        children = {},
      }

      if var.variablesReference and var.variablesReference > 0 then
        fetch_variables_recursive(session, var.variablesReference, depth - 1, function(children)
          entry.children = children
          table.insert(result, entry)
          done()
        end)
      else
        table.insert(result, entry)
        done()
      end
    end
  end)
end

local function format_variables_tree(vars, indent, lines)
  indent = indent or ""
  lines = lines or {}

  for _, var in ipairs(vars) do
    table.insert(lines, string.format("%s%s: %s", indent, var.name, var.value or ""))
    if var.children and #var.children > 0 then
      format_variables_tree(var.children, indent .. "  ", lines)
    end
  end

  return lines
end

local function normalize_text(text)
  return tostring(text or ""):gsub("\\r\\n", "\n"):gsub("\\n", "\n")
end

local function maybe_pretty_json(text)
  local ok, decoded = pcall(vim.json.decode, text)
  if not ok then
    return text, nil
  end

  if type(decoded) == "table" then
    return vim.json.encode(decoded, { indent = "  " }), "json"
  end

  if type(decoded) == "string" then
    local ok_inner, decoded_inner = pcall(vim.json.decode, decoded)
    if ok_inner and type(decoded_inner) == "table" then
      return vim.json.encode(decoded_inner, { indent = "  " }), "json"
    end
  end

  return text, nil
end

local function build_preview_payload(text, filetype)
  local pretty, pretty_ft = maybe_pretty_json(normalize_text(text))
  return pretty, (filetype or pretty_ft)
end

local function open_converted_preview(text, response)
  local converted = require("easy-dotnet.netcoredbg.preview_converters").convert(text, response)
  local preview_text, preview_ft = build_preview_payload(converted.text, converted.filetype)
  open_preview_float(preview_text, { filetype = preview_ft, title = converted.title })
  return converted, preview_ft
end

local function preview_variable_tree(session, var)
  fetch_variables_recursive(session, var.variablesReference, 6, function(children)
    vim.schedule(function()
      local lines = { string.format("%s: %s", var.name or "value", normalize_text(var.value)) }
      if #children > 0 then
        format_variables_tree(children, "  ", lines)
      end
      open_preview_float(table.concat(lines, "\n"), { filetype = "txt" })
    end)
  end)
end

local function evaluate_expression(session, expression, frame_id, cb)
  local supports_hover = session.capabilities and session.capabilities.supportsEvaluateForHovers
  local request = {
    expression = expression,
    context = supports_hover and "hover" or "repl",
  }

  if frame_id ~= nil then
    request.frameId = frame_id
  end

  session:evaluate(request, cb)
end

local function get_expression_from_var(var)
  if not var then
    return nil
  end
  if var.var_path and var.var_path ~= "" then
    return var.var_path
  end
  return var.name
end

function M.register_converter(converter)
  require("easy-dotnet.netcoredbg.preview_converters").register(converter)
end

function M.set_converters(converters)
  require("easy-dotnet.netcoredbg.preview_converters").set(converters)
end

function M.preview_variable(selected_var, frame_id)
  local session = require("dap").session()
  if not session then
    vim.notify("No active DAP session", vim.log.levels.WARN)
    return
  end

  if selected_var and selected_var.variablesReference and selected_var.variablesReference > 0 then
    preview_variable_tree(session, selected_var)
    return
  end

  local expression = get_expression_from_var(selected_var)
  expression = first_valid_expression(expression)
  if not expression then
    vim.notify("No expression found", vim.log.levels.WARN)
    return
  end

  evaluate_expression(session, expression, frame_id, function(err, resp)
    vim.schedule(function()
      if err or not resp or not resp.result then
        vim.notify("DAP evaluate failed for: " .. expression, vim.log.levels.WARN)
        return
      end

      local converted = require("easy-dotnet.netcoredbg.preview_converters").convert(resp.result, resp)
      local text, filetype = build_preview_payload(converted.text, converted.filetype)
      if filetype == nil and selected_var and selected_var.value then
        local fallback_text, fallback_ft = build_preview_payload(selected_var.value, nil)
        if fallback_ft == "json" then
          text = fallback_text
          filetype = fallback_ft
        end
      end

      open_preview_float(text, { filetype = filetype, title = converted.title })
    end)
  end)
end

function M.preview_under_cursor()
  local ok, viewer = pcall(require, "easy-dotnet.netcoredbg.debugger-float")
  local has_active_viewer = ok and viewer._current_window and vim.api.nvim_win_is_valid(viewer._current_window.win)
  local has_viewer_state = has_active_viewer or vim.b.easy_dotnet_debugger_float_line_to_var ~= nil
  if has_viewer_state then
    vim.notify("No variable under cursor", vim.log.levels.WARN)
    return
  end

  local session = require("dap").session()
  if not session then
    vim.notify("No active DAP session", vim.log.levels.WARN)
    return
  end

  local dap_item = get_dap_item_under_cursor()
  if dap_item and dap_item.variablesReference and dap_item.variablesReference > 0 then
    preview_variable_tree(session, dap_item)
    return
  end

  if dap_item and dap_item.value ~= nil then
    open_converted_preview(tostring(dap_item.value), { type = dap_item.type, result = tostring(dap_item.value) })
    return
  end

  local scopes_value = get_dapui_scopes_cursor_value()
  if scopes_value then
    open_converted_preview(scopes_value, { result = scopes_value })
    return
  end

  local expression = get_expression_from_cursor({ no_prompt = true })
  if not expression then
    vim.notify("No expression found", vim.log.levels.WARN)
    return
  end

  evaluate_expression(session, expression, get_current_frame_id(session), function(err, resp)
    vim.schedule(function()
      if err or not resp or not resp.result then
        vim.notify("DAP evaluate failed for: " .. expression, vim.log.levels.WARN)
        return
      end

      open_converted_preview(resp.result, resp)
    end)
  end)
end

return M
