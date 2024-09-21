local M = {}

local options = require("easy-dotnet.options")
local actions = require("easy-dotnet.actions")
local secrets = require("easy-dotnet.secrets")
local debug = require("easy-dotnet.debugger")

local function merge_tables(table1, table2)
  local merged = {}
  for k, v in pairs(table1) do
    merged[k] = v
  end
  for k, v in pairs(table2) do
    merged[k] = v
  end
  return merged
end

---@param argument string|nil
local function args_handler(argument)
  if not argument then
    return nil
  end
  local loweredArgument = argument:lower()
  if loweredArgument == "release" then
    return "-c release"
  elseif loweredArgument == "debug" then
    return "-c debug"
  else
    vim.notify("Unknown argument to dotnet build " .. argument, vim.log.levels.WARN)
  end
end

M.setup = function(opts)
  local merged_opts = merge_tables(options, opts or {})
  vim.api.nvim_set_hl(0, "EasyDotnetPackage", {
    fg = '#000000',
    bg = '#ffffff',
    bold = true,
    italic = false,
    underline = false,
  })
  local commands = {
    secrets = function()
      secrets.edit_secrets_picker(merged_opts.secrets.path)
    end,
    run = function(args)
      actions.run(merged_opts.terminal, false, args_handler(args[2]) or "")
    end,
    test = function(args)
      actions.test(merged_opts.terminal, false, args_handler(args[2]) or "")
    end,
    restore = function()
      actions.restore(merged_opts.terminal)
    end,
    build = function(args)
      actions.build(merged_opts.terminal, false, args_handler(args[2]) or "")
    end,
    testrunner = function()
      require("easy-dotnet.test-runner.runner").runner(merged_opts.test_runner, merged_opts.get_sdk_path())
    end,
    outdated = function()
      require("easy-dotnet.outdated.outdated").outdated()
    end,
    clean = function()
      require("easy-dotnet.actions.clean").clean_solution()
    end,
    new = function()
      require("easy-dotnet.actions.new").new()
    end,
    ef = function(args)
      local ef_handler = function()
        local sub = args[2]
        if sub == "database" then
          if args[3] == "update" then
            M.entity_framework.database.database_update(args[4])
          elseif args[3] == "drop" then
            M.entity_framework.database.database_drop()
          end
        elseif sub == "migrations" then
          if args[3] == "add" then
            M.entity_framework.migration.add_migration(args[4])
          elseif args[3] == "remove" then
            M.entity_framework.migration.remove_migration()
          elseif args[3] == "list" then
            M.entity_framework.migration.list_migrations()
          end
        else
          vim.notify("Unknown command")
        end
      end
      local co = coroutine.create(ef_handler)

      coroutine.resume(co)
    end
  }

  ---@return table<string>
  local function split_by_whitespace(str)
    local words = {}
    for word in str:gmatch("%S+") do
      table.insert(words, word)
    end
    return words
  end

  vim.api.nvim_create_user_command('Dotnet',
    function(commandOpts)
      local args = split_by_whitespace(commandOpts.fargs[1])
      local subcommand = args[1]
      local func = commands[subcommand]
      if func then
        func(args)
      else
        print("Invalid subcommand:", subcommand)
      end
    end,
    {
      nargs = "?",
      complete = function()
        local completion = {}
        for key, _ in pairs(commands) do
          table.insert(completion, key)
        end
        return completion
      end,
    }
  )

  if merged_opts.csproj_mappings == true then
    require("easy-dotnet.csproj-mappings").attach_mappings()
  end

  if merged_opts.auto_bootstrap_namespace == true then
    require("easy-dotnet.cs-mappings").auto_bootstrap_namespace()
  end

  M.test_project = commands.test
  M.test_default = function()
    actions.test(merged_opts.terminal, true)
  end
  M.test_solution = function()
    actions.test_solution(merged_opts.terminal)
  end
  M.watch_tests = function()
    actions.test_watcher()
  end
  M.run_project = commands.run

  M.run_default = function()
    actions.run(merged_opts.terminal, true, "")
  end

  M.build_default_quickfix = function(dotnet_args)
    actions.build_quickfix(true, dotnet_args)
  end

  M.build_quickfix = function(dotnet_args)
    actions.build_quickfix(false, dotnet_args)
  end

  M.build_default = function()
    actions.build(merged_opts.terminal, true)
  end

  M.restore = commands.restore
  M.secrets = commands.secrets
  M.build = commands.build
  M.clean = commands.clean
  M.build_solution = function()
    actions.build_solution(merged_opts.terminal)
  end
end

M.get_debug_dll = debug.get_debug_dll
M.get_environment_variables = debug.get_environment_variables

M.experimental = {
  start_debugging_test_project = debug.start_debugging_test_project
}

M.entity_framework = {
  database = require("easy-dotnet.ef-core.database"),
  migration = require("easy-dotnet.ef-core.migration")
}

M.is_dotnet_project = function()
  local project_files = require("easy-dotnet.parsers.sln-parse").find_solution_file() or
      require("easy-dotnet.parsers.csproj-parse").find_project_file()
  return project_files ~= nil
end

return M
