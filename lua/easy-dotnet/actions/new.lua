local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")
local M = {}

local function sln_add_project(sln_path, project_path, cb)
  local cmd = { "dotnet", "sln", sln_path, "add", project_path }

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_exit = function(_, code)
      if code ~= 0 then
        logger.error("Failed to add project to solution.")
      else
        logger.info("Project added to solution successfully.")
        if cb then cb() end
      end
    end,
  })
end

local no_name_templates = {
  ["Microsoft.Standard.QuickStarts.DirectoryProps"] = "Directory.Build.props",
  ["Microsoft.Standard.QuickStarts.DirectoryTargets"] = "Directory.Build.targets",
  ["Microsoft.Standard.QuickStarts.DirectoryPackages"] = "NuGet.Config",
  ["Microsoft.Standard.QuickStarts.EditorConfigFile"] = ".editorconfig",
  ["Microsoft.Standard.QuickStarts.GitignoreFile"] = ".gitignore",
  ["Microsoft.Standard.QuickStarts.GlobalJsonFile"] = "global.json",
  ["Microsoft.Standard.QuickStarts.Nuget.Config"] = "NuGet.Config",
  ["Microsoft.Standard.QuickStarts.Web.Config"] = "web.config",
  ["Microsoft.Standard.QuickStarts.ToolManifestFile"] = "dotnet-tools.json",
}

local function get_active_solution_info()
  local sln_path = current_solution.try_get_selected_solution()
  if sln_path == nil then return nil, nil, nil end

  local folder_path = vim.fs.dirname(sln_path)
  local solution_name = vim.fn.fnamemodify(sln_path, ":t:r")

  return solution_name, folder_path, sln_path
end

local make_project_name = function(name, sln_name)
  local has_opts, options = pcall(require, "easy-dotnet.options")
  if has_opts and options.get_option then
    local new_opts = options.get_option("new")
    if new_opts and new_opts.project and new_opts.project.prefix == "sln" and sln_name and sln_name ~= "" then return sln_name .. "." .. name end
  end
  return name
end

local function create_floating_window()
  local width = math.floor(vim.o.columns * 0.7)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " New Project Configuration ",
    title_pos = "center",
  })

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "dotnet_new_config"
  vim.bo[buf].modifiable = false

  return buf, win
end

local function prompt_for_param(param, current_val, callback)
  local prompt_text = "Edit " .. param.name

  if param.dataType == "bool" then
    local new_val = "true"
    if current_val == "true" or current_val == true then new_val = "false" end
    callback(new_val)
    return
  end

  if param.dataType == "choice" then
    local choices = {}
    for key, val in pairs(param.choices or {}) do
      local display = val
      if display == nil or display == "" then display = key end
      table.insert(choices, { display = display, value = key })
    end
    require("easy-dotnet.picker").picker(nil, choices, function(choice_val) callback(choice_val.value) end, prompt_text, true, true)
    return
  end

  vim.ui.input({ prompt = prompt_text, default = tostring(current_val or "") }, function(input)
    if input then callback(input) end
  end)
end

