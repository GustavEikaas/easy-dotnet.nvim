local M = {}

function M.open()
  local render = require("easy-dotnet.package-upgrade.render")
  local state  = require("easy-dotnet.package-upgrade.state")
  local current_solution = require("easy-dotnet.current_solution")
  local client  = require("easy-dotnet.rpc.rpc").global_rpc_client
  local options = require("easy-dotnet.options").get_option("package_upgrade")

  if render.win and vim.api.nvim_win_is_valid(render.win) then
    render.hide()
    return
  end

  state.reset()
  render.open()
  require("easy-dotnet.package-upgrade.keymaps").register(render.buf, client, options)

  current_solution.get_or_pick_solution(function(solution_path)
    if not solution_path then return end
    state.target_path = solution_path
    client:initialize(function()
      client.upgrade_wizard:open(solution_path, nil)
    end)
  end)
end

return M
