local M = {}

---@class NugetSource
---@field name string  # The source URL or path
---@field display string  # Display-friendly name (same as URL here)

local async = require("easy-dotnet.async-utils")
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

local function get_all_versions(package)
  local co = coroutine.running()

  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  client:initialize(function()
    client.nuget:nuget_get_package_versions(package, nil, false, function(i) coroutine.resume(co, list_reverse(i)) end)
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
local function add_package(package, project_path)
  local versions = polyfills.tbl_map(function(v) return { value = v, display = v } end, get_all_versions(package))

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
M.search_nuget = function(project_path)
  local package = picker.search_nuget()
  if package ~= nil then add_package(package, project_path) end
end

local function get_package_refs(project_path)
  local command = string.format('dotnet list %s package --format json | jq "[.projects[].frameworks[].topLevelPackages[] | {name: .id, version: .resolvedVersion}]"', project_path)
  local out = vim.fn.system(command)
  if vim.v.shell_error then logger.error("Failed to get packages for " .. project_path) end
  local packages = vim.fn.json_decode(out)
  return packages
end

---@async
--- Asynchronously lists NuGet sources using `dotnet nuget list source`.
--- Returns a list of `NugetSource` objects representing each source.
--- Throws an error if the command fails.
---
--- @return NugetSource[] List of NuGet source objects.
M.get_nuget_sources_async = function()
  local pack_res = async.await(async.job_run_async)({ "dotnet", "nuget", "list", "source", "--format", "short" })

  if not pack_res.success then
    vim.print(pack_res.stderr)
    error("Listing nuget sources failed")
  end
  return vim
    .iter(pack_res.stdout)
    :map(function(line)
      local url = vim.trim(line):match("^%u%s+(.*)")
      if not url then return nil end
      return { name = url, display = url }
    end)
    :filter(function(val) return val ~= nil end)
    :totable()
end

M.remove_nuget = function()
  local project_path = get_project()
  local packages = get_package_refs(project_path)
  local choices = polyfills.tbl_map(function(i) return { display = i.name .. "@" .. i.version, value = i.name } end, packages)
  local package = picker.pick_sync(nil, choices, "Pick package to remove", false).value
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
end

return M
