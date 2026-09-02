local M = {}

function M.open()
  local render = require("easy-dotnet.project-view.render")
  local state = require("easy-dotnet.project-view.state")
  local jobs = require("easy-dotnet.ui-modules.jobs")
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client

  if render.win and vim.api.nvim_win_is_valid(render.win) then
    render.hide()
    state.clear()
    return
  end

  if state.project_path and state.snapshot then
    render.open({})
    require("easy-dotnet.project-view.keymaps").register(render.buf, client, {})
    render.refresh()
    return
  end

  client:initialize(function()
    local finish = jobs.register_job({
      name = "Loading project view…",
      on_success_text = "Project view loaded",
      on_error_text = "Failed to load project view",
    })

    client.project_view:get(nil, function(snapshot)
      finish(true)
      if not snapshot then return end
      vim.schedule(function()
        state.set(snapshot.header.projectPath, snapshot)
        render.open({})
        require("easy-dotnet.project-view.keymaps").register(render.buf, client, {})
        render.refresh()
      end)
    end, { on_crash = function() finish(false) end })
  end)
end

return M
