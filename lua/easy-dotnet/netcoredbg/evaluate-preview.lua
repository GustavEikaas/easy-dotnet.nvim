local M = {}

local function get_var_from_easy_dotnet_variable_viewer()
  local ok, viewer = pcall(require, "easy-dotnet.netcoredbg.debugger-float")
  if not ok then
    return nil
  end

  local active_var = viewer.get_var_from_active_viewer_window and viewer.get_var_from_active_viewer_window() or nil
  if active_var then
    return active_var
  end

  local line_to_var = vim.b.easy_dotnet_debugger_float_line_to_var
  if type(line_to_var) == "table" then
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local var = line_to_var[line]
    if var then
      return var
    end
  end

  local var = viewer.get_var_under_cursor()
  if var then
    return var
  end

  return nil
end

local function get_frame_id_from_easy_dotnet_variable_viewer()
  local ok, viewer = pcall(require, "easy-dotnet.netcoredbg.debugger-float")
  if not ok then
    return vim.b.easy_dotnet_debugger_float_frame_id
  end

  local active_frame_id = viewer.get_current_frame_id_from_active_viewer_window and viewer.get_current_frame_id_from_active_viewer_window() or nil
  if active_frame_id ~= nil then
    return active_frame_id
  end

  if vim.b.easy_dotnet_debugger_float_frame_id ~= nil then
    return vim.b.easy_dotnet_debugger_float_frame_id
  end

  local frame_id = viewer.get_current_frame_id()
  if frame_id ~= nil then
    return frame_id
  end

  return nil
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

local function is_valid_expression(expr)
  if expr == nil then
    return false
  end

  expr = vim.trim(tostring(expr))
  if expr == "" then
    return false
  end

  return expr:match("[%w_%.$%[%]]") ~= nil
end

local function build_expression_from_dap_node(node)
  local item = node and node.item or nil
  if not item then
    return nil
  end

  if is_valid_expression(item.evaluateName) then
    return item.evaluateName
  end

  if is_valid_expression(item.expression) then
    return item.expression
  end

  if type(item.variable) == "table" then
    if is_valid_expression(item.variable.evaluateName) then
      return item.variable.evaluateName
    end
    if is_valid_expression(item.variable.name) then
      return item.variable.name
    end
  end

  local parts = {}
  local cur = node
  while cur and cur.item do
    local name = cur.item.name
    if name and is_valid_expression(name) and name ~= "Locals" and name ~= "Globals" and name ~= "Arguments" and name ~= "Registers" then
      table.insert(parts, 1, name)
    end
    cur = cur.parent
  end

  if #parts == 0 then
    return nil
  end

  local expr = parts[1]
  for i = 2, #parts do
    local part = parts[i]
    if part:match("^%[.+%]$") then
      expr = expr .. part
    else
      expr = expr .. "." .. part
    end
  end
  return expr
end

local function parse_dapui_variable_line(line)
  if not line or line == "" then
    return nil
  end

  local indent = line:match("^(%s*)") or ""
  local trimmed = vim.trim(line)
  if trimmed == "" then
    return nil
  end

  local first_token, rest = trimmed:match("^(%S+)%s+(.*)$")
  if not first_token then
    return nil
  end

  local icon
  if first_token:match("^[%w_]+$") then
    rest = trimmed
  else
    icon = first_token
  end

  if not rest or rest == "" then
    return nil
  end

  local name = rest:match("^([^%s=]+)")
  if not name or name == "" then
    return nil
  end

  local scope_name = name:gsub(":$", "")

  if scope_name == "Locals" or scope_name == "Arguments" or scope_name == "Globals" or scope_name == "Registers" then
    return {
      is_scope = true,
      indent = #indent,
      name = scope_name,
      icon = icon,
    }
  end

  return {
    is_scope = false,
    indent = #indent,
    name = scope_name,
    icon = icon,
  }
end

