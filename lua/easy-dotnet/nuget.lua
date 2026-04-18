local M = {}

local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local picker = require("easy-dotnet.picker")
local logger = require("easy-dotnet.logger")
local messages = require("easy-dotnet.error-messages")

---@return string
local function get_project()
  local sln_file_path = sln_parse.try_get_selected_solution_file()
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
---@param allow_prerelease boolean | nil
M.search_nuget = function(project_path, allow_prerelease)
  allow_prerelease = allow_prerelease or false
  client:initialize(function()
    client.nuget:nuget_add_package(project_path, allow_prerelease)
  end)
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
      ---@param i easy-dotnet.MSBuild.PackageReference
      local choices = vim.tbl_map(function(i) return { display = i.id .. "@" .. i.resolvedVersion, value = i.id } end, res)
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
