local M = {}

local function lsp_debug(msg)
  if vim.lsp and vim.lsp.log and vim.lsp.log.debug then vim.lsp.log.debug("easy-dotnet", msg) end
end

M.info = function(msg) vim.notify(msg, vim.log.levels.INFO) end
M.debug = lsp_debug
M.error = function(msg) vim.notify(msg, vim.log.levels.ERROR) end
M.warn = function(msg) vim.notify(msg, vim.log.levels.WARN) end
M.trace = function(msg) vim.notify(msg, vim.log.levels.TRACE) end

return M
