local polyfills = require("easy-dotnet.polyfills")
local logger = require("easy-dotnet.logger")
local M = {}

local function sln_add_project(sln_path, project)
  vim.fn.jobstart(string.format("dotnet sln %s add %s", sln_path, project), {
    stdout_buffered = true,
    on_exit = function(_, b)
      if b ~= 0 then logger.error("Failed to link project to solution") end
    end,
  })
end

local function get_dotnet_new_args(name)
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local sln_path = sln_parse.find_solution_file()
  if sln_path == nil then return nil end

  local folder_path = vim.fs.dirname(sln_path)
  local solution_name = vim.fn.fnamemodify(sln_path, ":t:r")
  local project_name = solution_name .. "." .. name
  local output = polyfills.fs.joinpath(folder_path, project_name)
  return {
    sln_path = sln_path,
    output = output,
    project_name = project_name,
  }
end

local function create_and_link_project(name, type)
  local args = get_dotnet_new_args(name)
  if args == nil then
    --No sln
    args = {
      project_name = name,
      output = ".",
    }
  end
  vim.fn.jobstart(string.format("dotnet new %s -n %s -o %s", type, args.project_name, args.output), {
    stdout_buffered = true,
    on_exit = function(_, code)
      if code ~= 0 then
        logger.error("Failed to create project")
      else
        logger.info("Project created")
        if args.sln_path ~= nil then sln_add_project(args.sln_path, args.output) end
      end
    end,
  })
end

local function create_config_file(type)
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local sln_path = sln_parse.find_solution_file()

  local folder_path = sln_path ~= nil and vim.fs.dirname(sln_path) or nil
  local output_arg = folder_path ~= nil and string.format("-o %s", folder_path) or ""
  vim.fn.jobstart(string.format("dotnet new %s %s", type, output_arg), {
    stdout_buffered = true,
    on_exit = function(_, code)
      if code ~= 0 then
        logger.error("Command failed")
      else
        logger.info("Config file created")
      end
    end,
  })
end

local templates = {
  {
    display = "Solution file",
    type = "config",
    run = function() create_config_file("sln") end,
  },
  {
    display = "nuget.config",
    type = "config",
    run = function() create_config_file("nugetconfig") end,
  },
  {
    display = ".gitignore",
    type = "config",
    run = function()
      vim.fn.jobstart(string.format("dotnet new gitignore", type), {
        stdout_buffered = true,
        on_exit = function(_, code)
          if code ~= 0 then
            logger.error("Command failed")
          else
            logger.info(".gitignore file created")
          end
        end,
      })
    end,
  },
  {
    display = "global.json file",
    type = "config",
    run = function() create_config_file("globaljson") end,
  },
  {
    display = ".editorconfig file",
    type = "config",
    run = function() create_config_file("editorconfig") end,
  },
  {
    display = "xUnit Test Project",
    type = "project",
    run = function(name) create_and_link_project(name, "xunit") end,
  },
  {
    display = "NUnit Test Project",
    type = "project",
    run = function(name) create_and_link_project(name, "nunit") end,
  },
  {
    display = "Blazor",
    type = "project",
    run = function(name) create_and_link_project(name, "blazor") end,
  },
  {
    display = "ASP.NET Core with React.js",
    type = "project",
    run = function(name) create_and_link_project(name, "react") end,
  },
  {
    display = "ASP.NET Core with Angular",
    type = "project",
    run = function(name) create_and_link_project(name, "angular") end,
  },
  {
    display = "ASP.NET Core Web API",
    type = "project",
    run = function(name) create_and_link_project(name, "webapi") end,
  },
  {
    display = "ASP.NET Core Web API F#",
    type = "project",
    run = function(name) create_and_link_project(name, "webapi --language F#") end,
  },
  {
    display = "ASP.NET Core Empty",
    type = "project",
    run = function(name) create_and_link_project(name, "web") end,
  },
  {
    display = "ASP.NET Core Empty F#",
    type = "project",
    run = function(name) create_and_link_project(name, "web --language F#") end,
  },
  {
    display = "ASP.NET Core gRPC Service",
    type = "project",
    run = function(name) create_and_link_project(name, "grpc") end,
  },
  {
    display = "Console app",
    type = "project",
    run = function(name) create_and_link_project(name, "console") end,
  },
  {
    display = "Console app F#",
    type = "project",
    run = function(name) create_and_link_project(name, "console --language F#") end,
  },
  {
    display = "Class library",
    type = "project",
    run = function(name) create_and_link_project(name, "classlib") end,
  },
  {
    display = "Class library F#",
    type = "project",
    run = function(name) create_and_link_project(name, "classlib --language F#") end,
  },
  {
    display = "ASP.NET Core Web API (native AOT)",
    type = "project",
    run = function(name) create_and_link_project(name, "webapiaot") end,
  },
  {
    display = "ASP.NET Core Web App (Model-View-Controller)",
    type = "project",
    run = function(name) create_and_link_project(name, "mvc") end,
  },
  {
    display = "ASP.NET Core Web App (Razor Pages)",
    type = "project",
    run = function(name) create_and_link_project(name, "razor") end,
  },
  {
    display = "Blazor server",
    type = "project",
    run = function(name) create_and_link_project(name, "blazorserver") end,
  },
  {
    display = "Blazor WebAssembly Standalone App",
    type = "project",
    run = function(name) create_and_link_project(name, "blazorwasm") end,
  },
}

