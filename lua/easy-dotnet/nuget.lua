local M = {}

local polyfills = require("easy-dotnet.polyfills")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local picker = require("easy-dotnet.picker")
local logger = require("easy-dotnet.logger")

local function reverse_list(list)
  local reversed = {}
  for i = #list, 1, -1 do
    table.insert(reversed, list[i])
  end
  return reversed
end

local function get_all_versions(package)
  local command = string.format("dotnet package search %s --exact-match --format json | jq '.searchResult[].packages[].version'", package)
  local versions = vim.fn.split(vim.fn.system(command):gsub('"', ""), "\n")
  return reverse_list(versions)
end

---@return string
local function get_project()
  local sln_file_path = sln_parse.find_solution_file()
  if not sln_file_path then
    logger.error("No solution file found")
    error("No solution file found")
  end
  local projects = sln_parse.get_projects_from_sln(sln_file_path)
  return picker.pick_sync(nil, projects, "Select a project", true).path
end

---@param project_path string | nil
local function add_package(package, project_path)
  print("Getting versions...")
  local versions = polyfills.tbl_map(function(v) return { value = v, display = v } end, get_all_versions(package))

  local selected_version = picker.pick_sync(nil, versions, "Select a version", true)
  logger.info("Adding package...")
  local selected_project = project_path or get_project()
  local command = string.format("dotnet add %s package %s --version %s", selected_project, package, selected_version.value)
  local co = coroutine.running()
  vim.fn.jobstart(command, {
    on_exit = function(_, ex_code)
      if ex_code == 0 then
        logger.info("Restoring packages...")
        vim.fn.jobstart(string.format("dotnet restore %s", selected_project), {
          on_exit = function(_, code)
            if code ~= 0 then
              logger.error("Dotnet restore failed...")
              --Retry usings users terminal, this will present the error for them. Not sure if this is the correct design choice
              require("easy-dotnet.options").options.terminal(selected_project, "restore", "")
            else
              logger.info(string.format("Installed %s@%s in %s", package, selected_version.value, vim.fs.basename(selected_project)))
            end
          end,
        })
      else
        logger.error(string.format("Failed to install %s@%s in %s", package, selected_version.value, vim.fs.basename(selected_project)))
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
  local command = string.format("dotnet list %s package --format json | jq '[.projects[].frameworks[].topLevelPackages[] | {name: .id, version: .resolvedVersion}]'", project_path)
  local out = vim.fn.system(command)
  if vim.v.shell_error then logger.error("Failed to get packages for " .. project_path) end
  local packages = vim.fn.json_decode(out)
  return packages
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
