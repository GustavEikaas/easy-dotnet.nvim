local actions = require("easy-dotnet.actions")
local debug = require("easy-dotnet.debugger")
local constants = require("easy-dotnet.constants")
local commands = require("easy-dotnet.commands")
local polyfills = require("easy-dotnet.polyfills")
local logger    = require("easy-dotnet.logger")

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
      local s = ...
      local handle = function()
        local success, err = coroutine.resume(co, s)
        if not success then print("Coroutine failed: " .. err) end
      end
      handle()
    end
  end
end
local function collect_commands_with_handles(parent, prefix)
  return polyfills.iter(parent):fold({}, function(command_handles, name, command)
    local full_command = prefix and (prefix .. "_" .. name) or name

    if command.handle then command_handles[full_command] = command.handle end

    if command.subcommands then polyfills.iter(collect_commands_with_handles(command.subcommands, full_command)):each(function(sub_name, sub_handle) command_handles[sub_name] = sub_handle end) end

    return command_handles
  end)
end

local function collect_commands(parent, prefix)
  return polyfills.iter(parent):fold({}, function(commands, name, command)
    local full_command = prefix and (prefix .. " " .. name) or name

    if command.handle then table.insert(commands, full_command) end

    if command.subcommands then polyfills.iter(collect_commands(command.subcommands, full_command)):each(function(sub) table.insert(commands, sub) end) end

    return commands
  end)
end

local function present_command_picker()
  local all_commands = collect_commands(commands)

  vim.ui.select(all_commands, { prompt = "Select a Dotnet Command" }, function(selected)
    if selected then
      vim.cmd("Dotnet " .. selected)
    else
      logger.info("No command selected")
    end
  end)
end

local function define_highlights_and_signs(merged_opts)
  vim.api.nvim_set_hl(0, "EasyDotnetPackage", {
    fg = "#000000",
    bg = "#ffffff",
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

local register_legacy_functions = function()
  ---Deprecated prefer dotnet.test instead
  ---@deprecated prefer dotnet.test instead
  M.test_project = function() require("easy-dotnet.commands").test.handle({}, require("easy-dotnet.options").options) end

  ---@deprecated I suspect this is not used as the testrunner seems to be mainly used, if this were to live on it should sync with testrunner
  M.watch_tests = function() actions.test_watcher(require("easy-dotnet.options").options.test_runner.icons) end

  ---Deprecated prefer dotnet.run instead
  ---@deprecated prefer dotnet.run instead
  M.run_with_profile = function(use_default)
    wrap(function() actions.run_with_profile(require("easy-dotnet.options").options.terminal, use_default == nil and false or use_default) end)()
  end
end

---@return table<string>
local function split_by_whitespace(str) return str and polyfills.iter(str:gmatch("%S+")):totable() or {} end

local function traverse_subcommands(args, parent)
  if next(args) then
    local subcommand = parent.subcommands and parent.subcommands[args[1]]
    if subcommand then
      traverse_subcommands(vim.list_slice(args, 2, #args), subcommand)
    elseif parent.passthrough then
      parent.handle(args, require("easy-dotnet.options").options)
    else
      print("Invalid subcommand:", args[1])
    end
  elseif parent.handle then
    parent.handle(args, require("easy-dotnet.options").options)
  else
    local required = polyfills.tbl_keys(parent.subcommands)
    print("Missing required argument " .. vim.inspect(required))
  end
end

M.setup = function(opts)
  local merged_opts = require("easy-dotnet.options").set_options(opts)
  define_highlights_and_signs(merged_opts)

  vim.api.nvim_create_user_command("Dotnet", function(commandOpts)
    local args = split_by_whitespace(commandOpts.fargs[1])
    local command = args[1]
    if not command then
      present_command_picker()
      return
    end
    local subcommand = commands[command]
    if subcommand then
      wrap(function() traverse_subcommands(vim.list_slice(args, 2, #args), subcommand) end)()
    else
      print("Invalid subcommand:", command)
    end
  end, { nargs = "?" })

  if merged_opts.csproj_mappings == true then require("easy-dotnet.csproj-mappings").attach_mappings() end

  if merged_opts.fsproj_mappings == true then require("easy-dotnet.fsproj-mappings").attach_mappings() end

  if merged_opts.auto_bootstrap_namespace.enabled == true then require("easy-dotnet.cs-mappings").auto_bootstrap_namespace(merged_opts.auto_bootstrap_namespace.type) end

  if merged_opts.test_runner.enable_buffer_test_execution then
    require("easy-dotnet.cs-mappings").add_test_signs()
    require("easy-dotnet.fs-mappings").add_test_signs()
  end

  polyfills.iter(collect_commands_with_handles(commands)):each(function(name, handle)
    M[name] = wrap(function(args, options) handle(args, options or require("easy-dotnet.options").options) end)
  end)

  register_legacy_functions()
end

M.create_new_item = wrap(function(...) require("easy-dotnet.actions.new").create_new_item(...) end)

M.get_debug_dll = debug.get_debug_dll
M.get_environment_variables = debug.get_environment_variables

M.try_get_selected_solution = function()
  local file = require("easy-dotnet.parsers.sln-parse").try_get_selected_solution_file()
  return {
    basename = vim.fs.basename(file),
    path = file,
  }
end

M.experimental = {
  start_debugging_test_project = debug.start_debugging_test_project,
}

M.entity_framework = {
  database = require("easy-dotnet.ef-core.database"),
  migration = require("easy-dotnet.ef-core.migration"),
}

M.is_dotnet_project = function()
  local project_files = require("easy-dotnet.parsers.sln-parse").get_solutions() or require("easy-dotnet.parsers.csproj-parse").find_project_file()
  return project_files ~= nil
end

M.package_completion_source = require("easy-dotnet.csproj-mappings").package_completion_cmp

return M
