local M = {}

function M.open(options)
  local render = require("easy-dotnet.test-runner.render")
  local state = require("easy-dotnet.test-runner.state")
  local current_solution = require("easy-dotnet.current_solution")
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client

  render.open(options.viewmode, options)

  if state.root_id then return end

  current_solution.get_or_pick_solution(function(solution_path)
    if not solution_path then return end

    client:initialize(function()
      client.testrunner:initialize(solution_path, function(result)
        if not result or not result.success then require("easy-dotnet.logger").error("Test runner initialization failed") end
      end)
    end)
  end)
end

return M
