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
    run = function()
      actions.run(merged_opts.terminal)
    end,
    test = function()
      actions.test(merged_opts.terminal)
    end,
    restore = function()
      actions.restore(merged_opts.terminal)
    end,
    build = function()
      actions.build(merged_opts.terminal)
    end,
    testrunner = function()
      require("easy-dotnet.test-runner.runner").runner(opts.test_runner)
    end,
    outdated = function()
      require("easy-dotnet.outdated.outdated").outdated()
    end
  }

  vim.api.nvim_create_user_command('Dotnet',
    function(commandOpts)
      local subcommand = commandOpts.fargs[1]
      local func = commands[subcommand]
      if func then
        func()
      else
        print("Invalid subcommand:", subcommand)
      end
    end,
    {
      nargs = 1,
      complete = function()
        local completion = {}
        for key, _ in pairs(commands) do
          table.insert(completion, key)
        end
        return completion
      end,
    }
  )

  M.test_project = commands.test
  M.test_solution = function()
    actions.test_solution(merged_opts.terminal)
  end
  M.watch_tests = function()
    actions.test_watcher()
  end
  M.run_project = commands.run
  M.restore = commands.restore
  M.secrets = commands.secrets
  M.build = commands.build
  M.build_solution = function()
    actions.build_solution(merged_opts.terminal)
  end
  M.build_quickfix = actions.build_quickfix
end

M.get_debug_dll = debug.get_debug_dll
M.get_environment_variables = debug.get_environment_variables

return M
