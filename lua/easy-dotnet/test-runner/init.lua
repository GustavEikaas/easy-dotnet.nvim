local M = {}

function M.auto_start()
  if not require("easy-dotnet.options").get_option("test_runner").auto_start_testrunner then return end
  local current_solution = require("easy-dotnet.current_solution")
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  local state = require("easy-dotnet.test-runner.state")
  if state.root_id then return end

  local sln = current_solution.try_get_selected_solution()
  if sln then client:initialize(function() client.testrunner:quick_discover(sln, nil) end) end
end

function M.open()
  local options = require("easy-dotnet.options").get_option("test_runner")
  local render = require("easy-dotnet.test-runner.render")
  local state = require("easy-dotnet.test-runner.state")
  local current_solution = require("easy-dotnet.current_solution")
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client

  if render.win and vim.api.nvim_win_is_valid(render.win) then
    render.hide()
    return
  end

  render.open(options.viewmode, options)
  require("easy-dotnet.test-runner.keymaps").register(render.buf, client, options)

  if state.root_id then return end

  current_solution.get_or_pick_solution(function(solution_path)
    if not solution_path then return end
    client:initialize(function()
      state.active_handle = client.testrunner:initialize(solution_path, function(result)
        if not result or not result.success then require("easy-dotnet.logger").error("Test runner initialization failed") end
      end)
    end)
  end)
end

return M
