local M = {}

---@param migration_name string
M.add_migration = function(migration_name)
  assert(migration_name, "Migration name required")
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  local cmd = string.format("dotnet ef migrations add %s --project %s --startup-project %s", migration_name, project
    .path,
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

M.remove_migration = function()
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  local cmd = string.format("dotnet ef migrations remove %s --project %s --startup-project %s", project.path,
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


M.list_migrations = function()
  local conf = require('telescope.config').values
  local selections = require("easy-dotnet.ef-core.utils").pick_projects()
  local project = selections.project
  local startup_project = selections.startup_project

  local cmd = string.format("dotnet ef migrations list --prefix-output --project %s --startup-project %s", project.path,
    startup_project.path)
  vim.notify(cmd)

  local migrations = {}

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
      if code == 0 then
        vim.notify("Success")
        local opts = {
          entry_maker = function(entry)
            return {
              display = entry,
              ordinal = entry,
              path = string.format("%s/Migrations/%s.cs", vim.fs.dirname(selections.project.path), entry),
              value = entry
            }
          end
        }
        local picker = require('telescope.pickers').new(opts, {
          prompt_title = "Migrations",
          finder = require('telescope.finders').new_table {
            results = migrations,
            entry_maker = opts.entry_maker,
          },
          sorter = require('telescope.config').values.generic_sorter({}),
          previewer = conf.grep_previewer(opts)
        })
        picker:find()
      else
        vim.notify("Failed", vim.log.levels.ERROR)
      end
    end
  })
end

return M
