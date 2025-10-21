local polyfills = require("easy-dotnet.polyfills")
local logger = require("easy-dotnet.logger")
local M = {}

local function sln_add_project(sln_path, project, cb)
  vim.fn.jobstart(string.format("dotnet sln %s add %s", sln_path, project), {
    stdout_buffered = true,
    on_exit = function(_, b)
      if b ~= 0 then
        logger.error("Failed to link project to solution")
      else
        if cb then cb() end
      end
    end,
  })
end

local make_project_name = function(name, sln_name)
  local options = require("easy-dotnet.options")
  if options.get_option("new").project.prefix == "sln" then return sln_name .. "." .. name end
  return name
end

local function get_dotnet_new_args(name)
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local sln_path = sln_parse.find_solution_file()
  if sln_path == nil then return nil end

  local folder_path = vim.fs.dirname(sln_path)
  local solution_name = vim.fn.fnamemodify(sln_path, ":t:r")
  local project_name = make_project_name(name, solution_name)
  local output = polyfills.fs.joinpath(folder_path, project_name)
  return {
    sln_path = sln_path,
    output = output,
    project_name = project_name,
  }
end

local function get_project_name_and_output(name)
  local args = get_dotnet_new_args(name)
  if args == nil then
    --No sln
    args = {
      project_name = name,
      output = ".",
    }
  end
  return args
end

local function handle_choices(params, done)
  local selected_params = {}

  local function process_param(param_list)
    if #param_list == 0 then
      if done then done(selected_params) end
      return
    end

    local param = param_list[1]
    local prompt = param.name
    if not param.isRequired then prompt = prompt .. " (optional)" end

    if param.dataType == "bool" then
      local default_bool = (param.defaultValue == "true")

      local options = vim
        .iter({
          { display = "yes", value = true },
          { display = "no", value = false },
        })
        :map(function(opt)
          return {
            display = opt.display .. (opt.value == default_bool and " (default)" or ""),
            value = opt.value,
          }
        end)
        :totable()

      table.sort(options, function(a, b) return a.value == default_bool and b.value ~= default_bool end)

      require("easy-dotnet.picker").picker(nil, options, function(bool_val)
        selected_params[param.name] = bool_val.value
        process_param({ unpack(param_list, 2) })
      end, prompt, false, true)
    elseif param.dataType == "text" or param.dataType == "string" or param.dataType == "integer" then
      vim.ui.input({ prompt = prompt, default = param.defaultValue or "" }, function(input)
        selected_params[param.name] = input or ""
        process_param({ unpack(param_list, 2) })
      end)
    elseif param.dataType == "choice" then
      local choices = {}
      for key, va in pairs(param.choices or {}) do
        local display = va
        if display == nil or display == "" then display = key end
        table.insert(choices, { display = display, value = key })
      end
      require("easy-dotnet.picker").picker(nil, choices, function(choice_val)
        selected_params[param.name] = choice_val.value
        process_param({ unpack(param_list, 2) })
      end, prompt, true, true)
    else
      vim.print("Unhandled dotnet new param type", param)
    end
  end

  process_param(params)
end

local no_name_templates = {
  "Microsoft.Standard.QuickStarts.DirectoryProps",
  "Microsoft.Standard.QuickStarts.DirectoryTargets",
  "Microsoft.Standard.QuickStarts.DirectoryPackages",
  "Microsoft.Standard.QuickStarts.EditorConfigFile",
  "Microsoft.Standard.QuickStarts.GitignoreFile",
  "Microsoft.Standard.QuickStarts.GlobalJsonFile",
  "Microsoft.Standard.QuickStarts.Nuget.Config",
  "Microsoft.Standard.QuickStarts.Web.Config",
  "Microsoft.Standard.QuickStarts.ToolManifestFile",
}

local function prompt_parameters(identity, client, name, cwd, cb)
  client:template_parameters(identity, function(params)
    vim.print("PARAMS", params)
    handle_choices(params, function(res)
      vim.print("RES", res)
      client:template_instantiate(identity, name or "", cwd or vim.fn.getcwd(), res, function()
        if cb then cb() end
      end)
    end)
  end)
end

