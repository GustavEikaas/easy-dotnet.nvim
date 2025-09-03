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
local polyfills = require("easy-dotnet.polyfills")

local function select_project(solution_file_path, cb, use_default)
  local default = default_manager.check_default_project(solution_file_path, "build")
  if default ~= nil and use_default == true then return cb(default) end

  local projects = sln_parse.get_projects_from_sln(solution_file_path)

  if #projects == 0 then
    logger.error(error_messages.no_projects_found)
    return
  end

  local cmd = require("easy-dotnet.options").get_option("server").use_visual_studio
      and string.format("& '%s' %s %s", require("easy-dotnet.rpc.rpc").global_rpc_client.initialized_msbuild_path, solution_file_path, "")
    or string.format("dotnet restore %s %s", solution_file_path, "")
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

  picker.picker(nil, { { name = csproj_path, display = csproj_path, path = csproj_path } }, function(i)
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

  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    csproj_fallback(term)
    return
  end

  select_project(solutionFilePath, function(project)
    local cmd = project.msbuild_props.buildCommand
    term(project.path, "build", args, { cmd = cmd })
  end, use_default)
end

local qf_title = "easy-dotnet"

local function set_quickfix_list(items)
  vim.fn.setqflist({}, " ", {
    title = qf_title,
    items = items,
  })
  vim.cmd("copen")
end

local function close_quickfix_list()
  local info = vim.fn.getqflist({ title = 1 })
  if info.title == qf_title then
    vim.fn.setqflist({})
    vim.cmd("cclose")
  end
end

local function populate_quickfix_from_file(filename)
  local file = io.open(filename, "r")
  if not file then
    print("Could not open file " .. filename)
    return
  end

  local quickfix_list = {}

  for line in file:lines() do
    -- Only matches build errors
    local filepath, lnum, col, text = line:match("^(.+)%((%d+),(%d+)%)%: error (.+)$")

    if filepath and lnum and col and text then
      text = text:match("^(.-)%s%[.+$")

      table.insert(quickfix_list, {
        filename = filepath,
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = text,
      })
    end
  end

  -- Close the file
  file:close()

  -- Set the quickfix list
  set_quickfix_list(quickfix_list)

  -- Open the quickfix window
  vim.cmd("copen")
end

local function execute_build_quickfix_command(command, log_path)
  local jobs = require("easy-dotnet.ui-modules.jobs")
  local on_finished = jobs.register_job({ name = "Building", on_error_text = "Build failed", on_success_text = "Successfully built" })

  M.pending = true
  vim.fn.jobstart(command, {
    on_exit = function(_, b, _)
      M.pending = false
      on_finished(b == 0)
      if b == 0 then
        close_quickfix_list()
      else
        populate_quickfix_from_file(log_path)
      end
    end,
  })
end

---@param use_default boolean
---@param dotnet_args string | nil
M.build_project_quickfix = function(use_default, dotnet_args)
  use_default = use_default or false
  dotnet_args = dotnet_args or ""

  if M.pending == true then
    logger.error("Build already pending...")
    return
  end
  local data_dir = require("easy-dotnet.constants").get_data_directory()
  local log_path = polyfills.fs.joinpath(data_dir, "build.log")

  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    local csproj = csproj_parse.find_project_file()
    if csproj == nil then
      logger.error(messages.no_project_definition_found)
      return
    end
    local command = string.format("dotnet build %s /flp:v=q /flp:logfile=%s %s", csproj, log_path, dotnet_args or "")
    execute_build_quickfix_command(command, log_path)
    return
  end

  select_project(solutionFilePath, function(project)
    if project == nil then return end
    local command = string.format("dotnet build %s /flp:v=q /flp:logfile=%s %s", project.path, log_path, dotnet_args or "")
    execute_build_quickfix_command(command, log_path)
  end, use_default)
end

M.build_solution = function(term, args)
  term = term or require("easy-dotnet.options").options.terminal
  args = args or ""

  local solution_file_path = sln_parse.find_solution_file() or csproj_parse.find_project_file()
  if solution_file_path == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end
  local cmd = require("easy-dotnet.options").get_option("server").use_visual_studio
      and string.format("& '%s' %s %s", require("easy-dotnet.rpc.rpc").global_rpc_client.initialized_msbuild_path, solution_file_path, args)
    or string.format("dotnet restore %s %s", solution_file_path, args)
  term(solution_file_path, "build", args or "", { cmd = cmd })
end

M.build_solution_quickfix = function(dotnet_args)
  dotnet_args = dotnet_args or ""
  if M.pending == true then
    logger.error("Build already pending...")
    return
  end
  local data_dir = require("easy-dotnet.constants").get_data_directory()
  local log_path = polyfills.fs.joinpath(data_dir, "build.log")
  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_project_file()
  if solutionFilePath == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end
  local command = string.format("dotnet build %s /flp:v=q /flp:logfile=%s %s", solutionFilePath, log_path, dotnet_args or "")
  execute_build_quickfix_command(command, log_path)
end

return M
