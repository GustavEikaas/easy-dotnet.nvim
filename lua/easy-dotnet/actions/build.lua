local constants = require("easy-dotnet.constants")
local current_solution = require("easy-dotnet.current_solution")
local M = {
  pending = false,
}

local logger = require("easy-dotnet.logger")
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local messages = require("easy-dotnet.error-messages")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")
local default_manager = require("easy-dotnet.default-manager")
local qf_list = require("easy-dotnet.build-output.qf-list")

local function group_by_project(errors)
  return vim.iter(errors):fold({}, function(acc, err)
    local project = err.project or "Unknown project"
    acc[project] = acc[project] or {}
    table.insert(acc[project], err)
    return acc
  end)
end

function M.rpc_build_quickfix(target_path, configuration, args, cb)
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client

  if M.pending == true then
    logger.error("Build already pending...")
    return
  end

  current_solution.get_or_pick_solution(function(solution_path)
    solution_path = solution_path or csproj_parse.find_project_file()
    if solution_path == nil then
      logger.error(error_messages.no_project_definition_found)
      return
    end

    client:initialize(function()
      M.pending = true
      client.msbuild:msbuild_build({ targetPath = target_path, configuration = configuration, buildArgs = args }, function(res)
        local ext = vim.fn.fnamemodify(target_path, ":e")
        local is_solution = ext == "sln" or ext == "slnx"
        M.pending = false
        if cb then cb(res.success) end
        if res.success then
          if is_solution then
            qf_list.clear_all()
          else
            qf_list.clear_project(target_path)
          end
          return
        end

        if is_solution then qf_list.clear_all() end
        local project_map = group_by_project(res.errors)
        for project, diagnostics in pairs(project_map) do
          qf_list.set_project_diagnostics(project, diagnostics)
        end
      end)
    end)
  end)
end

local function select_project(solution_file_path, cb, use_default)
  local default = default_manager.check_default_project(solution_file_path, "build")
  if default ~= nil and use_default == true then return cb(default) end

  local projects = sln_parse.get_projects_from_sln(solution_file_path)

  if #projects == 0 then
    logger.error(error_messages.no_projects_found)
    return
  end

  local cmd = require("easy-dotnet.options").get_option("server").use_visual_studio
      and string.format('%s build "%s" --msbuild "%s"', constants.compat_command, solution_file_path, require("easy-dotnet.rpc.rpc").global_rpc_client.initialized_msbuild_path)
    or string.format("dotnet build %s %s", solution_file_path, "")
  local choices = {
    { path = solution_file_path, display = "Solution", name = "Solution", msbuild_props = { buildCommand = cmd } },
  }

  for _, project in ipairs(projects) do
    table.insert(choices, project)
  end

  picker.picker(nil, choices, function(project)
    cb(project)
    default_manager.set_default_project(project, solution_file_path, "build")
  end, "Build project(s)")
end

local function csproj_fallback(term)
  local csproj_path = csproj_parse.find_project_file()
  if csproj_path == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end
  local project = csproj_parse.get_project_from_project_file(csproj_path)

  picker.picker(nil, { project }, function(i)
    local cmd = i.msbuild_props.buildCommand
    term(i.path, "build", "", { cmd = cmd })
  end, "Build project(s)")
end

---@param term function | nil
---@param use_default boolean
M.build_project_picker = function(term, use_default, args)
  term = term or require("easy-dotnet.options").options.terminal
  use_default = use_default or false
  args = args or ""

  current_solution.get_or_pick_solution(function(solution_path)
    if solution_path == nil then
      csproj_fallback(term)
      return
    end

    select_project(solution_path, function(project)
      local cmd = project.msbuild_props.buildCommand
      term(project.path, "build", args, { cmd = cmd })
    end, use_default)
  end)
end

---@param use_default boolean
M.build_project_quickfix = function(use_default, dotnet_args)
  use_default = use_default or false
  dotnet_args = dotnet_args or ""

  current_solution.get_or_pick_solution(function(solution_path)
    if solution_path == nil then
      local csproj = csproj_parse.find_project_file()
      if csproj == nil then
        logger.error(messages.no_project_definition_found)
        return
      end
      M.rpc_build_quickfix(csproj, nil, dotnet_args)
      return
    end

    select_project(solution_path, function(project)
      if project == nil then return end
      M.rpc_build_quickfix(project.path, nil, dotnet_args)
    end, use_default)
  end)
end

M.build_solution = function(term, args)
  term = term or require("easy-dotnet.options").options.terminal
  args = args or ""

  current_solution.get_or_pick_solution(function(solution_path)
    solution_path = solution_path or csproj_parse.find_project_file()

    if solution_path == nil then
      logger.error(error_messages.no_project_definition_found)
      return
    end

    local cmd = require("easy-dotnet.options").get_option("server").use_visual_studio
        and string.format('%s build "%s" --msbuild "%s"', constants.compat_command, solution_path, require("easy-dotnet.rpc.rpc").global_rpc_client.initialized_msbuild_path)
      or string.format("dotnet build %s %s", solution_path, args)
    term(solution_path, "build", args or "", { cmd = cmd })
  end)
end

M.build_solution_quickfix = function(dotnet_args)
  dotnet_args = dotnet_args or ""

  current_solution.get_or_pick_solution(function(solution_path)
    solution_path = solution_path or csproj_parse.find_project_file()

    if solution_path == nil then
      logger.error(error_messages.no_project_definition_found)
      return
    end

    M.rpc_build_quickfix(solution_path, nil, dotnet_args)
  end)
end

return M
