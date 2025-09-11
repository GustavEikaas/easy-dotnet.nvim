local polyfills = require("easy-dotnet.polyfills")
local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local logger = require("easy-dotnet.logger")
local cache = require("easy-dotnet.modules.file-cache")
local M = {}

M.find_project_files = function()
  local csfiles = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.csproj$", depth = 3 })
  local fsfiles = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.fsproj$", depth = 3 })
  local normalized = {}
  for _, value in ipairs(csfiles) do
    table.insert(normalized, vim.fs.normalize(value))
  end
  for _, value in ipairs(fsfiles) do
    table.insert(normalized, vim.fs.normalize(value))
  end
  return normalized
end

---@param slnpath string
function M.add_project_to_solution(slnpath)
  local sln_projects = M.get_projects_from_sln(slnpath)
  local projects = M.find_project_files()

  local options = {}
  for _, value in ipairs(projects) do
    if not polyfills.tbl_contains(sln_projects, function(a) return vim.fs.normalize(a.path) == value end, { predicate = true }) then
      table.insert(options, {
        display = value,
        ordinal = value,
        value = value,
      })
    end
  end
  if #options == 0 then
    print("No projects found")
    return
  end

  local value = require("easy-dotnet.picker").pick_sync(nil, options, "Project to add to sln", false)
  if not value then return end
  vim.fn.jobstart({
    "dotnet",
    "sln",
    slnpath,
    "add",
    value.value,
  }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.schedule(function() logger.info("Success") end)
      else
        vim.schedule(function() logger.error("Failed to add project to solution") end)
      end
    end,
  })
end

---@param slnpath string
function M.remove_project_from_solution(slnpath)
  local projects = M.get_projects_from_sln(slnpath)

  if #projects == 0 then
    print("No projects found")
    return
  end

  local value = require("easy-dotnet.picker").pick_sync(nil, projects, "Project to remove from sln", false)
  if not value then return end
  vim.fn.jobstart({
    "dotnet",
    "sln",
    slnpath,
    "remove",
    value.path,
  }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.schedule(function() logger.info("Success") end)
      else
        vim.schedule(function() logger.error("Failed to remove project from solution") end)
      end
    end,
  })
end

---Parses a .sln file and returns a flattened list of DotnetProject objects,
---where each project is duplicated per target framework it supports.
---
---Each returned DotnetProject will have properties like `version` and `msbuild_props.targetFramework`
---updated to reflect that specific target framework. This is useful when you want to iterate
---over each project-framework combination individually.
---
---@param solution_file_path string: The path to the .sln solution file.
---@param filter_fn? fun(project: DotnetProject): boolean Optional predicate to filter projects.
---@return DotnetProject[]: A list of DotnetProject objects, duplicated and updated for each target framework.
M.get_projects_and_frameworks_flattened_from_sln = function(solution_file_path, filter_fn)
  local projects = M.get_projects_from_sln(solution_file_path, filter_fn)
  local project_frameworks = {}

  for _, project in ipairs(projects) do
    local defs = project.get_all_runtime_definitions()
    if defs then
      for _, def in ipairs(defs) do
        table.insert(project_frameworks, def)
      end
    end
  end

  return project_frameworks
end

---@param project_paths string[]
---@return DotnetProject[]
local function get_all_projects_from_paths(project_paths)
  return polyfills.tbl_map(function(proj_path)
    local csproj_parser = require("easy-dotnet.parsers.csproj-parse")
    local project = csproj_parser.get_project_from_project_file(proj_path)
    return project
  end, project_paths)
end

--- Preload MSBuild properties for multiple project paths, with optional coroutine suspension.
---@param project_lines string[] List of project paths
local function preload_msbuild_async_or_sync(project_lines)
  if #project_lines == 0 then return end
  local co = coroutine.running()
  local remaining = #project_lines

  for _, proj_path in ipairs(project_lines) do
    require("easy-dotnet.parsers.csproj-parse").preload_msbuild_properties(proj_path, function()
      remaining = remaining - 1
      if remaining == 0 then
        if co then coroutine.resume(co) end
      end
    end)
  end

  if co and remaining > 0 then coroutine.yield() end
end

---Parses a .sln file and returns a list of DotnetProject objects.
---If a callback is provided, only projects for which the callback returns true will be included.
---
---@param solution_file_path string: The path to the .sln solution file.
---@param filter_fn? fun(project: DotnetProject): boolean Optional predicate to filter projects.
---@return DotnetProject[]: A list of DotnetProject objects from the solution, optionally filtered.
function M.get_projects_from_sln_async(solution_file_path, filter_fn)
  ---@type string[]
  local project_lines = cache.get(solution_file_path, function()
    local co = coroutine.running()
    assert(co, "get_projects_from_sln_async must be called within a coroutine")
    local full_path = vim.fs.joinpath(vim.fn.getcwd(), solution_file_path)

    client:initialize(function()
      client:solution_list_projects(full_path, function(res)
        coroutine.resume(co, vim.tbl_map(function(value) return value.absolutePath end, res))
      end)
    end)
    return coroutine.yield()
  end)

  preload_msbuild_async_or_sync(project_lines)

  local projects = get_all_projects_from_paths(project_lines)
  if filter_fn then return vim.tbl_filter(filter_fn, projects) end

  return projects
end

---Parses a .sln file and returns a list of DotnetProject objects.
---If a callback is provided, only projects for which the callback returns true will be included.
---
---@param solution_file_path string: The path to the .sln solution file.
---@param filter_fn? fun(project: DotnetProject): boolean Optional predicate to filter projects.
---@return DotnetProject[]: A list of DotnetProject objects from the solution, optionally filtered.
function M.get_projects_from_sln(solution_file_path, filter_fn)
  local co = coroutine.running()
  ---@type string[]
  local result = cache.get(solution_file_path, function()
    local full_path = vim.fs.joinpath(vim.fn.getcwd(), solution_file_path)
    client:initialize(function()
      client:solution_list_projects(full_path, function(res)
        coroutine.resume(co, vim.tbl_map(function(value) return value.absolutePath end, res))
      end)
    end)
    local project_lines = coroutine.yield()
    return project_lines
  end)

  preload_msbuild_async_or_sync(result)
  local projects = get_all_projects_from_paths(result)

  if filter_fn then return vim.tbl_filter(filter_fn, projects) end

  return projects
end

---@return table<string>
function M.get_solutions()
  local sln_files = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.slnx?$", depth = 5 })
  return sln_files
end

M.try_get_selected_solution_file = function()
  local files = M.get_solutions()
  for _, value in ipairs(files) do
    local file = require("easy-dotnet.default-manager").try_get_cache_file(value)
    if file then return value end
  end
end

---@return string | nil
M.find_solution_file = function(no_cache)
  local files = M.get_solutions()
  local opts = {}
  for _, value in ipairs(files) do
    local file = require("easy-dotnet.default-manager").try_get_cache_file(value)
    if file and not no_cache then
      ---@type string
      return value
    end
    table.insert(opts, { display = value, ordinal = value, value = value })
  end
  if #opts == 0 then return nil end
  local selection = require("easy-dotnet.picker").pick_sync(nil, opts, "Pick solution file")

  if selection.value then
    require("easy-dotnet.default-manager").set_default_solution(nil, selection.value)
    return selection.value
  end
end

return M
