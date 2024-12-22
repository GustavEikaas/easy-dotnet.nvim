local M = {}

local function sln_add_project(sln_path, project)
  vim.fn.jobstart(string.format("dotnet sln %s add %s", sln_path, project), {
    stdout_buffered = true,
    on_exit = function(_, b)
      if b ~= 0 then
        vim.notify("Failed to link project to solution")
      end
    end
  })
end

local function get_dotnet_new_args(name)
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local sln_path = sln_parse.find_solution_file()
  if sln_path == nil then
    return nil
  end

  local folder_path = sln_path:gsub("[\\/][^\\/]*%.sln$", "")
  local project_name = sln_path:match("[^\\/]+%.sln$"):gsub("%.sln$", "") .. "." .. name
  local output = vim.fs.joinpath(folder_path, project_name)
  return {
    sln_path = sln_path,
    output = output,
    project_name = project_name
  }
end

local function create_and_link_project(name, type)
  local args = get_dotnet_new_args(name)
  if args == nil then
    --No sln
    args = {
      project_name = name,
      output = "."
    }
  end
  vim.fn.jobstart(string.format("dotnet new %s -n %s -o %s", type, args.project_name, args.output), {
    stdout_buffered = true,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("Failed to create project", vim.log.levels.ERROR)
      else
        vim.notify("Project created")
        if args.sln_path ~= nil then
          sln_add_project(args.sln_path, args.output)
        end
      end
    end
  })
end


local function create_config_file(type)
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local sln_path = sln_parse.find_solution_file()

  local folder_path = sln_path ~= nil and sln_path:gsub("[\\/][^\\/]*%.sln$", "") or nil
  local output_arg = folder_path ~= nil and string.format("-o %s", folder_path) or ""
  vim.fn.jobstart(string.format("dotnet new %s %s", type, output_arg), {
    stdout_buffered = true,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("Command failed")
      else
        vim.notify("Config file created")
      end
    end
  })
end

local projects = {
  {
    display = "Solution file",
    type = "config",
    run = function()
      create_config_file("sln")
    end
  },
  {
    display = "nuget.config",
    type = "config",
    run = function()
      create_config_file("nugetconfig")
    end
  },
  {
    display = ".gitignore",
    type = "config",
    run = function()
      vim.fn.jobstart(string.format("dotnet new gitignore", type), {
        stdout_buffered = true,
        on_exit = function(_, code)
          if code ~= 0 then
            vim.notify("Command failed")
          else
            vim.notify(".gitignore file created")
          end
        end
      })
    end
  },
  {
    display = "global.json file",
    type = "config",
    run = function()
      create_config_file("globaljson")
    end
  },
  {
    display = ".editorconfig file",
    type = "config",
    run = function()
      create_config_file("editorconfig")
    end
  },
  {
    display = "xUnit Test Project",
    type = "project",
    run = function(name)
      create_and_link_project(name, "xunit")
    end
  },
  {
    display = "NUnit Test Project",
    type = "project",
    run = function(name)
      create_and_link_project(name, "nunit")
    end
  },
  {
    display = "Blazor",
    type = "project",
    run = function(name)
      create_and_link_project(name, "blazor")
    end
  },
  {
    display = "ASP.NET Core with React.js",
    type = "project",
    run = function(name)
      create_and_link_project(name, "react")
    end
  },
  {
    display = "ASP.NET Core with Angular",
    type = "project",
    run = function(name)
      create_and_link_project(name, "angular")
    end
  },
  {
    display = "ASP.NET Core Web API",
    type = "project",
    run = function(name)
      create_and_link_project(name, "webapi")
    end
  },
  {
    display = "ASP.NET Core Web API F#",
    type = "project",
    run = function(name)
      create_and_link_project(name, "webapi --language F#")
    end
  },
  {
    display = "ASP.NET Core Empty",
    type = "project",
    run = function(name)
      create_and_link_project(name, "web")
    end
  },
  {
    display = "ASP.NET Core Empty F#",
    type = "project",
    run = function(name)
      create_and_link_project(name, "web --language F#")
    end
  },
  {
    display = "ASP.NET Core gRPC Service",
    type = "project",
    run = function(name)
      create_and_link_project(name, "grpc")
    end
  },
  {
    display = "Console app",
    type = "project",
    run = function(name)
      create_and_link_project(name, "console")
    end
  },
  {
    display = "Console app F#",
    type = "project",
    run = function(name)
      create_and_link_project(name, "console --language F#")
    end
  },
  {
    display = "Class library",
    type = "project",
    run = function(name)
      create_and_link_project(name, "classlib")
    end
  },
  {
    display = "Class library F#",
    type = "project",
    run = function(name)
      create_and_link_project(name, "classlib --language F#")
    end
  },
  {
    display = "ASP.NET Core Web API (native AOT)",
    type = "project",
    run = function(name)
      create_and_link_project(name, "webapiaot")
    end
  },
  {
    display = "ASP.NET Core Web App (Model-View-Controller)",
    type = "project",
    run = function(name)
      create_and_link_project(name, "mvc")
    end
  },
  {
    display = "ASP.NET Core Web App (Razor Pages)",
    type = "project",
    run = function(name)
      create_and_link_project(name, "razor")
    end
  },
  {
    display = "Blazor server",
    type = "project",
    run = function(name)
      create_and_link_project(name, "blazorserver")
    end
  },
  {
    display = "Blazor WebAssembly Standalone App",
    type = "project",
    run = function(name)
      create_and_link_project(name, "blazorwasm")
    end
  },
  {
    display = "Clean Architecture Template [Web Api]",
    type = "project",
    run = function(name)
      create_and_link_project(name, "cleanarch")
    end
  }
}