local function build_expression_from_dapui_scopes_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local filetype = vim.bo[buf].filetype
  local buftype = vim.bo[buf].buftype

  local is_dapui_scope = name:find("DAP Scopes", 1, true)
    or filetype == "dapui_scopes"
    or filetype == "dapui"
    or (buftype == "nofile" and name:lower():find("scopes", 1, true))

  if not is_dapui_scope then
    return nil
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, cursor_line, false)
  local stack = {}

  for i, line in ipairs(lines) do
    local parsed = parse_dapui_variable_line(line)

    if parsed and not parsed.is_scope then
      while #stack > 0 and stack[#stack].indent >= parsed.indent do
        table.remove(stack)
      end
      table.insert(stack, parsed)

      if i == cursor_line then
        local expr = stack[1].name
        for j = 2, #stack do
          local part = stack[j].name
          if part:match("^%[.+%]$") then
            expr = expr .. part
          else
            expr = expr .. "." .. part
          end
        end
        return expr
      end
    end
  end

  return nil
end

local function get_dapui_scopes_cursor_value()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local filetype = vim.bo[buf].filetype
  local buftype = vim.bo[buf].buftype

  local is_dapui_scope = name:find("DAP Scopes", 1, true)
    or filetype == "dapui_scopes"
    or filetype == "dapui"
    or (buftype == "nofile" and name:lower():find("scopes", 1, true))

  if not is_dapui_scope then
    return nil
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(buf, cursor_line - 1, cursor_line, false)[1]
  if not line then
    return nil
  end

  local rhs = line:match("=%s*(.*)$")
  if not rhs or rhs == "" then
    return nil
  end

  return rhs
end

local function get_current_frame_id(session)
  if session and session.current_frame and session.current_frame.id then
    return session.current_frame.id
  end
  return nil
end

local function get_expression_from_cursor(opts)
  opts = opts or {}
  local expression

  expression = get_expression_from_var(get_var_from_easy_dotnet_variable_viewer())
  if expression and expression ~= "" then
    return expression
  end

  local ok_layer, layer = pcall(function()
    return require("dap.ui").get_layer(vim.api.nvim_get_current_buf())
  end)

  if ok_layer and layer then
    local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
    local node = layer.get(lnum)
    expression = build_expression_from_dap_node(node)
  end

  if not is_valid_expression(expression) then
    expression = build_expression_from_dapui_scopes_buffer()
  end

  if not is_valid_expression(expression) then
    expression = vim.fn.expand("<cexpr>")
  end

  if not is_valid_expression(expression) then
    expression = vim.fn.expand("<cword>")
  end

  if not is_valid_expression(expression) and not opts.no_prompt then
    expression = vim.fn.input("DAP expression: ")
  end

  if not is_valid_expression(expression) then
    return nil
  end

  return expression
end

local function get_dap_item_under_cursor()
  local ok_layer, layer = pcall(function()
    return require("dap.ui").get_layer(vim.api.nvim_get_current_buf())
  end)

  if not ok_layer or not layer then
    return nil
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local node = layer.get(lnum)
  if not node then
    return nil
  end

  return node.item
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
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
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
    if err or not response or not response.variables then
      cb({})
      return
    end

    local vars = response.variables
    if #vars == 0 then
      cb({})
      return
    end

    local result = {}
    local pending = #vars

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
          pending = pending - 1
          if pending == 0 then cb(result) end
        end)
      else
        table.insert(result, entry)
        pending = pending - 1
        if pending == 0 then cb(result) end
      end
    end
  end)
end

local function format_variables_tree(vars, indent, lines)
  indent = indent or ""
  lines = lines or {}

  for _, var in ipairs(vars) do
    local value = var.value or ""
    table.insert(lines, string.format("%s%s: %s", indent, var.name, value))
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
  if ok and type(decoded) == "table" then
    return vim.json.encode(decoded, { indent = "  " }), "json"
  end

  if ok and type(decoded) == "string" then
    local ok_inner, decoded_inner = pcall(vim.json.decode, decoded)
    if ok_inner and type(decoded_inner) == "table" then
      return vim.json.encode(decoded_inner, { indent = "  " }), "json"
    end
  end

  return text, nil
end

local function build_preview_payload(text, filetype)
  local normalized = normalize_text(text)
  local pretty, pretty_ft = maybe_pretty_json(normalized)
  return pretty, (filetype or pretty_ft)
end

function M.register_converter(converter)
  require("easy-dotnet.netcoredbg.preview_converters").register(converter)
end

function M.set_converters(converters)
  require("easy-dotnet.netcoredbg.preview_converters").set(converters)
end

