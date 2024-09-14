---@class SolutionContent
---@field default_build_project string
---@field default_test_project string
---@field default_run_project string

local M = {}

---Gets the property name for the given type.
---@param type '"build"' | '"test"' | '"run"'
---@return string
local function get_property(type)
  if not (type == "build" or type == "test" or type == "run") then
    error("Expected build, test or run received " .. type)
  end
  return string.format("default_%s_project", type)
end

local function get_or_create_cache_dir()
  --TODO: constants.get_data_dir
  local dir = vim.fs.joinpath(vim.fn.stdpath("data"), "easy-dotnet")
  local file_utils = require("easy-dotnet.file-utils")
  file_utils.ensure_directory_exists(dir)
  return dir
end

local function extract_sln_name(solution_file_path)
  return solution_file_path:match("([^/\\]+)$")
end

local function get_or_create_cache_file(solution_file_path)
  local sln_name = extract_sln_name(solution_file_path)
  local file_utils = require("easy-dotnet.file-utils")
  local dir = get_or_create_cache_dir()
  local file = vim.fs.joinpath(dir, sln_name .. ".json")
  file_utils.ensure_json_file_exists(file)

  local _, decoded = pcall(vim.fn.json_decode, vim.fn.readfile(file))
  return {
    file = file,
    ---@type SolutionContent|nil
    decoded = decoded
  }

end

---Checks for the default project in the solution file.
---@param solution_file_path string Path to the solution file.
---@param type '"build"' | '"test"' | '"run"'
---@return DotnetProject|nil
M.check_default_project = function(solution_file_path, type)
  local file = get_or_create_cache_file(solution_file_path)
  local sln_parse = require("easy-dotnet.parsers.sln-parse")

  local project = file.decoded[get_property(type)]
  if project ~= nil then
    local projects = sln_parse.get_projects_from_sln(solution_file_path)
    --TODO: improve 
    table.insert(projects, { path = solution_file_path, display = "Solution", name = "Solution" })

    for _, value in ipairs(projects) do
      if value.name == project then
        return value
      end
    end
  end
end

---Sets the default project in the solution file.
---@param project DotnetProject The project to set as default.
---@param solution_file_path string Path to the solution file.
---@param type '"build"' | '"test"' | '"run"'
M.set_default_project = function(project, solution_file_path, type)
  local file = get_or_create_cache_file(solution_file_path)

  if file.decoded == nil then
    file.decoded = {} 
  end

  file.decoded[get_property(type)] = project.name
    local file_utils = require("easy-dotnet.file-utils")
  file_utils.overwrite_file(file.file, vim.fn.json_encode(file.decoded))
end

return M
