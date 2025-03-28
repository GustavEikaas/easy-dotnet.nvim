local M = {}
local picker = require("easy-dotnet.picker")
local error_messages = require("easy-dotnet.error-messages")
local logger = require("easy-dotnet.logger")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local polyfills = require("easy-dotnet.polyfills")

---@param use_default boolean
---@return DotnetProject, string | nil
local function pick_project(use_default)
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    local csproject_path = csproj_parse.find_project_file()
    if not csproject_path then logger.error(error_messages.no_runnable_projects_found) end
    local project = csproj_parse.get_project_from_project_file(csproject_path)
    return project, nil
  end

  local default = default_manager.check_default_project(solution_file_path, "debug")
  if default ~= nil and use_default == true then return default, solution_file_path end

  local projects = polyfills.tbl_filter(function(i) return i.runnable == true end, sln_parse.get_projects_from_sln(solution_file_path))

  if #projects == 0 then
    logger.error(error_messages.no_runnable_projects_found)
    return
  end
  local project = picker.pick_sync(nil, projects, "Debug project")
  if not project then
    logger.error("No project selected")
    return
  end
  default_manager.set_default_project(project, solution_file_path, "debug")
  return project, solution_file_path
end

M.get_debug_dll = function(default)
  local sln_file = sln_parse.find_solution_file()
  local result = sln_file ~= nil and M.get_dll_for_solution_project(default) or M.get_dll_for_project()
  local relative_dll_path = polyfills.fs.joinpath(vim.fn.getcwd(), result.dll)
  local relative_project_path = polyfills.fs.joinpath(vim.fn.getcwd(), result.project)
  return {
    dll_path = result.dll,
    project_path = result.project,
    project_name = result.projectName,
    relative_dll_path = relative_dll_path,
    relative_project_path = relative_project_path,
  }
end

local function run_job_sync(cmd)
  local result = {}
  local co = coroutine.running()

  vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      for _, line in ipairs(data) do
        local match = string.match(line, "Process Id: (%d+)")
        if match then
          result.process_id = tonumber(match)
          coroutine.resume(co)
          return
        end
      end
    end,
  })

  coroutine.yield()

  return result
end

---@param path string
local function start_test_process(path)
  local command = string.format("dotnet test %s --environment=VSTEST_HOST_DEBUG=1", path)
  local res = run_job_sync(command)
  if not res.process_id then error("Failed to start process") end
  return res.process_id
end

M.start_debugging_test_project = function(project_path)
  local sln_file = sln_parse.find_solution_file()
  assert(sln_file, "Failed to find a solution file")
  local projects = sln_parse.get_projects_from_sln(sln_file)
  local test_projects = polyfills.tbl_filter(function(i) return i.isTestProject end, projects)
  local test_project = project_path and project_path or picker.pick_sync(nil, test_projects, "Pick test project").path
  assert(test_project, "No project selected")

  local process_id = start_test_process(test_project)
  return {
    process_id = process_id,
    cwd = vim.fs.dirname(test_project),
  }
end

M.get_environment_variables = function(project_name, relative_project_path)
  local launchSettings = polyfills.fs.joinpath(relative_project_path, "Properties", "launchSettings.json")

  local stat = vim.loop.fs_stat(launchSettings)
  if stat == nil then return nil end

  local success, result = pcall(vim.fn.json_decode, vim.fn.readfile(launchSettings, ""))
  if not success then return nil, "Error parsing JSON: " .. result end

  local launchProfile = result.profiles[project_name]

  if launchProfile == nil then return nil end

  --TODO: Is there more env vars in launchsetttings.json?
  launchProfile.environmentVariables["ASPNETCORE_URLS"] = launchProfile.applicationUrl
  return launchProfile.environmentVariables
end

M.get_dll_for_solution_project = function(default)
  if default == nil then default = false end
  local project = pick_project(default)

  local path = vim.fs.dirname(project.path)
  return {
    dll = project.get_dll_path(),
    project = path,
    projectName = project.name,
  }
end

M.get_dll_for_project = function()
  local project_file_path = csproj_parse.find_project_file()
  if project_file_path == nil then error("No project or solution file found") end
  local project = csproj_parse.get_project_from_project_file(project_file_path)
  local path = vim.fs.dirname(project.path)
  return {
    projectName = project.name,
    dll = project.get_dll_path(),
    project = path,
  }
end

return M