function M.new()
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  client:initialize(function()
    client.template_engine:template_list(function(templates)
      ---@param value DotnetNewTemplate
      local choices = vim.tbl_map(function(value)
        return {
          value = value,
          display = value.displayName,
        }
      end, templates)
      require("easy-dotnet.picker").picker(nil, choices, function(selection)
        ---@type DotnetNewTemplate
        local val = selection.value
        if val.type == "project" then
          vim.ui.input({ prompt = "Enter name:" }, function(input)
            local args = get_project_name_and_output(input)
            prompt_parameters(val.identity, client.template_engine, args.project_name, args.output, function() sln_add_project(args.sln_path, args.output) end)
          end)
        elseif not vim.tbl_contains(no_name_templates, selection.value.identity) then
          vim.ui.input({ prompt = "Enter name:" }, function(input)
            prompt_parameters(val.identity, client.template_engine, input, nil, function() print("Success") end)
          end)
        else
          prompt_parameters(val.identity, client.template_engine, nil, nil, function() print("Success") end)
        end
      end, "New", false, true)
    end)
  end)
end

local function name_input_sync() return vim.fn.input("Enter name:") end

---@param path string
---@param cb function | nil
M.create_new_item = function(path, cb)
  path = path or "."
  local template = require("easy-dotnet.picker").pick_sync(nil, {
    { value = "buildprops", display = "MSBuild Directory.Build.props File", type = "MSBuild/props", predefined_file_name = "Directory.Build.props" },
    { value = "packagesprops", display = "MSBuild Directory.Packages.props File", type = "MSBuild/props", predefined_file_name = "Directory.Packages.props" },
    { value = "buildtargets", display = "MSBuild Directory.Build.targets File", type = "MSBuild/props", predefined_file_name = "Directory.Build.targets" },
    { value = "apicontroller", display = "Api Controller", type = "Code", extension = ".cs" },
    { value = "interface", display = "Interface", type = "Code", extension = ".cs" },
    { value = "class", display = "Class", type = "Code", extension = ".cs" },
    { value = "record", display = "Record", type = "Code", extension = ".cs" },
    { value = "struct", display = "Struct", type = "Code", extension = ".cs" },
    { value = "enum", display = "Enum", type = "Code", extension = ".cs" },
    { value = "mvccontroller", display = "MVC Controller", type = "Code", extension = ".cs" },
    { value = "viewimports", display = "MVC ViewImports", type = "Code", extension = ".cshtml" },
    { value = "viewstart", display = "MVC ViewStart", type = "Code", extension = ".cshtml" },
    { value = "razorcomponent", display = "Razor Component", type = "Code", extension = ".razor" },
    { value = "page", display = "Razor Page", type = "Code", extension = ".cshtml" },
    { value = "view", display = "Razor View", type = "Code", extension = ".cshtml" },
    { value = "nunit-test", display = "NUnit 3 Test Item", type = "Test/NUnit", extension = ".cs" },
    { value = "gitignore", display = "Dotnet Gitignore File", type = "Config", predefined_file_name = ".gitignore" },
    { value = "tool-manifest", display = "Dotnet Local Tool Manifest File", type = "Config", predefined_file_name = "dotnet-tools.json" },
    { value = "editorconfig", display = "EditorConfig File", type = "Config", predefined_file_name = ".editorconfig" },
    { value = "globaljson", display = "Global.json File", type = "Config", predefined_file_name = "global.json" },
    { value = "nugetconfig", display = "NuGet Config", type = "Config", predefined_file_name = "nuget.config" },
    { value = "webconfig", display = "Web Config", type = "Config", predefined_file_name = "web.config" },
    { value = "solution", display = "Solution", type = "Config", extension = ".sln" },
  }, "Type")

  assert(template)

  path = path or "."
  local args = ""
  local file_name

  if template.predefined_file_name ~= nil then
    file_name = template.predefined_file_name
  else
    local name = name_input_sync()
    if not name or name:match("^%s*$") then
      logger.error("No name provided")
      return
    end
    file_name = name .. template.extension
    args = string.format("-n %s", name)
  end

  local cmd = string.format("dotnet new %s -o %s %s", template.value, path, args)
  local stdout = {}
  vim.fn.jobstart(cmd, {
    on_stderr = function(_, data) vim.list_extend(stdout, data) end,
    on_stdout = function(_, data) vim.list_extend(stdout, data) end,
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.print(stdout)
        logger.error("Command failed")
      end
      if cb then
        local file_path = vim.fs.normalize(vim.fs.joinpath(path, file_name))
        cb(file_path)
      end
    end,
  })
end

return M
