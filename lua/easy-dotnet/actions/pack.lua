local sln_parse = require("easy-dotnet.parsers.sln-parse")
local error_messages = require("easy-dotnet.error-messages")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local logger = require("easy-dotnet.logger")
local picker = require("easy-dotnet.picker")
local async = require("easy-dotnet.async-utils")
local job = require("easy-dotnet.ui-modules.jobs")
local nuget = require("easy-dotnet.nuget")

local function file_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "file"
end

---@param cmd string[] The command run
---@param res { stdout: string[], stderr: string[], success: boolean }
---@return nil | { command: string, stdout?: string[], stderr?: string[] }
local function format_command_failure(cmd, res)
  if res.success then return nil end

  local function is_only_whitespace(lines) return vim.tbl_isempty(lines) or (#lines == 1 and vim.trim(lines[1]) == "") end

  local stdout_valid = not is_only_whitespace(res.stdout)
  local stderr_valid = not is_only_whitespace(res.stderr)

  return {
    command = table.concat(cmd, " "),
    stdout = stdout_valid and res.stdout or nil,
    stderr = stderr_valid and res.stderr or nil,
  }
end

local M = {}

local function build_project(project, configuration)
  local build_job = job.register_job({ name = "Building...", on_error_text = "Build failed", on_success_text = "Build success" })
  local cmd = { "dotnet", "build", project.path, "-c", configuration }
  local build_res = async.await(async.job_run_async)(cmd)
  build_job(build_res.success, format_command_failure(cmd, build_res))
  return build_res.success
end

local function pack_project(project, configuration)
  local pack_job = job.register_job({ name = "Packing...", on_error_text = "Packing failed", on_success_text = "Packing success" })
  local cmd = { "dotnet", "pack", project.path, "-c", configuration }
  local pack_res = async.await(async.job_run_async)(cmd)
  pack_job(pack_res.success, format_command_failure(cmd, pack_res))
end

---@param project DotnetProject
---@param configuration string
---@param source NugetSource
local function push_nuget_package(project, configuration, source)
  local res = async.await(async.job_run_async)({
    "dotnet",
    "msbuild",
    project.path,
    "-getProperty:PackageOutputPath",
    "-getProperty:PackageId",
    "-getProperty:Version",
    "-p:Configuration=" .. configuration,
  })

  if not res.success then
    vim.print(res.stderr)
    error("Failed to get MSBuild properties")
  end

  local json = table.concat(res.stdout, "")
  local ok, props = pcall(vim.fn.json_decode, json)
  if not ok or not props then error("Failed to parse MSBuild JSON output") end

  local out_dir = vim.fs.normalize(props.Properties.PackageOutputPath)
  if not require("easy-dotnet.extensions").isWindows() then
      out_dir = string.gsub(out_dir, "\\", "/")
  end

  local id = props.Properties.PackageId
  local version = props.Properties.Version
  if not id or not version then error("Missing PackageId or Version from MSBuild output") end

  local package_path = vim.fs.joinpath(vim.fs.dirname(project.path), vim.fs.joinpath(out_dir, id .. "." .. version .. ".nupkg"))

  if not file_exists(package_path) then error(string.format("No nuget package at %s was found", package_path)) end

  local push_job = job.register_job({ name = "Pushing...", on_error_text = "Pushing failed", on_success_text = "Pushed to nuget feed!" })
  local cmd = { "dotnet", "nuget", "push", package_path, "--source", source.name }
  local push_res = async.await(async.job_run_async)(cmd)
  push_job(push_res.success, format_command_failure(cmd, push_res))
end

---@param project DotnetProject
---@param configuration string
local function build_and_pack_project(project, configuration)
  local res = build_project(project, configuration)
  if res == false then return end
  pack_project(project, configuration)
end

---@param project DotnetProject
---@param configuration string
local function select_source_and_push(project, configuration)
  local sources = nuget.get_nuget_sources_async()
  local source = picker.pick_sync(nil, sources, "Pick nuget source", false, true)

  push_nuget_package(project, configuration, source)
end

local function csproj_fallback(push)
  local configuration = "release"
  local csproj_path = csproj_parse.find_project_file()
  if csproj_path == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end
  local project = csproj_parse.get_project_from_project_file(csproj_path)
  if not project.isNugetPackage then error(project.name .. " is not a nuget package") end
  build_and_pack_project(project, configuration)
  if push then select_source_and_push(project, configuration) end
end

--TODO: add passthrough args
M.pack = function()
  local configuration = "release"
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    csproj_fallback(false)
    return
  end
  local nuget_packages = sln_parse.get_projects_from_sln(solution_file_path, function(project) return project.isNugetPackage end)
  if #nuget_packages == 0 then
    logger.warn("No nuget packages found in solution")
    return
  end

  local project = picker.pick_sync(nil, nuget_packages, "Pack projects", false, true)

  build_and_pack_project(project, configuration)
end

--TODO: add passthrough args
M.push = function()
  local configuration = "release"
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    csproj_fallback(true)
    return
  end
  local nuget_packages = sln_parse.get_projects_from_sln(solution_file_path, function(project) return project.isNugetPackage end)

  if #nuget_packages == 0 then
    logger.warn("No nuget packages found in solution")
    return
  end

  local project = picker.pick_sync(nil, nuget_packages, "Pack projects", false, true)

  build_and_pack_project(project, configuration)
  select_source_and_push(project, configuration)
end

return M
