local M = {}

M.info = function(msg) vim.notify(msg, vim.log.levels.INFO) end
M.error = function(msg) vim.notify(msg, vim.log.levels.ERROR) end
M.warn = function(msg) vim.notify(msg, vim.log.levels.WARN) end
M.trace = function(msg) vim.notify(msg, vim.log.levels.TRACE) end

return M
