local M = {}

local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local polyfills = require("easy-dotnet.polyfills")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local picker = require("easy-dotnet.picker")
local logger = require("easy-dotnet.logger")
local messages = require("easy-dotnet.error-messages")
local job = require("easy-dotnet.ui-modules.jobs")

local function list_reverse(tbl)
  local rev = {}
  for i = #tbl, 1, -1 do
    table.insert(rev, tbl[i])
  end
  return rev
end

---@param allow_prerelease boolean
local function get_all_versions(package, allow_prerelease)
  local co = coroutine.running()

  client:initialize(function()
    client.nuget:nuget_get_package_versions(package, nil, allow_prerelease, function(i) coroutine.resume(co, list_reverse(i)) end)
  end)
  return coroutine.yield()
end

---@return string
local function get_project()
  local sln_file_path = sln_parse.find_solution_file()
  if not sln_file_path then
    local proj = csproj_parse.find_project_file()
    if not proj then
      logger.error(messages.no_project_definition_found)
      error("")
    end
    return proj
  end
  local projects = sln_parse.get_projects_from_sln(sln_file_path)
  return picker.pick_sync(nil, projects, "Select a project", true).path
end

---@param project_path string | nil
---@param allow_prerelease boolean
local function add_package(package, project_path, allow_prerelease)
  local versions = polyfills.tbl_map(function(v) return { value = v, display = v } end, get_all_versions(package, allow_prerelease))

  local selected_version = picker.pick_sync(nil, versions, "Select a version", true)
  local finished = job.register_job({
    name = string.format("Installing %s@%s", package, selected_version.value),
    on_error_text = string.format("dotnet restore failed"),
    on_success_text = string.format("%s@%s installed", package, selected_version.value),
  })
  local selected_project = project_path or get_project()
  local command = string.format("dotnet add %s package %s --version %s", selected_project, package, selected_version.value)
  local co = coroutine.running()
  vim.fn.jobstart(command, {
    on_exit = function(_, ex_code)
      if ex_code == 0 then
        vim.fn.jobstart(string.format("dotnet restore %s", selected_project), {
          on_exit = function(_, code)
            if code ~= 0 then
              local cmd = require("easy-dotnet.options").options.server.use_visual_studio == true and string.format("nuget restore %s %s", selected_project, "")
                or string.format("dotnet restore %s %s", selected_project, "")
              require("easy-dotnet.options").options.terminal(selected_project, "restore", "", { cmd = cmd })
              finished(false)
            else
              finished(true)
            end
          end,
        })
      else
        finished(false)
      end
      coroutine.resume(co)
    end,
  })
  coroutine.yield()
end

---@param project_path string | nil
---@param allow_prerelease boolean | nil
M.search_nuget = function(project_path, allow_prerelease)
  allow_prerelease = allow_prerelease or false
  local package = picker.search_nuget()
  if package ~= nil then add_package(package, project_path, allow_prerelease) end
end

M.get_nuget_sources_async = function()
  local co = coroutine.running()
  client:initialize(function()
    client.nuget:nuget_list_sources(function(res)
      coroutine.resume(co, vim.tbl_map(function(value) return { name = value.name, display = value.name } end, res))
    end)
  end)
  return coroutine.yield()
end

M.remove_nuget = function()
  local project_path = get_project()
  local project = csproj_parse.get_project_from_project_file(project_path)

  client:initialize(function()
    client.msbuild:msbuild_list_package_reference(project.path, project.msbuild_props.targetFramework, function(res)
      ---@param i PackageReference
      local choices = polyfills.tbl_map(function(i) return { display = i.id .. "@" .. i.resolvedVersion, value = i.id } end, res)
      picker.picker(nil, choices, function(val)
        local package = val.value
        vim.fn.jobstart(string.format("dotnet remove %s package %s ", project_path, package), {
          on_exit = function(_, code)
            if code ~= 0 then
              logger.error("Command failed")
            else
              logger.info("Package removed " .. package)
              vim.fn.jobstart(string.format("dotnet restore %s", project_path), {
                on_exit = function(_, ex_code)
                  if ex_code ~= 0 then
                    logger.error("Failed to restore packages")
                    require("easy-dotnet.options").options.terminal(project_path, "restore", "")
                  else
                    logger.info("Packages restored...")
                  end
                end,
              })
            end
          end,
        })
      end, "Pick package to remove", false)
    end)
  end)
end

return M
