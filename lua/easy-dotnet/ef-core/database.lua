local M = {}

M.database_update = function(mode)
  local selected_migration = { value = "" }
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  if mode == "pick" then
    local cmd = string.format("dotnet ef migrations list --prefix-output --project %s --startup-project %s", project.path, startup_project.path)
    local stdout = vim.fn.system(cmd)
    local migrations = {}
    local lines = {}
    for line in stdout:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end
    for _, value in ipairs(lines) do
      local migration = value:match("^data:%s*(%S+)")
      if migration then table.insert(migrations, {
        display = migration,
        value = migration,
        ordinal = migration,
      }) end
    end

    local selected = require("easy-dotnet.picker").pick_sync(nil, migrations)
    assert(selected, "No migration selected")
    selected_migration = selected
  end

  local spinner = require("easy-dotnet.ui-modules.spinner").new()
  local cmd = string.format("dotnet ef database update %s --project %s --startup-project %s", selected_migration.value, project.path, startup_project.path)

  spinner:start_spinner("Applying migrations")
  vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      if code == 0 then
        spinner:stop_spinner("Database updated")
      else
        spinner:stop_spinner("Database update failed", vim.log.levels.ERROR)
      end
    end,
  })
end
--
M.database_drop = function()
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  local spinner = require("easy-dotnet.ui-modules.spinner").new()
  local cmd = string.format("dotnet ef database drop --project %s --startup-project %s -f", project.path, startup_project.path)
  spinner:start_spinner("Dropping database")
  vim.fn.jobstart(cmd, {
    on_exit = function(_, code)
      if code == 0 then
        spinner:stop_spinner("Database dropped")
      else
        spinner:stop_spinner("Failed to drop database", vim.log.levels.ERROR)
      end
    end,
  })
end

return M
