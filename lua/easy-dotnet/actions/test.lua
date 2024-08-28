local M = {}
local extensions = require("easy-dotnet.extensions")
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")

local function csproj_fallback(on_select)
  local csproj_path = csproj_parse.find_csproj_file()
  if (csproj_path == nil) then
    vim.notify("No .sln file or .csproj file found")
  end
  picker.picker(nil, { { name = csproj_path, display = csproj_path, path = csproj_path } },
    function(i) on_select(i.path, "test") end, "Run test")
end

local function select_project(solution_file_path, cb, use_default)
  local default_manager = require("easy-dotnet.default-manager")
  local default = default_manager.check_default_project(solution_file_path, "test")
  if default ~= nil and use_default == true then
    return cb(default)
  end

  local projects = extensions.filter(sln_parse.get_projects_from_sln(solution_file_path),
    function(i)
      return i.isTestProject == true
    end)


  if #projects == 0 then
    vim.notify(error_messages.no_test_projects_found)
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
    default_manager.set_default_project(project, solution_file_path, "test")
  end, "Run test(s)")
end


---@param use_default boolean
M.run_test_picker = function(on_select, use_default)
  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    csproj_fallback(on_select)
    return
  end

  select_project(solutionFilePath, function(project)
    on_select(project.path, "test")
  end, use_default)
end

M.test_solution = function(term)
  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_csproj_file()
  if solutionFilePath == nil then
    vim.notify(error_messages.no_project_definition_found)
    return
  end
  term(solutionFilePath, "test")
end


M.test_watcher = function()
  local dn = require("easy-dotnet.parsers").sln_parser
  local slnPath = dn.find_solution_file()
  local projects = dn.get_projects_from_sln(slnPath)
  local testProjects = {}
  for _, value in pairs(projects) do
    if value.isTestProject then
      table.insert(testProjects, value)
    end
  end
  local header_test_message = "🧪 Testing..." .. "\n\n"

  local testMessage = header_test_message
  for _, value in pairs(testProjects) do
    testMessage = testMessage .. "\n" .. value.name
  end

  local state = {}

  for _, value in pairs(testProjects) do
    table.insert(state, { state = "pending", name = value.name })
  end

  local notification = nil
  local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }

  local function update_message(i)
    local message = header_test_message
    for _, value in pairs(state) do
      local icon = spinner_frames[i % #spinner_frames + 1]
      if value.state == "pending" then

      elseif value.state == "failed" then
        icon = "❌"
      elseif value.state == "success" then
        icon = "✅"
      end
      message = message .. "\n" .. icon .. " " .. value.name
    end
    notification = vim.notify(message, "info", { replace = notification })
  end

  update_message(1)
  local i = 1
  for _, value in pairs(testProjects) do
    vim.fn.jobstart("dotnet test " .. value.path, {
      on_exit = function(_, b, _)
        local curr = nil
        for _, stateValue in pairs(state) do
          if value.name == stateValue.name then
            curr = stateValue
          end
        end
        if curr == nil then
          error("blaaa")
        end
        if b == 0 then
          curr.state = "success"
        else
          curr.state = "failed"
        end
        update_message(1)
      end,
      on_stdout = function()
        i = i + 1
        update_message(i)
      end

    })
  end
end



return M
