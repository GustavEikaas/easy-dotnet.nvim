local polyfills = require("easy-dotnet.polyfills")
local M = {}

-- Generates a relative path from cwd to the project.csproj file
local function generate_relative_path_for_project(path, slnpath)
  local dir = vim.fs.dirname(slnpath)
  local res = polyfills.fs.joinpath(dir, path):gsub("\\", "/")
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

---Dotnet solution add with telescope picker
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
        vim.schedule(function() vim.notify("Success") end)
      else
        vim.schedule(function() vim.notify("Failed to add project to solution", vim.log.levels.ERROR) end)
      end
    end,
  })
end

---Dotnet solution remove with telescope picker
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
        vim.schedule(function() vim.notify("Success") end)
      else
        vim.schedule(function() vim.notify("Failed to remove project from solution", vim.log.levels.ERROR) end)
      end
    end,
  })
end

-- TODO: Investigate using dotnet sln list command
---@param solutionFilePath string
---@return DotnetProject[]
M.get_projects_from_sln = function(solutionFilePath)
  local file_contents = vim.fn.readfile(solutionFilePath)
  local regexp = 'Project%("{(.-)}"%).*= "(.-)", "(.-)", "{.-}"'

  local projectLines = polyfills.tbl_filter(function(line)
    local id, name, path = line:match(regexp)
    if id and name and path and (path:match("%.csproj$") or path:match("%.fsproj$")) then return true end
    return false
  end, file_contents)

  local projects = polyfills.tbl_map(function(line)
    local csproj_parser = require("easy-dotnet.parsers.csproj-parse")
    local _, _, path = line:match(regexp)
    local project_file_path = generate_relative_path_for_project(path, solutionFilePath)
    local project = csproj_parser.get_project_from_project_file(project_file_path)
    return project
  end, projectLines)

  return projects
end

---@return table<string>
function M.get_solutions()
  local files = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.sln$", depth = 5 })
  return files
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
