local M = {}
local picker = require("easy-dotnet.picker")
local error_messages = require("easy-dotnet.error-messages")
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser

---@return easy-dotnet.Project.Project | nil
local pick_project_without_solution = function()
  local csproject_path = csproj_parse.find_project_file()
  if not csproject_path then
    logger.error(error_messages.no_projects_found)
    return
  end
  local project = csproj_parse.get_project_from_project_file(csproject_path)
  local project_framework = picker.pick_sync(nil, project.get_all_runtime_definitions(), "Run project")
  return project_framework
end
---Prompts the user to select a testable DotnetProject (with framework),
---optionally using a default if configured and allowed.
---
---This function looks for a solution file, checks if a default testable project
---is defined, and if so, uses it (if `use_default` is `true`). Otherwise, it
---presents the user with a picker of all testable projects and their frameworks.
---If no solution file is found, falls back to picking a project without one.
---
---If a project is selected, the default is updated for future invocations.
---
---@param use_default boolean: If true, allows using the stored default project if available.
---@return easy-dotnet.Project.Project | nil: The selected or default DotnetProject.
---@return string|nil: The path to the solution file, or nil if no solution is used.
local function pick_project_framework_or_solution(use_default)
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.try_get_selected_solution_file()
  if solution_file_path == nil then return pick_project_without_solution(), nil end

  local default = default_manager.check_default_project(solution_file_path, "test")

  if default ~= nil and use_default == true then
    if default.type == "solution" then return nil, solution_file_path end
    return default.project, solution_file_path
  end

  local projects_with_sln = sln_parse.get_projects_and_frameworks_flattened_from_sln(solution_file_path, function(i) return i.isTestProject == true end)
  table.insert(projects_with_sln, { display = "Solution" })

  if #projects_with_sln == 0 then error(error_messages.no_test_projects_found) end
  ---@type easy-dotnet.Project.Project
  local project_framework = picker.pick_sync(nil, projects_with_sln, "Test project")
  if not project_framework then
    logger.error("No project selected")
    return
  end

  if project_framework.display:lower() == "solution" then
    ---@diagnostic disable-next-line: missing-fields
    default_manager.set_default_project({ name = "Solution" }, solution_file_path, "test")
    return nil, solution_file_path
  end

  default_manager.set_default_project(project_framework, solution_file_path, "test")
  return project_framework, solution_file_path
end

---Tests a dotnet solution with the given arguments using the terminal runner.
---
---This is a wrapper around `term(path, "test", args)`.
---
---@param args string: Additional arguments to pass to `dotnet test`.
---@param term function: terminal callback
local function test_solution(args, term)
  term = term or require("easy-dotnet.options").options.terminal
  args = args or ""

  current_solution.get_or_pick_solution(function(solution_path)
    solution_path = solution_path or csproj_parse.find_project_file()

    if solution_path == nil then
      logger.error(error_messages.no_project_definition_found)
      return
    end

    local cmd = string.format("dotnet test %s", solution_path)

    term(solution_path, "test", args or "", { cmd = cmd })
  end)
end

---Tests a dotnet project with the given arguments using the terminal runner.
---
---This is a wrapper around `term(path, "test", args)`.
---
---@param project easy-dotnet.Project.Project: The full path to the Dotnet project.
---@param args string: Additional arguments to pass to `dotnet test`.
---@param term function: terminal callback
local function test_project(project, args, term)
  args = args or ""

  if project.name:lower() == "solution" then
    test_solution(args, term)
    return
  end

  local arg = ""
  if project.type == "project_framework" then arg = arg .. " --framework " .. project.msbuild_props.targetFramework end
  local cmd = project.msbuild_props.testCommand
  term(project.path, "test", arg .. " " .. args, { cmd = cmd })
end

---@param term function
local function csproj_fallback_test(term, args)
  local project = pick_project_without_solution()
  test_project(project, args, term)
end

---@param use_default boolean
---@param args string|nil
M.run_test_picker = function(term, use_default, args)
  term = term or require("easy-dotnet.options").options.terminal
  use_default = use_default or false
  args = args or ""

  current_solution.get_or_pick_solution(function(solution_path)
    if solution_path == nil then
      csproj_fallback_test(term, args)
      return
    end

    local project, sln = pick_project_framework_or_solution(use_default)
    if project == nil and sln ~= nil then
      test_solution(args, term)
    elseif project ~= nil then
      test_project(project, args, term)
    end
  end)
end

M.test_solution = function(term, args) test_solution(args, term) end

M.test_watcher = function(icons)
  local dn = require("easy-dotnet.parsers").sln_parser
  local slnPath = dn.try_get_selected_solution_file()
  local projects = dn.get_projects_from_sln(slnPath)
  local testProjects = {}
  for _, value in pairs(projects) do
    if value.isTestProject then table.insert(testProjects, value) end
  end
  local header_test_message = icons.test .. " Testing..." .. "\n\n"

  local testMessage = header_test_message
  for _, value in pairs(testProjects) do
    testMessage = testMessage .. "\n" .. value.name
  end

  local state = {}

  for _, value in pairs(testProjects) do
    table.insert(state, { state = "pending", name = value.name })
  end

  local notification = nil
  local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }

  local function update_message(i)
    local message = header_test_message
    for _, value in pairs(state) do
      local icon = spinner_frames[i % #spinner_frames + 1]
      if value.state == "failed" then
        icon = icons.failed
      elseif value.state == "success" then
        icon = icons.success
      end
      message = message .. "\n" .. icon .. " " .. value.name
    end
    notification = vim.notify(message, "info", { replace = notification })
  end

  update_message(1)
  local i = 1
  for _, value in pairs(testProjects) do
    vim.fn.jobstart("dotnet test " .. value.path, {
      on_exit = function(_, b, _)
        local curr = nil
        for _, stateValue in pairs(state) do
          if value.name == stateValue.name then curr = stateValue end
        end
        if curr == nil then error("blaaa") end
        if b == 0 then
          curr.state = "success"
        else
          curr.state = "failed"
        end
        update_message(1)
      end,
      on_stdout = function()
        i = i + 1
        update_message(i)
      end,
    })
  end
end

return M
