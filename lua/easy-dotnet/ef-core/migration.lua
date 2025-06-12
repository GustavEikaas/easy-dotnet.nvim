local logger = require("easy-dotnet.logger")
local job = require("easy-dotnet.ui-modules.jobs")
local M = {}

---@param migration_name string
M.add_migration = function(migration_name)
  if not migration_name then
    logger.error("Migration name required")
    return
  end
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  local cmd = string.format("dotnet ef migrations add %s --project %s --startup-project %s", migration_name, project.path, startup_project.path)

  local migration_job = job.register_job({ name = "Adding migration", on_error_text = "Failed to add migration", on_success_text = "Migration added" })
  vim.fn.jobstart(cmd, { on_exit = function(_, code) migration_job(code == 0) end })
end

M.remove_migration = function()
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  local cmd = string.format("dotnet ef migrations remove --project %s --startup-project %s", project.path, startup_project.path)

  local migration_job = job.register_job({ name = "Removing migration", on_error_text = "Failed to remove migration", on_success_text = "Migration removed" })
  vim.fn.jobstart(cmd, {
    on_exit = function(_, code) migration_job(code == 0) end,
  })
end

M.list_migrations = function()
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  local cmd = string.format("dotnet ef migrations list --prefix-output --project %s --startup-project %s", project.path, startup_project.path)
  local migrations = {}

  local migration_job = job.register_job({ name = "Loading migrations", on_error_text = "Failed to load migrations", on_success_text = "Migrations loaded" })
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    ---@param data table<string>
    on_stdout = function(_, data)
      -- Iterate over the output lines
      for _, value in ipairs(data) do
        -- Strip the "data: " prefix and capture the migration name
        local migration = value:match("^data:%s*(%S+)")
        if migration then
          -- Insert the stripped migration name into the migrations table
          table.insert(migrations, migration)
        end
      end
    end,
    on_exit = function(_, code)
      migration_job(code == 0)
      if code == 0 then
        local opts = {
          entry_maker = function(entry)
            return {
              display = entry,
              ordinal = entry,
              path = string.format("%s/Migrations/%s.cs", vim.fs.dirname(selections.project.path), entry),
              value = entry,
            }
          end,
        }
        require("easy-dotnet.picker").migration_picker(opts, migrations)
      end
    end,
  })
end

return M
