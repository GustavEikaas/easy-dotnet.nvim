local M = {}

---@param s string
---@return string
local function trim(s)
  -- Match the string and capture the non-whitespace characters
  return s:match("^%s*(.-)%s*$")
end

---@param tests Test[]
local function generate_tree(tests, options, project)
  local offset_indent = 2

  project.children = project.children or {}

  local function count_segments(path)
    local count = 0
    for _ in path:gmatch("[^.]+") do
      count = count + 1
    end
    return count
  end

  ---@param root TestNode Treenode
  ---@param path string E.X neovimdebugproject.test.helpers
  ---@param has_arguments boolean does the test class use classdata,inlinedata etc. Add_ShouldReturnSum(a: -1, b: 1, expected: 0) == true
  ---@param test Test The test the path was referenced from, used for getting stuff like csproject path and sln path
  local function ensure_path(root, path, has_arguments, test)
    local parts = {}
    for part in path:gmatch("[^.]+") do
      table.insert(parts, part)
    end

    local current = root.children
    for i, part in ipairs(parts) do
      if not current[part] then
        local is_full_path = i == #parts
        current[part] = {
          id = test.id,
          name = part,
          namespace = table.concat(parts, ".", 1, i),
          children = {},
          cs_project_path = test.cs_project_path,
          solution_file_path = test.solution_file_path,
          file_path = test.file_path,
          line_number = test.line_number,
          expanded = true,
          indent = (i * 2) - 1 + offset_indent,
          type = is_full_path and "test" or "namespace",
          highlight = not is_full_path and "EasyDotnetTestRunnerDir" or has_arguments and "EasyDotnetTestRunnerPackage" or
              "EasyDotnetTestRunnerTest",
          preIcon = is_full_path == false and options.icons.dir or has_arguments and options.icons.package or
              options.icons.test,
          icon = "",
        }
      end
      current = current[part].children
    end
  end

  for _, test in ipairs(tests) do
    local has_arguments = test.namespace:find("%(") ~= nil
    local base_name = test.namespace:match("([^%(]+)") or test.namespace
    ensure_path(project, base_name, has_arguments, test)

    -- If the test has arguments, add it as a subcase
    if test.namespace:find("%(") then
      local parent = project.children
      for part in base_name:gmatch("[^.]+") do
        parent = parent[part].children
      end
      parent[test.namespace] = {
        name = test.namespace:match("([^.]+%b())$"),
        namespace = test.namespace,
        children = {},
        cs_project_path = test.cs_project_path,
        solution_file_path = test.solution_file_path,
        expanded = true,
        icon = "",
        id = test.id,
        line_number = test.line_number,
        file_path = test.file_path,
        indent = count_segments(base_name) * 2 + offset_indent,
        type = "subcase",
        highlight = "EasyDotnetTestRunnerSubcase",
        preIcon = options.icons.test,
      }
    end
  end

  return project
end


---@class TestNode
---@field id string
---@field name string
---@field namespace string
---@field file_path string
---@field line_number string
---@field solution_file_path string
---@field cs_project_path string
---@field type string
---@field indent number
---@field expanded boolean
---@field highlight string
---@field preIcon string
---@field icon string
---@field children table<string, TestNode>

---@class Project : TestNode
---@field id string
---@field cs_project_path string
---@field solution_file_path string
---@field full_name string
---@field hidden boolean
---@field collapsable boolean
---@field expand table
---@field icons table


---@param tests Test[]
---@return Project
local function expand_test_names_with_flags(tests, options, project)
  local tree = generate_tree(tests, options, project)
  return tree
end

local function merge_tables(table1, table2)
  return vim.tbl_deep_extend("keep", table1, table2)
end

local default_options = require("easy-dotnet.options").test_runner

--- @class Highlight
--- @field group string
--- @field column_start number | nil
--- @field column_end number | nil

