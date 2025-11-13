local logger = require("easy-dotnet.logger")
local job = require("easy-dotnet.ui-modules.jobs")
local M = {}

M.database_update = function(mode)
  local selected_migration = { value = "" }
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  if mode == "pick" then
    local cmd = string.format("dotnet ef migrations list --prefix-output --project %s --startup-project %s", project.path, startup_project.path)
    local stdout = vim.fn.system(cmd)
    local exit_code = vim.v.shell_error
    if exit_code ~= 0 then
      logger.error(stdout)
      return
    end
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

  local migrations_job = job.register_job({ name = "Applying migrations", on_error_text = "Database update failed", on_success_text = "Database update failed" })
  local cmd = string.format("dotnet ef database update %s --project %s --startup-project %s", selected_migration.value, project.path, startup_project.path)
  local stdout = {}

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data) vim.list_extend(stdout, data) end,
    on_stderr = function(_, data) vim.list_extend(stdout, data) end,
    on_exit = function(_, code)
      if code ~= 0 then logger.error(table.concat(stdout, "\n")) end
      migrations_job(code == 0)
    end,
  })
end
--
M.database_drop = function()
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  local drop_job = job.register_job({ name = "Dropping database", on_error_text = "Failed to drop database", on_success_text = "Database dropped" })
  local cmd = string.format("dotnet ef database drop --project %s --startup-project %s -f", project.path, startup_project.path)
  local stdout = {}

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if data then vim.list_extend(stdout, data) end
    end,
    on_stderr = function(_, data)
      if data then vim.list_extend(stdout, data) end
    end,
    on_exit = function(_, code)
      if code ~= 0 then logger.error(table.concat(stdout, "\n")) end
      drop_job(code == 0)
    end,
  })
end

return M
