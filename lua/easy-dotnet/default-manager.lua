local polyfills = require("easy-dotnet.polyfills")
---@class DefaultProfile
---@field project string
---@field profile string

---@class SolutionContent
---@field default_build_project string
---@field default_test_project string
---@field default_run_project string
---@field default_debug_project string
---@field default_profile DefaultProfile

---@class PersistedDefinition
---@field project string
---@field target_framework string | nil

local M = {}

---@alias TaskType "build" | "test" | "run" | "launch-profile" | "view" | "watch" | "debug"

---Gets the property name for the given type.
---@param type TaskType
---@return string
local function get_property(type)
  if not (type == "build" or type == "test" or type == "run" or type == "launch-profile" or type == "view" or type == "watch" or type == "debug") then
    error("Expected build, test or run received " .. type)
  end
  if type == "launch-profile" then return "default_profile" end
  return string.format("default_%s_project", type)
end

local function file_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "file"
end

local function get_or_create_cache_dir()
  local dir = require("easy-dotnet.constants").get_data_directory()
  local file_utils = require("easy-dotnet.file-utils")
  file_utils.ensure_directory_exists(dir)
  return dir
end

function M.try_get_cache_file(solution_file_path)
  local sln_name = vim.fs.basename(solution_file_path)
  local dir = get_or_create_cache_dir()
  local file = polyfills.fs.joinpath(dir, sln_name .. ".json")
  if file_exists(file) then return file end
end

local function get_or_create_cache_file(solution_file_path)
  local sln_name = vim.fs.basename(solution_file_path)
  local file_utils = require("easy-dotnet.file-utils")
  local dir = get_or_create_cache_dir()
  local file = polyfills.fs.joinpath(dir, sln_name .. ".json")
  file_utils.ensure_json_file_exists(file)

  local _, decoded = pcall(vim.fn.json_decode, vim.fn.readfile(file))
  return {
    file = file,
    ---@type SolutionContent|nil
    decoded = decoded,
  }
end

M.set_default_solution = function(old_solution_file, solution_file_path)
  if old_solution_file then
    local sln_name = vim.fs.basename(old_solution_file)
    local dir = get_or_create_cache_dir()
    local file = polyfills.fs.joinpath(dir, sln_name .. ".json")
    if file_exists(file) then
      local success, err = pcall(vim.loop.fs_unlink, file)
      if not success then print("Failed to delete file: " .. err) end
    end
  end

  get_or_create_cache_file(solution_file_path)
end

---@param project string | PersistedDefinition | nil
---@return PersistedDefinition | nil
local function backwards_compatible(project)
  if not project then return nil end
  if type(project) == "string" then return {
    project = project,
  } end
  return project
end

---Checks for the default project in the solution file.
---@param solution_file_path string Path to the solution file.
---@param type TaskType
---@return DotnetProject|nil
M.check_default_project = function(solution_file_path, type)
  local file = get_or_create_cache_file(solution_file_path)
  local sln_parse = require("easy-dotnet.parsers.sln-parse")

  local default = backwards_compatible(file.decoded[get_property(type)])
  if default ~= nil then
    local projects = sln_parse.get_projects_and_frameworks_flattened_from_sln(solution_file_path)
    table.insert(projects, { path = solution_file_path, display = "Solution", name = "Solution" })

    ---@type DotnetProject[]
    local matches = vim.tbl_filter(function(value) return value.name == default.project end, projects)

    if #matches == 0 then return nil end

    for _, value in ipairs(matches) do
      if value.msbuild_props.isMultiTarget then
        if value.msbuild_props.targetFramework == default.target_framework then return value end
      else
        return value
      end
    end

    --Project changed from being single target to multi target
    local fallback = matches[1]
    if not fallback then return nil end
    M.set_default_project(fallback, solution_file_path, type)
    return fallback
  end
end

---@param project DotnetProject The project to set as default.
---@return PersistedDefinition
local function project_to_persist(project)
  return {
    project = project.name,
    target_framework = project.msbuild_props.isMultiTarget and project.msbuild_props.targetFramework or nil,
  }
end

---Sets the default project in the solution file.
---@param project DotnetProject The project to set as default.
---@param solution_file_path string Path to the solution file.
---@param type TaskType
M.set_default_project = function(project, solution_file_path, type)
  local file = get_or_create_cache_file(solution_file_path)

  if file.decoded == nil then file.decoded = {} end

  file.decoded[get_property(type)] = project_to_persist(project)
  local file_utils = require("easy-dotnet.file-utils")
  file_utils.overwrite_file(file.file, vim.fn.json_encode(file.decoded))
end

---@param project DotnetProject
---@param solution_file_path string
---@param profile string
M.set_default_launch_profile = function(project, solution_file_path, profile)
  local file = get_or_create_cache_file(solution_file_path)

  if file.decoded == nil then file.decoded = {} end

  ---@type DefaultProfile
  local default_profile = {
    project = project.name,
    profile = profile,
  }

  file.decoded[get_property("launch-profile")] = default_profile
  local file_utils = require("easy-dotnet.file-utils")
  file_utils.overwrite_file(file.file, vim.fn.json_encode(file.decoded))
end

---@param solution_file_path string
---@param project DotnetProject
---@return DefaultProfile | nil
M.get_default_launch_profile = function(solution_file_path, project)
  local file = get_or_create_cache_file(solution_file_path)
  local default_profile = file.decoded.default_profile

  if default_profile and project.name == default_profile.project then return default_profile end

  return nil
end

return M