--- @class Test
--- @field id string
--- @field type "csproject" | "sln" | "namespace" | "test" | "subcase" | "test_group"
--- @field solution_file_path string
--- @field cs_project_path string
--- @field name string
--- @field full_name string
--- @field namespace string
--- @field preIcon string
--- @field collapsable boolean
--- @field indent number
--- @field hidden boolean
--- @field expand table | nil
--- @field icon string | nil
--- @field highlight string | Highlight| nil
--- @field file_path string | nil
--- @field line_number number | nil


---@param project Test
---@param options TestRunnerOptions
---@param sdk_path string
---@param dotnet_project DotnetProject
---@param on_job_finished function
local function discover_tests_for_project_and_update_lines(project, win, options, dotnet_project, sdk_path,
                                                           on_job_finished)
  local vstest_dll = vim.fs.joinpath(sdk_path, "vstest.console.dll")
  local absolute_dll_path = vim.fs.normalize(vim.fs.joinpath(vim.fn.getcwd(), dotnet_project.get_dll_path()))
  local outfile = vim.fs.normalize(os.tmpname())
  local script_path = require("easy-dotnet.test-runner.discovery").get_script_path()
  local command = string.format("dotnet fsi %s %s %s %s", script_path, vstest_dll,
    absolute_dll_path, outfile)

  local tests = {}
  vim.fn.jobstart(command, {
    on_stderr = function(_, data)
      if #data > 0 and #trim(data[1]) > 0 then
        print(vim.inspect(data))
        error("Failed")
      end
    end,
    ---@param code number
    on_exit = function(_, code)
      on_job_finished()
      if code ~= 0 then
        --TODO: check if project was not built
        vim.notify(string.format("Discovering tests for %s failed", project.name))
      else
        local file = io.open(outfile)
        if file == nil then
          error("Discovery script emitted no file for " .. project.name)
        end

        for line in file:lines() do
          local success, json_test = pcall(function()
            return vim.fn.json_decode(line)
          end)

          if success then
            if #line ~= 2 then
              table.insert(tests, json_test)
            end
          else
            print("Malformed JSON: " .. line)
          end
        end

        local success = pcall(function()
          os.remove(outfile)
        end)

        if not success then
          print("Failed to delete tmp file " .. outfile)
        end

        ---@type Test[]
        local converted = {}
        for _, value in ipairs(tests) do
          --HACK: This is necessary for MSTest cases where name is not a namespace.classname but rather classname
          local name = value.Name:find("%.") and value.Name or value.Namespace
          ---@type Test
          local test = {
            id = value.Id,
            name = name,
            full_name = name,
            namespace = name,
            file_path = value.FilePath,
            line_number = value.Linenumber,
            preIcon = "",
            indent = 0,
            collapsable = true,
            type = "test",
            icon = "",
            hidden = true,
            expand = {},
            highlight = "EasyDotnetTestRunnerTest",
            cs_project_path = project.cs_project_path,
            solution_file_path = project.solution_file_path
          }
          table.insert(converted, test)
        end
        local project_tree = expand_test_names_with_flags(converted, options, project)


        --TODO: multiple sln support?
        win.tree.children[project.name] = project_tree
        win.refreshTree()
      end
    end
  })
end

