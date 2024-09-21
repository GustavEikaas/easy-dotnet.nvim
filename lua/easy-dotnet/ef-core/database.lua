local M = {}

M.database_update = function(migration_name)
  local selected_migration = { value = "" }
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project


  if migration_name == "pick" then
    local cmd = string.format("dotnet ef migrations list --prefix-output --project %s --startup-project %s", project
      .path, startup_project.path)
    local stdout = vim.fn.system(cmd)
    local migrations = {}
    local lines = {}
    for line in stdout:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end
    for _, value in ipairs(lines) do
      local migration = value:match("^data:%s*(%S+)")
      if migration then
        table.insert(migrations, {
          display = migration,
          value = migration,
          ordinal = migration
        })
      end
    end

    local selected = require("easy-dotnet.picker").pick_sync(nil, migrations)
    assert(selected, "No migration selected")
    selected_migration = selected
  end


  print(vim.inspect(selected_migration))
  local cmd = string.format("dotnet ef database update %s --project %s --startup-project %s",
    selected_migration.value,
    project.path,
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
