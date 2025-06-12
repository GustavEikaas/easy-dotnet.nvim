local sln_parse = require("easy-dotnet.parsers.sln-parse")
local error_messages = require("easy-dotnet.error-messages")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local logger = require("easy-dotnet.logger")
local picker = require("easy-dotnet.picker")
local async = require("easy-dotnet.async-utils")
local spinner = require("easy-dotnet.ui-modules.spinner")
local nuget = require("easy-dotnet.nuget")

local function file_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "file"
end

local M = {}

local function build_project(project, configuration)
  local build_spinner = spinner.new()
  build_spinner:start_spinner("Building...")
  local build_res = async.await(async.job_run_async)({ "dotnet", "build", project.path, "-c", configuration })
  if not build_res.success then
    vim.print(build_res.stderr)
    build_spinner:stop_spinner("Build failed", vim.log.levels.ERROR)
    return
  else
    build_spinner:stop_spinner("Build success")
  end
end

local function pack_project(project, configuration)
  local pack_spinner = spinner.new()
  pack_spinner:start_spinner("Packing...")
  local pack_res = async.await(async.job_run_async)({ "dotnet", "pack", project.path, "-c", configuration })
  if not pack_res.success then
    vim.print(pack_res.stderr)
    pack_spinner:stop_spinner("Packing failed", vim.log.levels.ERROR)
    return
  else
    pack_spinner:stop_spinner("Packing success")
  end
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
    vim.notify("Failed to get MSBuild properties", vim.log.levels.ERROR)
    return
  end

  local json = table.concat(res.stdout, "")
  local ok, props = pcall(vim.fn.json_decode, json)
  if not ok or not props then
    vim.notify("Failed to parse MSBuild JSON output", vim.log.levels.ERROR)
    return
  end

  local out_dir = vim.fs.normalize(props.Properties.PackageOutputPath)
  local id = props.Properties.PackageId
  local version = props.Properties.Version
  if not id or not version then
    vim.notify("Missing PackageId or Version from MSBuild output", vim.log.levels.ERROR)
    return
  end

  local package_path = vim.fs.joinpath(vim.fs.dirname(project.path), vim.fs.joinpath(out_dir, id .. "." .. version .. ".nupkg"))

  if not file_exists(package_path) then error(string.format("No nuget package at %s was found", package_path)) end

  local push_spinner = spinner.new()
  push_spinner:start_spinner("Pushing...")
  local push_res = async.await(async.job_run_async)({ "dotnet", "nuget", "push", package_path, "--source", source.name })
  if not push_res.success then
    vim.print(push_res.stderr)
    push_spinner:stop_spinner("Pushing failed", vim.log.levels.ERROR)
    return
  else
    push_spinner:stop_spinner("Pushed to nuget feed!")
  end
end

---@param project DotnetProject
---@param configuration string
local function build_and_pack_project(project, configuration)
  build_project(project, configuration)
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
