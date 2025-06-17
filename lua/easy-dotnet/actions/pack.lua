local sln_parse = require("easy-dotnet.parsers.sln-parse")
local error_messages = require("easy-dotnet.error-messages")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local logger = require("easy-dotnet.logger")
local picker = require("easy-dotnet.picker")
local nuget = require("easy-dotnet.nuget")

local M = {}
---@param project DotnetProject
---@param configuration string
---@return string
local function build_and_pack_project(project, configuration)
  local co = coroutine.running()
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  client:initialize(function()
    client:msbuild_build({ targetPath = project.path, configuration = configuration }, function()
      client:msbuild_pack(project.path, configuration, function(res) coroutine.resume(co, res.result.filePath) end)
    end)
  end)
  return coroutine.yield()
end

local function select_source_and_push(path)
  vim.print("Pushing " .. path)
  local sources = nuget.get_nuget_sources_async()
  local source = picker.pick_sync(nil, sources, "Pick nuget source", false, true)

  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  client:initialize(function()
    client:nuget_push({ path }, source.name, function(i) vim.print(i) end)
  end)

  -- push_nuget_package(path, source)
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
  local path = build_and_pack_project(project, configuration)
  if push then select_source_and_push(path) end
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
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client

  client:initialize(function() client:msbuild_pack(project.path, configuration) end)
end

--TODO: add passthrough args
M.push = function()
  local configuration = "Release"
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

  local path = build_and_pack_project(project, configuration)
  select_source_and_push(path)
end

return M