M.new = function()
  local picker = require("easy-dotnet.picker")
  picker.picker(nil, projects, function(i)
    if i.type == "project" then
      vim.cmd('startinsert')
      vim.ui.input({ prompt = string.format("Enter name for %s", i.display) }, function(input)
        if input == nil then
          vim.notify("No name provided")
          return
        end
        vim.cmd('stopinsert')
        i.run(input)
      end)
    else
      i.run()
    end
  end, "Select type")
end

local function name_input_sync()
  local name = ""
  local co = coroutine.running()
  vim.cmd('startinsert')
  vim.ui.input({ prompt = "Enter name" }, function(input)
    if input == nil then
      vim.notify("No name provided")
      return
    end
    vim.cmd('stopinsert')
    name = input
    coroutine.resume(co)
  end)
  coroutine.yield()
  return name
end

---@param path string
---@param cb function | nil
M.create_new_item = function(path, cb)
  local template = require("easy-dotnet.picker").pick_sync(nil,
    {
      { value = "buildprops",     display = "MSBuild Directory.Build.props File",   type = "MSBuild/props" },
      { value = "buildtargets",   display = "MSBuild Directory.Build.targets File", type = "MSBuild/props" },
      { value = "apicontroller",  display = "Api Controller",                       type = "Code" },
      { value = "interface",      display = "Interface",                            type = "Code" },
      { value = "class",          display = "Class",                                type = "Code" },
      { value = "mvccontroller",  display = "MVC Controller",                       type = "Code" },
      { value = "viewimports",    display = "MVC ViewImports",                      type = "Code" },
      { value = "viewstart",      display = "MVC ViewStart",                        type = "Code" },
      { value = "razorcomponent", display = "Razor Component",                      type = "Code" },
      { value = "page",           display = "Razor Page",                           type = "Code" },
      { value = "view",           display = "Razor View",                           type = "Code" },
      { value = "nunit-test",     display = "NUnit 3 Test Item",                    type = "Test/NUnit" },
      { value = "gitignore",      display = "Dotnet Gitignore File",                type = "Config" },
      { value = "tool-manifest",  display = "Dotnet Local Tool Manifest File",      type = "Config" },
      { value = "editorconfig",   display = "EditorConfig File",                    type = "Config" },
      { value = "globaljson",     display = "Global.json File",                     type = "Config" },
      { value = "nugetconfig",    display = "NuGet Config",                         type = "Config" },
      { value = "webconfig",      display = "Web Config",                           type = "Config" },
      { value = "solution",       display = "Solution",                             type = "Config" }
    },
    "Type")

  assert(template)

  local args = ""

  if template.type == "Code" then
    local name = name_input_sync()
    args = string.format("-n %s", name)
  elseif template.type == "MSBuild/props" then
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
        vim.notify(value, vim.log.levels.ERROR)
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
      else
        vim.notify("Command failed")
      end
      if cb then
        cb()
      end
    end
  })
end

return M