function M.preview_variable(selected_var, frame_id)
  local dap = require("dap")
  local session = dap.session()

  if not session then
    vim.notify("No active DAP session", vim.log.levels.WARN)
    return
  end

  if selected_var and selected_var.variablesReference and selected_var.variablesReference > 0 then
    fetch_variables_recursive(session, selected_var.variablesReference, 6, function(children)
      vim.schedule(function()
        local lines = {
          string.format("%s: %s", selected_var.name or "value", normalize_text(selected_var.value)),
        }
        if #children > 0 then
          format_variables_tree(children, "  ", lines)
        end
        open_preview_float(table.concat(lines, "\n"), {
          filetype = "txt",
        })
      end)
    end)
    return
  end

  local expression = get_expression_from_var(selected_var)
  if expression == nil or expression == "" then
    vim.notify("No expression found", vim.log.levels.WARN)
    return
  end

  local supports_hover = session.capabilities and session.capabilities.supportsEvaluateForHovers
  local context = supports_hover and "hover" or "repl"

  local request = { expression = expression, context = context }
  if frame_id ~= nil then
    request.frameId = frame_id
  end

  session:evaluate(request, function(err, resp)
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
      open_preview_float(text, {
        filetype = filetype,
        title = converted.title,
      })
    end)
  end)
end

function M.preview_under_cursor()
  local ok, viewer = pcall(require, "easy-dotnet.netcoredbg.debugger-float")
  local has_active_viewer = ok and viewer._current_window and vim.api.nvim_win_is_valid(viewer._current_window.win)
  local has_viewer_state = has_active_viewer or vim.b.easy_dotnet_debugger_float_line_to_var ~= nil

  local selected_var = get_var_from_easy_dotnet_variable_viewer()
  if selected_var then
    return M.preview_variable(selected_var, get_frame_id_from_easy_dotnet_variable_viewer())
  end

  if has_viewer_state then
    vim.notify("No variable under cursor", vim.log.levels.WARN)
    return
  end

  local dap = require("dap")
  local session = dap.session()

  if not session then
    vim.notify("No active DAP session", vim.log.levels.WARN)
    return
  end

  local dap_item = get_dap_item_under_cursor()
  if dap_item and dap_item.variablesReference and dap_item.variablesReference > 0 then
    fetch_variables_recursive(session, dap_item.variablesReference, 6, function(children)
      vim.schedule(function()
        local lines = {
          string.format("%s: %s", dap_item.name or "value", normalize_text(dap_item.value)),
        }
        if #children > 0 then
          format_variables_tree(children, "  ", lines)
        end
        open_preview_float(table.concat(lines, "\n"), {
          filetype = "txt",
        })
      end)
    end)
    return
  elseif dap_item and dap_item.value ~= nil then
    local converted = require("easy-dotnet.netcoredbg.preview_converters").convert(tostring(dap_item.value), {
      type = dap_item.type,
      result = tostring(dap_item.value),
    })
    local text, filetype = build_preview_payload(converted.text, converted.filetype)
    open_preview_float(text, {
      filetype = filetype,
      title = converted.title,
    })
    return
  end

  local scopes_value = get_dapui_scopes_cursor_value()
  if scopes_value then
    local converted = require("easy-dotnet.netcoredbg.preview_converters").convert(scopes_value, {
      result = scopes_value,
    })
    local text, filetype = build_preview_payload(converted.text, converted.filetype)
    open_preview_float(text, {
      filetype = filetype,
      title = converted.title,
    })
    return
  end

  local expression = get_expression_from_cursor({ no_prompt = true })
  if expression == nil or expression == "" then
    vim.notify("No expression found", vim.log.levels.WARN)
    return
  end

  local supports_hover = session.capabilities and session.capabilities.supportsEvaluateForHovers
  local context = supports_hover and "hover" or "repl"
  local frame_id = get_current_frame_id(session)
  local request = { expression = expression, context = context }
  if frame_id ~= nil then
    request.frameId = frame_id
  end

  session:evaluate(request, function(err, resp)
    vim.schedule(function()
      if err or not resp or not resp.result then
        vim.notify("DAP evaluate failed for: " .. expression, vim.log.levels.WARN)
        return
      end

      local converted = require("easy-dotnet.netcoredbg.preview_converters").convert(resp.result, resp)
      local text, filetype = build_preview_payload(converted.text, converted.filetype)
      open_preview_float(text, {
        filetype = filetype,
        title = converted.title,
      })
    end)
  end)
end

return M