M.new = function()
  local picker = require("easy-dotnet.picker")
  local template = picker.pick_sync(nil, templates, "Select type")
  if template.type == "project" then
    vim.cmd("startinsert")
    --TODO: telescope
    vim.ui.input({ prompt = string.format("Enter name for %s", template.display) }, function(input)
      if input == nil then
        logger.error("No name provided")
        return
      end
      vim.cmd("stopinsert")
      coroutine.wrap(function() template.run(input) end)()
    end)
  else
    template.run()
  end
end

local function name_input_sync() return vim.fn.input("Enter name:") end

---@param path string
---@param cb function | nil
M.create_new_item = function(path, cb)
  path = path or "."
  local template = require("easy-dotnet.picker").pick_sync(nil, {
    { value = "buildprops", display = "MSBuild Directory.Build.props File", type = "MSBuild/props" },
    { value = "packagesprops", display = "MSBuild Directory.Packages.props File", type = "MSBuild/props" },
    { value = "buildtargets", display = "MSBuild Directory.Build.targets File", type = "MSBuild/props" },
    { value = "apicontroller", display = "Api Controller", type = "Code" },
    { value = "interface", display = "Interface", type = "Code" },
    { value = "class", display = "Class", type = "Code" },
    { value = "mvccontroller", display = "MVC Controller", type = "Code" },
    { value = "viewimports", display = "MVC ViewImports", type = "Code" },
    { value = "viewstart", display = "MVC ViewStart", type = "Code" },
    { value = "razorcomponent", display = "Razor Component", type = "Code" },
    { value = "page", display = "Razor Page", type = "Code" },
    { value = "view", display = "Razor View", type = "Code" },
    { value = "nunit-test", display = "NUnit 3 Test Item", type = "Test/NUnit" },
    { value = "gitignore", display = "Dotnet Gitignore File", type = "Config" },
    { value = "tool-manifest", display = "Dotnet Local Tool Manifest File", type = "Config" },
    { value = "editorconfig", display = "EditorConfig File", type = "Config" },
    { value = "globaljson", display = "Global.json File", type = "Config" },
    { value = "nugetconfig", display = "NuGet Config", type = "Config" },
    { value = "webconfig", display = "Web Config", type = "Config" },
    { value = "solution", display = "Solution", type = "Config" },
  }, "Type")

  assert(template)

  local args = ""

  if template.type == "Code" then
    local name = name_input_sync()
    args = string.format("-n %s", name)
  elseif template.type == "Config" then
    local name = name_input_sync()
    args = string.format("-n %s", name)
  elseif template.type == "Test/NUnit" then
    local name = name_input_sync()
    args = string.format("-n %s", name)
  end

  local cmd = string.format("dotnet new %s -o %s %s", template.value, path, args)
  vim.fn.jobstart(cmd, {
    on_stderr = function(_, data)
      for _, value in ipairs(data) do
        logger.error(value)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then logger.error("Command failed") end
      if cb then cb() end
    end,
  })
end

return M
