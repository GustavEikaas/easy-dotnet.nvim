local M = {}
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local messages = require("easy-dotnet.error-messages")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")
local default_manager = require("easy-dotnet.default-manager")


local function select_project(solution_file_path, cb, use_default)
  local default = default_manager.check_default_project(solution_file_path, "build")
  if default ~= nil and use_default == true then
    return cb(default)
  end

  local projects = sln_parse.get_projects_from_sln(solution_file_path)

  if #projects == 0 then
    vim.notify(error_messages.no_projects_found)
    return
  end
  local choices = {
    { path = solution_file_path, display = "Solution", name = "Solution" }
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
  local csproj_path = csproj_parse.find_csproj_file()
  if (csproj_path == nil) then
    vim.notify(error_messages.no_project_definition_found)
    return
  end
  picker.picker(nil, { { name = csproj_path, display = csproj_path, path = csproj_path } }, function(i)
    term(i.path, "build")
  end, "Build project(s)")
end

---@param term function
---@param use_default boolean
M.build_project_picker = function(term, use_default)
  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    csproj_fallback(term)
    return
  end

  select_project(solutionFilePath, function(project)
    term(project.path, "build")
  end, use_default)
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
  vim.fn.setqflist(quickfix_list)

  -- Open the quickfix window
  vim.cmd("copen")
end


---@param use_default boolean
M.build_project_quickfix = function(use_default)
  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    local csproj = csproj_parse.find_csproj_file()
    if csproj == nil then
      vim.notify(messages.no_project_definition_found)
    end
    local logPath = vim.fn.stdpath "data" .. "/easy-dotnet/build.log"
    local command = "dotnet build " .. csproj .. " /flp:v=q /flp:logfile=" .. logPath
    vim.fn.jobstart(command, {
      on_exit = function(_, b, _)
        if b == 0 then
          vim.notify("Built successfully")
        else
          vim.notify("Build failed")
          populate_quickfix_from_file(logPath)
        end
      end,
    })

    return
  end

  select_project(solutionFilePath, function(project)
    if project == nil then
      return
    end
    vim.notify("Building...")
    local logPath = vim.fn.stdpath "data" .. "/easy-dotnet/build.log"
    local command = "dotnet build " .. project.path .. " /flp:v=q /flp:logfile=" .. logPath
    vim.fn.jobstart(command, {
      on_exit = function(_, b, _)
        if b == 0 then
          vim.notify("Built successfully")
        else
          vim.notify("Build failed")
          populate_quickfix_from_file(logPath)
        end
      end,
    })
  end, use_default)
end


M.build_solution = function(term)
  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_csproj_file()
  if solutionFilePath == nil then
    vim.notify(error_messages.no_project_definition_found)
    return
  end
  term(solutionFilePath, "build")
end

return M