local function show_confirmation_ui(initial_name, initial_path, param_definitions, collected_values, final_cb)
  vim.cmd.stopinsert()

  local buf, win = create_floating_window()

  local state = {
    name = initial_name,
    path = initial_path,
    params = collected_values,
  }

  local action_map = {}

  local function render()
    vim.bo[buf].modifiable = true

    local lines = {}
    action_map = {}

    table.insert(lines, "Confirm Project Creation")
    table.insert(lines, string.rep("=", 20))
    table.insert(lines, "")

    local name_line = string.format("  Project Name: %s", state.name)
    table.insert(lines, name_line)
    action_map[#lines] = function()
      vim.ui.input({ prompt = "Project Name: ", default = state.name }, function(input)
        if input then
          state.name = input
          render()
        end
      end)
    end

    local path_line = string.format("  Output Path:  %s", state.path)
    table.insert(lines, path_line)
    action_map[#lines] = function()
      vim.ui.input({ prompt = "Output Path: ", default = state.path, completion = "dir" }, function(input)
        if input then
          state.path = input
          render()
        end
      end)
    end

    table.insert(lines, "")
    table.insert(lines, "[ Parameters ] (Press <Enter> to edit)")
    table.insert(lines, string.rep("-", 40))

    table.sort(param_definitions, function(a, b)
      if a.isRequired and not b.isRequired then return true end
      if not a.isRequired and b.isRequired then return false end
      return a.name < b.name
    end)

    for _, param in ipairs(param_definitions) do
      local val = state.params[param.name]
      local is_req = param.isRequired
      local marker = is_req and "*" or " "

      local val_str = tostring(val)
      if val_str == "" then val_str = "<empty>" end

      local prefix_str = string.format(" %s %-20s", marker, param.name)
      local sep_str = " : "
      local line_str = prefix_str .. sep_str .. val_str

      table.insert(lines, line_str)

      local current_line_idx = #lines - 1
      local name_start = 3
      local name_end = 3 + #param.name
      local val_start = #prefix_str + #sep_str

      action_map[#lines] = {
        action = function()
          prompt_for_param(param, state.params[param.name], function(new_val)
            state.params[param.name] = new_val
            render()
          end)
        end,
        hl = {
          row = current_line_idx,
          name_range = { name_start, name_end },
          val_range = { val_start, -1 },
        },
      }
    end

    table.insert(lines, "")
    table.insert(lines, "[ Actions ]")
    table.insert(lines, "  [C]reate Project")
    table.insert(lines, "  [Q]uit")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local ns_id = vim.api.nvim_create_namespace("DotnetNewUI")
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

    vim.api.nvim_buf_add_highlight(buf, ns_id, "Title", 0, 0, -1)

    vim.api.nvim_buf_add_highlight(buf, ns_id, "Keyword", 3, 0, 15)
    vim.api.nvim_buf_add_highlight(buf, ns_id, "String", 3, 16, -1)

    vim.api.nvim_buf_add_highlight(buf, ns_id, "Keyword", 4, 0, 15)
    vim.api.nvim_buf_add_highlight(buf, ns_id, "String", 4, 16, -1)

    local count = #lines
    vim.api.nvim_buf_add_highlight(buf, ns_id, "String", count - 2, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns_id, "Comment", count - 1, 0, -1)

    for _, data in pairs(action_map) do
      if type(data) == "table" and data.hl then
        local h = data.hl
        vim.api.nvim_buf_add_highlight(buf, ns_id, "Identifier", h.row, h.name_range[1], h.name_range[2])
        vim.api.nvim_buf_add_highlight(buf, ns_id, "String", h.row, h.val_range[1], h.val_range[2])
      end
    end

    vim.bo[buf].modifiable = false
  end

  render()

  local function on_cr()
    local cursor_row = vim.api.nvim_win_get_cursor(win)[1]
    local item = action_map[cursor_row]

    if item then
      if type(item) == "function" then
        item()
      elseif type(item) == "table" then
        item.action()
      end
    else
      local line = vim.api.nvim_buf_get_lines(buf, cursor_row - 1, cursor_row, false)[1]
      if line:find("Create Project") then
        vim.api.nvim_win_close(win, true)
        final_cb(state.name, state.path, state.params)
      elseif line:find("Quit") then
        vim.api.nvim_win_close(win, true)
        print("Cancelled.")
      end
    end
  end

  local opts = { buffer = buf, silent = true, nowait = true }

  vim.keymap.set("n", "<CR>", on_cr, opts)

  vim.keymap.set("n", "C", function()
    vim.api.nvim_win_close(win, true)
    final_cb(state.name, state.path, state.params)
  end, opts)

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
    print("Cancelled.")
  end, opts)

  vim.keymap.set("n", "Q", function()
    vim.api.nvim_win_close(win, true)
    print("Cancelled.")
  end, opts)
end

function M.new()
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client

  client:initialize(function()
    client.template_engine:template_list(function(templates)
      local choices = vim.tbl_map(function(value) return { value = value, display = value.displayName } end, templates)

      require("easy-dotnet.picker").picker(nil, choices, function(selection)
        local tmpl = selection.value
        local sln_name, sln_folder, sln_fullpath = get_active_solution_info()

        local base_path = vim.fn.getcwd()
        if sln_folder then base_path = sln_folder end

        local function continue_with_name(name)
          local suggested_path = base_path
          if tmpl.type == "project" then suggested_path = vim.fs.joinpath(base_path, name) end

          vim.ui.input({ prompt = "Output Directory:", default = suggested_path, completion = "dir" }, function(output_path)
            if not output_path then return end

            client.template_engine:template_parameters(tmpl.identity, function(params)
              local collected = {}
              local required_list = {}

              for _, p in ipairs(params) do
                collected[p.name] = p.defaultValue
                if p.dataType == "bool" and (p.defaultValue == nil or p.defaultValue == "") then collected[p.name] = "false" end

                if p.isRequired then table.insert(required_list, p) end
              end

              local function process_required(index)
                if index > #required_list then
                  local is_project = (tmpl.type == "project")
                  local has_optional_params = #params > #required_list

                  if not is_project and not has_optional_params then
                    client.template_engine:template_instantiate(tmpl.identity, name, output_path, collected, function() print(string.format("Created %s in %s", name, output_path)) end)
                    return
                  end

                  show_confirmation_ui(name, output_path, params, collected, function(final_name, final_path, final_params)
                    client.template_engine:template_instantiate(tmpl.identity, final_name, final_path, final_params, function()
                      print(string.format("Created %s in %s", final_name, final_path))

                      if tmpl.type == "project" and sln_fullpath then sln_add_project(sln_fullpath, final_path) end
                    end)
                  end)
                  return
                end

                local p = required_list[index]
                prompt_for_param(p, collected[p.name], function(val)
                  collected[p.name] = val
                  process_required(index + 1)
                end)
              end

              process_required(1)
            end)
          end)
        end

        local auto_name = no_name_templates[tmpl.identity]
        if auto_name then
          continue_with_name(auto_name)
        else
          vim.ui.input({ prompt = "Project Name:", default = "MyItem" }, function(input_name)
            if not input_name then return end

            local final_name = input_name
            if tmpl.type == "project" then final_name = make_project_name(input_name, sln_name) end

            continue_with_name(final_name)
          end)
        end
      end, "Select Template", false, true)
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
