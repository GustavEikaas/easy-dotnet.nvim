-- Mirrors editor buffer state to the server so server-side features (profiler, future
-- diagnostics throttling, etc.) can scope work to files the user has open. The server tolerates
-- duplicate `opened` events and ignores `closed` for paths it doesn't know about.
local M = {}

local patterns = { "*.cs", "*.razor", "*.cshtml", "*.vb", "*.fs" }

local function should_track(path)
  if not path or path == "" then return false end
  for _, ext in ipairs({ ".cs", ".razor", ".cshtml", ".vb", ".fs" }) do
    if path:sub(-#ext) == ext then return true end
  end
  return false
end

local function notify(method, path)
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  -- :initialize is idempotent — fires the callback immediately when already connected, otherwise
  -- queues until the handshake completes. Cheap on the hot path.
  client:initialize(function()
    if method == "opened" then
      client.buffer:opened(path)
    else
      client.buffer:closed(path)
    end
  end)
end

local function for_each_loaded_buffer(fn)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if should_track(name) then fn(name) end
    end
  end
end

function M.attach()
  local group = vim.api.nvim_create_augroup("EasyDotnetBufferSync", { clear = true })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    pattern = patterns,
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if should_track(path) then notify("opened", path) end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    pattern = patterns,
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if should_track(path) then notify("closed", path) end
    end,
  })

  -- Sync buffers that are already loaded at setup time.
  for_each_loaded_buffer(function(path) notify("opened", path) end)
end

return M
