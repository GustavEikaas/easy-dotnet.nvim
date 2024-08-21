local M = {}
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local messages = require("easy-dotnet.error-messages")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")

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
M.build_project_picker = function(term)
  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    csproj_fallback(term)
    return
  end
  local projects = sln_parse.get_projects_from_sln(solutionFilePath)

  if #projects == 0 then
    vim.notify(error_messages.no_projects_found)
    return
  end

  -- Add an entry for the solution file
  table.insert(projects, {
    path = solutionFilePath,
    display = "All"
  })

  picker.picker(nil, projects, function(i)
    term(i.path, "build")
  end, "Build project(s)")
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

M.build_project_quickfix = function()
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
  local projects = sln_parse.get_projects_from_sln(solutionFilePath)

  if #projects == 0 then
    vim.notify(error_messages.no_projects_found)
    return
  end

  -- Add an entry for the solution file
  table.insert(projects, {
    path = solutionFilePath,
    display = "All"
  })

  picker.picker(nil, projects, function(i)
    vim.notify("Building...")
    local logPath = vim.fn.stdpath "data" .. "/easy-dotnet/build.log"
    local command = "dotnet build " .. i.path .. " /flp:v=q /flp:logfile=" .. logPath
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
  end, "Build project(s)")
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