local function refresh_runner(options, win, solutionFilePath, sdk_path)
  if #win.jobs > 0 then
    vim.notify("Cant refresh while waiting for pending jobs", vim.log.levels.WARN)
    return
  end
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local async = require("easy-dotnet.async-utils")

  if options.noRestore == false then
    vim.notify("Restoring")
    local _, restore_err, restore_code = async.await(async.job_run_async)({ "dotnet", "restore", solutionFilePath })

    if restore_code ~= 0 then
      error("Restore failed " .. vim.inspect(restore_err))
    end
  end
  if options.noBuild == false then
    vim.notify("Building")
    local _, build_err, build_code = async.await(async.job_run_async)({ "dotnet", "build", solutionFilePath,
      "--no-restore" })
    if build_code ~= 0 then
      error("Build failed " .. vim.inspect(build_err))
    end
  end

  ---@type Test[]
  local lines = {}

  ---@type TestNode
  local sln = {
    id = "",
    solution_file_path = solutionFilePath,
    cs_project_path = "",
    type = "sln",
    preIcon = options.icons.sln,
    name = solutionFilePath:match("([^/\\]+)$"),
    full_name = solutionFilePath:match("([^/\\]+)$"),
    file_path = "",
    line_number = "",
    indent = 0,
    namespace = "",
    hidden = false,
    collapsable = true,
    icon = "",
    expand = {},
    highlight = "EasyDotnetTestRunnerSolution",
    expanded = true,
    children = {}
  }
  win.tree = sln
  table.insert(lines, sln)

  local projects = sln_parse.get_projects_from_sln(solutionFilePath)

  for _, value in ipairs(projects) do
    if value.isTestProject == true then
      ---@type Test
      local project = {
        id = "",
        children = {},
        cs_project_path = value.path,
        solution_file_path = solutionFilePath,
        namespace = "",
        type = "csproject",
        expanded = true,
        name = value.name,
        full_name = value.name,
        indent = 2,
        preIcon = options.icons.project,
        hidden = false,
        collapsable = true,
        icon = "",
        expand = {},
        highlight = "EasyDotnetTestRunnerProject"
      }
      local on_job_finished = win.appendJob(value.name, "Discovery")
      --Performance reasons
      if not value.version then
        vim.schedule(function()
          discover_tests_for_project_and_update_lines(project, win, options, value, sdk_path, on_job_finished)
        end)
      else
        discover_tests_for_project_and_update_lines(project, win, options, value, sdk_path, on_job_finished)
      end
    end
  end

  win.refreshTree()
end

---@param options TestRunnerOptions
---@param sdk_path string
local function open_runner(options, sdk_path)
  local win = require("easy-dotnet.test-runner.render")
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
  local error_messages = require("easy-dotnet.error-messages")

  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_project_file()
  if solutionFilePath == nil then
    vim.notify(error_messages.no_project_definition_found)
    return
  end

  local is_reused = win.buf ~= nil

  win.buf_name = "Test manager"
  win.filetype = "easy-dotnet"
  --TODO: make plugin options state
  options.sdk_path = sdk_path
  win.setOptions(options).setKeymaps(require("easy-dotnet.test-runner.keymaps")).render(options.viewmode)

  if is_reused then
    return
  end

  refresh_runner(options, win, solutionFilePath, sdk_path)
end

M.refresh = function(options, sdk_path, args)
  local win = require("easy-dotnet.test-runner.render")
  if #win.jobs > 0 then
    vim.notify("Cant refresh while waiting for pending jobs", vim.log.levels.WARN)
    return
  end

  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
  local error_messages = require("easy-dotnet.error-messages")
  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_project_file()

  if solutionFilePath == nil then
    vim.notify(error_messages.no_project_definition_found)
    return
  end

  if args.build then
    local complete = win.appendJob("build", "Build")
    local co = coroutine.running()
    local command = string.format("dotnet build %s", solutionFilePath)
    vim.fn.jobstart(command, {
      on_exit = function(_, b, _)
        coroutine.resume(co)
        if b == 0 then
          vim.notify("Built successfully")
        else
          vim.notify("Build failed", vim.log.levels.ERROR)
        end
      end,
    })
    coroutine.yield()
    complete()
  end

  local is_active = win.buf ~= nil
  if not is_active then
    error("Testrunner not initialized")
  end
  refresh_runner(options, win, solutionFilePath, sdk_path)
end

M.runner = function(options, sdk_path)
  ---@type TestRunnerOptions
  local mergedOpts = merge_tables(options or {}, default_options)

  coroutine.wrap(
    function()
      open_runner(mergedOpts, sdk_path)
    end
  )()
end


return M
