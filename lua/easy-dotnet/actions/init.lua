local M = {}

local function file_path() return vim.api.nvim_buf_get_name(0) end

M.pack = function()
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  client:initialize(function() client.workspace:pack({ file_path = file_path() }) end)
end

M.pack_and_push = function()
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  client:initialize(function() client.workspace:pack_and_push({ file_path = file_path() }) end)
end

return M
