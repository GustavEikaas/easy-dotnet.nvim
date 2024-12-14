local M = {}

local function wrap(callback)
  return function(...)
    -- Check if we are already in a coroutine
    if coroutine.running() then
      -- If already in a coroutine, call the callback directly
      callback(...)
    else
      -- If not, create a new coroutine and resume it
      local co = coroutine.create(callback)
      coroutine.resume(co, ...)
    end
  end
end

local options = require("easy-dotnet.options")
local actions = require("easy-dotnet.actions")
local secrets = require("easy-dotnet.secrets")
local debug = require("easy-dotnet.debugger")

local function merge_tables(default_options, user_options)
  return vim.tbl_deep_extend("keep", user_options, default_options)
end

local function slice(array, start_index, end_index)
  local result = {}
  table.move(array, start_index, end_index, 1, result)
  return result
end


---@param arguments table<string>|nil
local function args_handler(arguments)
  if not arguments or #arguments == 0 then
    return ""
  end
  local loweredArgument = arguments[1]:lower()
  if loweredArgument == "release" then
    return string.format("-c release %s", args_handler(slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "debug" then
    return string.format("-c debug %s", args_handler(slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "-c" then
    local flag = string.format("-c %s", #arguments >= 2 and arguments[2] or "")
    return string.format("%s %s", flag, args_handler(slice(arguments, 3, #arguments) or ""))
  elseif loweredArgument == "--no-build" then
    return string.format("--no-build %s", args_handler(slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "--no-restore" then
    return string.format("--no-restore %s", args_handler(slice(arguments, 2, #arguments) or ""))
  else
    vim.notify("Unknown argument to dotnet build " .. loweredArgument, vim.log.levels.WARN)
  end
end

local function define_highlights_and_signs(merged_opts)
  local constants = require("easy-dotnet.constants")
  vim.api.nvim_set_hl(0, "EasyDotnetPackage", {
    fg = '#000000',
    bg = '#ffffff',
    bold = true,
    italic = false,
    underline = false,
  })

  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerSolution, { link = "Question" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerProject, { link = "Character" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerTest, { link = "Normal" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerSubcase, { link = "Conceal" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerDir, { link = "Directory" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerPackage, { link = "Include" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerPassed, { link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerFailed, { link = "DiagnosticError" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerRunning, { link = "DiagnosticWarn" })

  local icons = merged_opts.test_runner.icons
  vim.fn.sign_define(constants.signs.EasyDotnetTestSign, { text = icons.test, texthl = "Character" })
  vim.fn.sign_define(constants.signs.EasyDotnetTestPassed, { text = icons.passed, texthl = "EasyDotnetTestRunnerPassed" })
  vim.fn.sign_define(constants.signs.EasyDotnetTestFailed, { text = icons.failed, texthl = "EasyDotnetTestRunnerFailed" })
  vim.fn.sign_define(constants.signs.EasyDotnetTestSkipped, { text = icons.skipped })
  vim.fn.sign_define(constants.signs.EasyDotnetTestError, { text = "E", texthl = "EasyDotnetTestRunnerFailed" })
end

M.setup = function(opts)
  local merged_opts = merge_tables(options, opts or {})
  define_highlights_and_signs(merged_opts)
  local commands = {
    solution = function(args)
      local sub = args[2]
      if sub == "select" then
        local function handler()
          local files = require("easy-dotnet.parsers.sln-parse").get_solutions()
          local old = nil
          for _, value in ipairs(files) do
            local file = require("easy-dotnet.default-manager").try_get_cache_file(value)
            if file then
              old = value
            end
          end

          local sln = require("easy-dotnet.parsers.sln-parse").find_solution_file(true)
          if sln == nil then
            print("No solutions found")
          end
          require("easy-dotnet.default-manager").set_default_solution(old, sln)
        end
        local co = coroutine.create(handler)
        coroutine.resume(co)
      else
        error("unknown command")
      end
    end,
    secrets = function()
      secrets.edit_secrets_picker(merged_opts.secrets.path)
    end,
    run = function(args)
      local extra_args = slice(args, 2, #args)
      actions.run(merged_opts.terminal, false, args_handler(extra_args))
    end,
    test = function(args)
      local extra_args = slice(args, 2, #args)
      actions.test(merged_opts.terminal, false, args_handler(extra_args))
    end,
    restore = function()
      actions.restore(merged_opts.terminal)
    end,
    build = function(args)
      local extra_args = slice(args, 2, #args)
      actions.build(merged_opts.terminal, false, args_handler(extra_args))
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
    reset = function()
      local dir = require("easy-dotnet.constants").get_data_directory()
      require("plenary.path"):new(dir):rm({ recursive = true })
      vim.notify("Cached files deleted")
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

  if merged_opts.fsproj_mappings == true then
    require("easy-dotnet.fsproj-mappings").attach_mappings()
  end

  if merged_opts.auto_bootstrap_namespace == true then
    require("easy-dotnet.cs-mappings").auto_bootstrap_namespace()
  end

  if merged_opts.test_runner.enable_buffer_test_execution then
    require("easy-dotnet.cs-mappings").add_test_signs()
    require("easy-dotnet.fs-mappings").add_test_signs()
  end

  if merged_opts.enable_filetypes == true then
    require('easy-dotnet.filetypes').enable_filetypes()
  end

  M.test_project = commands.test
  M.test_default = function()
    actions.test(merged_opts.terminal, true)
  end
  M.test_solution = function()
    actions.test_solution(merged_opts.terminal)
  end
  M.watch_tests = function()
    actions.test_watcher(merged_opts.test_runner.icons)
  end
  M.run_project = commands.run
  M.run_with_profile = function(use_default)
    local function co_wrapper()
      actions.run_with_profile(merged_opts.terminal, use_default == nil and false or use_default)
    end

    local co = coroutine.create(co_wrapper)
    coroutine.resume(co)
  end

  M.testrunner_refresh = function(args)
    local function co_wrapper()
      require("easy-dotnet.test-runner.runner").refresh(merged_opts.test_runner, merged_opts.get_sdk_path(), args)
    end

    local co = coroutine.create(co_wrapper)
    coroutine.resume(co)
  end

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

  M.create_new_item = wrap(function(...)
    require("easy-dotnet.actions.new").create_new_item(...)
  end)

  M.secrets = commands.secrets
  M.build = commands.build
  M.clean = commands.clean
  M.build_solution = function()
    actions.build_solution(merged_opts.terminal)
  end
end

M.get_debug_dll = debug.get_debug_dll
M.get_environment_variables = debug.get_environment_variables

M.try_get_selected_solution = function()
  local file = require("easy-dotnet.parsers.sln-parse").try_get_selected_solution_file()
  return {
    basename = vim.fs.basename(file),
    path = file
  }
end

M.experimental = {
  start_debugging_test_project = debug.start_debugging_test_project
}

M.entity_framework = {
  database = require("easy-dotnet.ef-core.database"),
  migration = require("easy-dotnet.ef-core.migration")
}

M.is_dotnet_project = function()
  local project_files = require("easy-dotnet.parsers.sln-parse").get_solutions() or
      require("easy-dotnet.parsers.csproj-parse").find_project_file()
  return project_files ~= nil
end

M.package_completion_source = require("easy-dotnet.csproj-mappings").package_completion_cmp

return M
