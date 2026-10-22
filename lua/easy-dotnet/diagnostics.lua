local M = {}

local constants = require("easy-dotnet.constants")
local diagnostic_ns = vim.api.nvim_create_namespace("easy-dotnet-diagnostics")

local function get_or_create_buffer(filename)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == filename then return buf end
  end

  if vim.fn.filereadable(filename) == 1 then return vim.fn.bufadd(filename) end

  return nil
end

local function is_roslyn_client(client) return client.name == "roslyn" or client.name == constants.lsp_client_name end

---Roslyn keeps diagnostics for attached buffers up to date via pull diagnostics
---@param buf integer
local function has_live_diagnostics(buf)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if is_roslyn_client(client) then return true end
  end
  return false
end

-- Diagnostics in our namespace are a snapshot from the last workspace diagnostics run.
-- Once Roslyn attaches to a buffer it reports live diagnostics for it, so drop the snapshot
-- for that buffer to avoid stale (or duplicated) entries.
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("easy-dotnet-diagnostics", { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and is_roslyn_client(client) then vim.diagnostic.reset(diagnostic_ns, args.buf) end
  end,
})

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

  vim.diagnostic.reset(diagnostic_ns)

  local grouped_diagnostics = {}
  for _, diagnostic in ipairs(diagnostics) do
    local filepath = diagnostic.filePath

    if not filter_func or filter_func(filepath) then
      if not grouped_diagnostics[filepath] then grouped_diagnostics[filepath] = {} end
      table.insert(grouped_diagnostics[filepath], diagnostic_message_to_vim(diagnostic))
    end
  end

  local qf_diagnostics = {}
  for filepath, file_diagnostics in pairs(grouped_diagnostics) do
    local buf = get_or_create_buffer(filepath)
    if buf then
      for _, d in ipairs(file_diagnostics) do
        d.bufnr = buf
        table.insert(qf_diagnostics, d)
      end
      if not has_live_diagnostics(buf) then vim.diagnostic.set(diagnostic_ns, buf, file_diagnostics) end
    end
  end

  local total_count = #diagnostics
  local filtered_count = vim.tbl_count(grouped_diagnostics)
  vim.notify(string.format("Populated %d diagnostics across %d files", total_count, filtered_count), vim.log.levels.INFO)

  local options = require("easy-dotnet.options").options
  if options.diagnostics and options.diagnostics.setqflist then
    vim.fn.setqflist({}, " ", { title = "Workspace diagnostics", items = vim.diagnostic.toqflist(qf_diagnostics) })
    vim.cmd("botright copen")
  end
end

return M
