local polyfills = require("easy-dotnet.polyfills")
local logger = require("easy-dotnet.logger")
local M = {}

local function generate_absolute_path_for_project(path, slnpath)
  local base = vim.fs.normalize(vim.fn.getcwd())
  local dir = vim.fs.normalize(vim.fs.dirname(slnpath))
  local res = vim.fs.normalize(polyfills.fs.joinpath(base, dir, vim.fs.normalize(path)))
  return res
end

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

function M.get_projects_from_slnx(solution_file_path, filter_fn)
  local file_contents = vim.fn.readfile(solution_file_path)
  local regexp = '<Project Path="([^"]+)"'

  local project_lines = polyfills.tbl_filter(function(line)
    local path = line:match(regexp)
    if path and (path:match("%.csproj$") or path:match("%.fsproj$")) then return true end
    return false
  end, file_contents)

  polyfills.iter(project_lines):each(function(proj_path)
    local _, _, path = proj_path:match(regexp)
    local project_file_path = generate_absolute_path_for_project(path, solution_file_path)
    require("easy-dotnet.parsers.csproj-parse").preload_msbuild_properties(project_file_path)
  end)

  local projects = polyfills.tbl_map(function(line)
    local csproj_parser = require("easy-dotnet.parsers.csproj-parse")
    local path = line:match(regexp)
    local project_file_path = generate_absolute_path_for_project(path, solution_file_path)
    local project = csproj_parser.get_project_from_project_file(project_file_path)
    return project
  end, project_lines)

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
  local extension = vim.fn.fnamemodify(solution_file_path, ":e")
  if extension == "slnx" then return M.get_projects_from_slnx(solution_file_path, filter_fn) end

  local file_contents = vim.fn.readfile(solution_file_path)
  local regexp = 'Project%("{(.-)}"%).*= "(.-)", "(.-)", "{.-}"'

  local project_lines = polyfills.tbl_filter(function(line)
    local id, name, path = line:match(regexp)
    if id and name and path and (path:match("%.csproj$") or path:match("%.fsproj$")) then return true end
    return false
  end, file_contents)

  polyfills.iter(project_lines):each(function(proj_path)
    local _, _, path = proj_path:match(regexp)
    local project_file_path = generate_absolute_path_for_project(path, solution_file_path)
    require("easy-dotnet.parsers.csproj-parse").preload_msbuild_properties(project_file_path)
  end)

  local projects = polyfills.tbl_map(function(line)
    local csproj_parser = require("easy-dotnet.parsers.csproj-parse")
    local _, _, path = line:match(regexp)
    local project_file_path = generate_absolute_path_for_project(path, solution_file_path)
    local project = csproj_parser.get_project_from_project_file(project_file_path)
    return project
  end, project_lines)

  if filter_fn then return vim.tbl_filter(filter_fn, projects) end

  return projects
end

---@return table<string>
function M.get_solutions()
  local sln_files = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.sln$", depth = 5 })
  local slnx_files = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.slnx$", depth = 5 })

  local normalized = {}
  for _, value in ipairs(sln_files) do
    table.insert(normalized, value)
  end
  for _, value in ipairs(slnx_files) do
    table.insert(normalized, value)
  end
  return normalized
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
  return selection and selection.value or nil
end

return M
