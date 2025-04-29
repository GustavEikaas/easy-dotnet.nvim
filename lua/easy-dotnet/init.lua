local actions = require("easy-dotnet.actions")
local debug = require("easy-dotnet.debugger")
local constants = require("easy-dotnet.constants")
local commands = require("easy-dotnet.commands")
local polyfills = require("easy-dotnet.polyfills")
local logger = require("easy-dotnet.logger")

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
  return polyfills.iter(parent):fold({}, function(cmds, name, command)
    local full_command = prefix and (prefix .. " " .. name) or name

    if command.handle then table.insert(cmds, full_command) end

    if command.subcommands then polyfills.iter(collect_commands(command.subcommands, full_command)):each(function(sub) table.insert(cmds, sub) end) end

    return cmds
  end)
end

local function present_command_picker()
  local all_commands = collect_commands(commands)
  local options = vim.tbl_map(function(i) return { display = i, value = i } end, all_commands)

  require("easy-dotnet.picker").picker(nil, options, function(selected)
    if selected and selected.value then
      vim.cmd("Dotnet " .. selected.value)
    else
      logger.info("No command selected")
    end
  end, "Select command", false)
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

local function check_picker_config(opts)
  if opts.picker == "fzf" and not (pcall(require, "fzf-lua")) then
    vim.notify("config.picker is set to fzf but fzf-lua is not installed. Using basic picker.")
  elseif opts.picker == "telescope" and not (pcall(require, "telescope")) then
    vim.notify("config.picker is set to telescope but telescope is not installed. Using basic picker.")
  end
end

---@param arg_lead string
---@param cmdline string
---@return string[]
local function complete_command(arg_lead, cmdline)
  local all_commands = collect_commands(commands)
  local args = cmdline:match(".*Dotnet[!]*%s+(.*)")
  if not args then return all_commands end
  -- Everything before arg_lead
  local pre_arg_lead = args:match("^(.*)" .. arg_lead .. "$")

  local matches = polyfills
    .iter(all_commands)
    :map(function(command)
      if pre_arg_lead ~= "" then
        local truncated_command = command:match("^" .. pre_arg_lead .. "(.*)")
        if truncated_command == nil then return nil end
        command = truncated_command
      end
      return command:find(arg_lead) ~= nil and command or nil
    end)
    :totable()

  return matches
end

local function generate_absolute_path_for_project(path, slnpath)
  local dir = vim.fs.normalize(vim.fs.dirname(slnpath))
  local res = vim.fs.normalize(polyfills.fs.joinpath(dir, vim.fs.normalize(path)))
  return res
end

M.setup = function(opts)
  local merged_opts = require("easy-dotnet.options").set_options(opts)
  define_highlights_and_signs(merged_opts)
  check_picker_config(merged_opts)

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
  end, { nargs = "?", complete = complete_command })

  if merged_opts.csproj_mappings == true then require("easy-dotnet.csproj-mappings").attach_mappings() end

  if merged_opts.fsproj_mappings == true then require("easy-dotnet.fsproj-mappings").attach_mappings() end

  if merged_opts.auto_bootstrap_namespace.enabled == true then require("easy-dotnet.cs-mappings").auto_bootstrap_namespace(merged_opts.auto_bootstrap_namespace.type) end

  if merged_opts.enable_filetypes == true then require("easy-dotnet.filetypes").enable_filetypes() end

  if merged_opts.test_runner.enable_buffer_test_execution then
    require("easy-dotnet.cs-mappings").add_test_signs()
    require("easy-dotnet.fs-mappings").add_test_signs()
  end

  polyfills.iter(collect_commands_with_handles(commands)):each(function(name, handle)
    M[name] = wrap(function(args, options) handle(args, options or require("easy-dotnet.options").options) end)
  end)

  register_legacy_functions()

  if merged_opts.background_scanning then
    --prewarm msbuild properties
    local sln = require("easy-dotnet.parsers.sln-parse")
    local path = sln.find_solution_file()
    if not path then return end

    local stdout
    local stderr
    local cmd = require("easy-dotnet.dotnet_cli").list_projects(path)
    vim.fn.jobstart(cmd, {
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data) stdout = data end,
      on_stderr = function(_, data) stderr = data end,
      on_exit = function(_, code)
        if code == 0 then
          local function trim(s) return s:match("^%s*(.-)%s*$") end
          local project_lines = {}
          for _, line in ipairs(stdout) do
            local t = trim(line)
            if t:match("%.csproj$") or t:match("%.fsproj$") then table.insert(project_lines, t) end
          end

          polyfills.iter(project_lines):each(function(proj_path)
            local project_file_path = generate_absolute_path_for_project(proj_path, path)
            require("easy-dotnet.parsers.csproj-parse").preload_msbuild_properties(project_file_path)
          end)
        else
          print("Preloading msbuild properties for " .. path .. " failed")
          vim.print(stderr)
        end
      end,
    })
  end
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
