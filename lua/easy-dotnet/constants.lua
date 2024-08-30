local M = {}

M.ns_id = vim.api.nvim_create_namespace('easy-dotnet')

M.get_data_directory = function()
  local dir = vim.fs.joinpath(vim.fn.stdpath("data"), "easy-dotnet")
  local file_utils = require("easy-dotnet.file-utils")
  file_utils.ensure_directory_exists(dir)
  return dir
end


return M
