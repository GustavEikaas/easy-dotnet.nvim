local M = {}

M.database_update = function()
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  local cmd = string.format("dotnet ef database update --project %s --startup-project %s", project.path,
    startup_project.path)
  vim.notify(cmd)
  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)

    end,
    on_exit = function(_, code)
      if code == 0 then
        vim.notify("Success")
      else
        vim.notify("Failed", vim.log.levels.ERROR)
      end
    end
  })
end
--
M.database_drop = function()
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  local cmd = string.format("dotnet ef database drop --project %s --startup-project %s -f", project.path,
    startup_project.path)
  vim.notify(cmd)
  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)

    end,
    on_exit = function(_, code)
      if code == 0 then
        vim.notify("Success")
      else
        vim.notify("Failed", vim.log.levels.ERROR)
      end
    end
  })
end

return M
