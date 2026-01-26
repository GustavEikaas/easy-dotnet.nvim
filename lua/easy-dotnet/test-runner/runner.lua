local Render = require("easy-dotnet.test-runner.render")
local Tree = require("easy-dotnet.test-runner.v2")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local logger = require("easy-dotnet.logger")

---@class easy-dotnet.TestRunner.Module
---@field client easy-dotnet.RPC.Client.Dotnet
local M = {
  client = require("easy-dotnet.rpc.rpc").global_rpc_client,
}

---@param solution_file_path string
local function refresh_runner(solution_file_path)
  M.client:initialize(function()
    M.client.test:test_runner_initialize(solution_file_path, function()
      M.client.test:test_runner_discover(function() end)
    end)
  end)
end

---@param options easy-dotnet.TestRunner.Options
---@param solution_file_path string
local function open_runner(options, solution_file_path)
  -- 1. Configure the Render module
  Render.setup(options)

  -- 2. Check Reuse:
  -- We check the Tree module directly. If it has children, we assume data is loaded.
  -- (Assuming Tree exposes a way to check content, e.g., checking if root has children or table count)
  local has_nodes = false
  if Tree.tree and next(Tree.tree) then has_nodes = true end

  -- 3. Open the UI (Render module handles window/buffer creation)
  Render.open(options.viewmode)

  -- 4. Initial Discovery (only if tree is empty)
  if not has_nodes then refresh_runner(solution_file_path) end
end

M.refresh = function(options)
  -- Trigger a re-discovery on the server
  M.client:initialize(function() M.client.test:test_runner_discover() end)
end

local function run_with_traceback(func)
  local co = coroutine.create(func)
  local ok, err = coroutine.resume(co)
  if not ok then error(debug.traceback(co, err), 0) end
end

M.runner = function(options)
  local sln = sln_parse.try_get_selected_solution_file()
  if not sln then
    logger.warn("Cannot open runner without a solution file")
    return
  end

  options = options or require("easy-dotnet.options").options.test_runner
  run_with_traceback(function() open_runner(options, sln) end)
end

return M
