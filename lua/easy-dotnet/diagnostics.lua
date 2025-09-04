local M = {}

local diagnostic_ns = vim.api.nvim_create_namespace("easy-dotnet-diagnostics")


local function get_or_create_buffer(filename)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == filename then return buf end
  end

  if vim.fn.filereadable(filename) == 1 then return vim.fn.bufadd(filename) end

  return nil
end

---@param diagnostic_msg table DiagnosticMessage from server
---@return vim.Diagnostic
local function diagnostic_message_to_vim(diagnostic_msg)
  return {
    lnum = diagnostic_msg.range.start.line,
    col = diagnostic_msg.range.start.character,
    end_lnum = diagnostic_msg.range["end"].line,
    end_col = diagnostic_msg.range["end"].character,
    severity = diagnostic_msg.severity,
    message = diagnostic_msg.message,
    source = diagnostic_msg.source or "roslyn",
    code = diagnostic_msg.code,
    user_data = {
      category = diagnostic_msg.category,
    },
  }
end

---@param diagnostics_response table
---@param filter_func? function Optional function to filter files
function M.populate_diagnostics(diagnostics_response, filter_func)
  if not diagnostics_response then
    vim.notify("No diagnostics response received", vim.log.levels.WARN)
    return
  end

  local diagnostics = diagnostics_response
  if type(diagnostics) ~= "table" then
    vim.notify("Invalid diagnostics response format", vim.log.levels.WARN)
    return
  end


  local roslyn_clients = vim.lsp.get_clients({ name = "roslyn" })
  local ns = diagnostic_ns

  if roslyn_clients and #roslyn_clients > 0 then
    for _, client in ipairs(roslyn_clients) do
      local ok, lsp_ns = pcall(vim.lsp.diagnostic.get_namespace, client.id)
      if ok and lsp_ns then
        ns = lsp_ns
        break
      end
    end
  end

  vim.diagnostic.reset(ns)

  local grouped_diagnostics = {}
  for _, diagnostic in ipairs(diagnostics) do
    local filepath = diagnostic.filePath

    if not filter_func or filter_func(filepath) then
      if not grouped_diagnostics[filepath] then grouped_diagnostics[filepath] = {} end
      table.insert(grouped_diagnostics[filepath], diagnostic_message_to_vim(diagnostic))
    end
  end

  for filepath, file_diagnostics in pairs(grouped_diagnostics) do
    local buf = get_or_create_buffer(filepath)
    if buf then vim.diagnostic.set(ns, buf, file_diagnostics) end
  end

  local total_count = #diagnostics
  local filtered_count = vim.tbl_count(grouped_diagnostics)
  vim.notify(string.format("Populated %d diagnostics across %d files", total_count, filtered_count), vim.log.levels.INFO)
end

return M
