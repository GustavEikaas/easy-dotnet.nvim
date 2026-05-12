local M = {}

local function get_expression_from_cursor()
  local expression

  local ok_layer, layer = pcall(function()
    return require("dap.ui").get_layer(vim.api.nvim_get_current_buf())
  end)

  if ok_layer and layer then
    local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
    local node = layer.get(lnum)
    local item = node and node.item or nil
    if item then
      expression = item.evaluateName or item.name
    end
  end

  if expression == nil or expression == "" then
    expression = vim.fn.expand("<cexpr>")
  end

  if expression == nil or expression == "" then
    expression = vim.fn.expand("<cword>")
  end

  if expression == nil or expression == "" then
    expression = vim.fn.input("DAP expression: ")
  end

  return expression
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

function M.register_converter(converter)
  require("easy-dotnet.netcoredbg.preview_converters").register(converter)
end

function M.set_converters(converters)
  require("easy-dotnet.netcoredbg.preview_converters").set(converters)
end

function M.preview_under_cursor()
  local dap = require("dap")
  local session = dap.session()

  if not session then
    vim.notify("No active DAP session", vim.log.levels.WARN)
    return
  end

  local expression = get_expression_from_cursor()
  if expression == nil or expression == "" then
    vim.notify("No expression found", vim.log.levels.WARN)
    return
  end

  local supports_hover = session.capabilities and session.capabilities.supportsEvaluateForHovers
  local context = supports_hover and "hover" or "repl"

  session:evaluate({ expression = expression, context = context }, function(err, resp)
    vim.schedule(function()
      if err or not resp or not resp.result then
        vim.notify("DAP evaluate failed for: " .. expression, vim.log.levels.WARN)
        return
      end

      local converted = require("easy-dotnet.netcoredbg.preview_converters").convert(resp.result, resp)
      local text = converted.text:gsub("\\r\\n", "\n"):gsub("\\n", "\n")
      open_preview_float(text, {
        filetype = converted.filetype,
        title = converted.title,
      })
    end)
  end)
end

return M
