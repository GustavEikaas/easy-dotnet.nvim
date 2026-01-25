local win = require("easy-dotnet.test-runner.render")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local logger = require("easy-dotnet.logger")

---@class easy-dotnet.TestRunner.Module
---@field client easy-dotnet.RPC.Client.Dotnet

---@type easy-dotnet.TestRunner.Module
local M = {
  client = require("easy-dotnet.rpc.rpc").global_rpc_client,
}

---@class Highlight
---@field group string
---@field column_start number | nil
---@field column_end number | nil

local function refresh_runner(options, solution_file_path)
  M.client:initialize(function()
    M.client.test:test_runner_initialize(solution_file_path, function()
      M.client.test:test_runner_discover(function() end)
    end)
  end)
end

---@param options TestRunnerOptions
local function open_runner(options, solution_file_path)
  local is_reused = win.buf ~= nil and vim.api.nvim_buf_is_valid(win.buf) and vim.tbl_keys(win.tree) > 0

  win.buf_name = "Test manager"
  win.filetype = "easy-dotnet"
  win.set_options(options).set_keymaps(require("easy-dotnet.test-runner.keymaps").keymaps).render(options.viewmode)

  if is_reused then return end

  refresh_runner(options, solution_file_path)
end

M.refresh = function(options)
  logger.warn("refresh not implemented")
  --TODO: refresh
  options = options or require("easy-dotnet.options").options.test_runner
end

local function run_with_traceback(func)
  local co = coroutine.create(func)
  local ok, err = coroutine.resume(co)

  if not ok then error(debug.traceback(co, err), 0) end
end

M.runner = function(options)
  local sln = sln_parse.try_get_selected_solution_file()
  if not sln then logger.warn("cant open runner without sln file") end
  options = options or require("easy-dotnet.options").options.test_runner
  run_with_traceback(function() open_runner(options, sln) end)
end

return M
