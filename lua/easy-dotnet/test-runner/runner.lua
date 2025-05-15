local logger = require("easy-dotnet.logger")
local extensions = require("easy-dotnet.extensions")
local M = {
  _server = {
    id = nil,
    ready = false,
    callbacks = {},
    wait = nil,
    pipe_name = nil,
    client = nil,
  },
}

M._server.wait = function(cb)
  if M._server.ready then
    pcall(cb)
  else
    table.insert(M._server.callbacks, cb)
  end
end

---@class RPC_DiscoveredTest
---@field id string
---@field namespace? string
---@field name string
---@field displayName string
---@field filePath string
---@field lineNumber? integer

---@class TestNode
---@field id string
---@field name string
---@field displayName string
---@field namespace string
---@field file_path string
---@field line_number number | nil
---@field solution_file_path string
---@field cs_project_path string
---@field type string
---@field indent number
---@field expanded boolean
---@field highlight string
---@field preIcon string
---@field duration string | nil
---@field icon string
---@field expand table | nil
---@field framework string
---@field is_MTP boolean
---@field children table<string, TestNode>

---@class Highlight
---@field group string
---@field column_start number | nil
---@field column_end number | nil

---@class Test
---@field id string
---@field display_name string
---@field solution_file_path string
---@field cs_project_path string
---@field namespace string
---@field file_path string | nil
---@field line_number number | nil
---@field runtime string | nil

local function start_server(win)
  if M._server.ready then return end
  local server_started = win.appendJob("server", "Server")
  local server_ready_prefix = "Named pipe server started: "

  local is_negotiating = false
  local handle = vim.fn.jobstart({ "easydotnet" }, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if M._server.ready or is_negotiating then return end
      if data then
        for _, line in ipairs(data) do
          if line:find(server_ready_prefix, 1, true) then
            local pipename = line:sub(#server_ready_prefix + 1)
            M._server.pipe_name = vim.trim(pipename)
            M._server.client = require("easy-dotnet.test-runner.rpc-client")
            local full_pipe_path = extensions.isWindows() and [[\\.\pipe\]] .. M._server.pipe_name or "/tmp/CoreFxPipe_" .. M._server.pipe_name
            is_negotiating = true
            M._server.client.setup({ pipe_path = full_pipe_path, debug = false })
            M._server.client.connect(function()
              M._server.ready = true
              vim.schedule(function()
                server_started()
                for _, cb in ipairs(M._server.callbacks) do
                  pcall(cb)
                end
                M._server.callbacks = {}
              end)
            end)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then vim.notify("[server stderr] " .. line, vim.log.levels.WARN) end
        end
      end
    end,
    on_exit = function(_, code, _)
      vim.notify("Testrunner server exited with code " .. code, vim.log.levels.INFO)
      M._server.ready = false
      M._server.id = nil
    end,
  })

  if handle <= 0 then
    vim.notify("Failed to start testrunner server", vim.log.levels.ERROR)
    return
  end

  M._server.job_id = handle
  M._server.ready = false
end

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
---@param options TestRunnerOptions
---@param offset_indent integer
local function ensure_path(root, path, has_arguments, test, options, offset_indent)
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
        displayName = test.display_name,
        namespace = table.concat(parts, ".", 1, i),
        cs_project_path = test.cs_project_path,
        solution_file_path = test.solution_file_path,
        file_path = test.file_path,
        line_number = test.line_number,
        expanded = false,
        expand = nil,
        indent = (i * 2) - 1 + offset_indent,
        type = not is_full_path and "namespace" or has_arguments and "test_group" or "test",
        highlight = not is_full_path and "EasyDotnetTestRunnerDir" or has_arguments and "EasyDotnetTestRunnerPackage" or "EasyDotnetTestRunnerTest",
        preIcon = is_full_path == false and options.icons.dir or has_arguments and options.icons.package or options.icons.test,
        icon = "",
        children = {},
        framework = root.framework,
        is_MTP = root.is_MTP,
      }
    end
    current = current[part].children
  end
end

---@param tests Test[]
---@param options TestRunnerOptions
---@param project TestNode
---@return TestNode
local function generate_tree(tests, options, project)
  local offset_indent = 2
  project.children = project.children or {}

  for _, test in ipairs(tests) do
    local has_arguments = test.namespace:find("%(") ~= nil
    local base_name = test.namespace:match("([^%(]+)") or test.namespace
    ensure_path(project, base_name, has_arguments, test, options, offset_indent)

    -- If the test has arguments, add it as a subcase
    if test.namespace:find("%(") then
      local parent = project.children
      for part in base_name:gmatch("[^.]+") do
        parent = parent[part].children
      end
      parent[test.namespace] = {
        name = test.namespace:match("([^.]+%b())$"),
        displayName = test.display_name,
        namespace = test.namespace,
        children = {},
        cs_project_path = test.cs_project_path,
        solution_file_path = test.solution_file_path,
        expanded = false,
        icon = "",
        id = test.id,
        line_number = test.line_number,
        file_path = test.file_path,
        indent = count_segments(base_name) * 2 + offset_indent,
        type = "subcase",
        highlight = "EasyDotnetTestRunnerSubcase",
        preIcon = options.icons.test,
        framework = project.framework,
        is_MTP = project.is_MTP,
      }
    end
  end

  return project
end

---@param dotnet_project DotnetProject
---@param solution_file_path string
---@param options table
---@return TestNode
local function create_test_node_from_dotnet_project(dotnet_project, solution_file_path, options)
  return {
    id = "",
    children = {},
    cs_project_path = dotnet_project.path,
    solution_file_path = solution_file_path,
    namespace = "",
    type = "csproject",
    expanded = false,
    name = dotnet_project.name .. "@" .. dotnet_project.version,
    displayName = "",
    file_path = dotnet_project.path,
    line_number = nil,
    full_name = dotnet_project.name,
    indent = 2,
    preIcon = options.icons.project,
    icon = "",
    expand = {},
    highlight = "EasyDotnetTestRunnerProject",
    framework = dotnet_project.msbuild_props.targetFramework,
    is_MTP = dotnet_project.isTestPlatformProject,
  }
end

---@param file string
---@return RPC_DiscoveredTest[]
local function json_decode_out_file(file)
  local ok, contents = pcall(vim.fn.readfile, file)
  if not ok then contents = { "[]" } end
  if #contents == 1 and contents[1] == "[]" then return {} end
  pcall(vim.loop.fs_unlink, file)
  ---@type RPC_DiscoveredTest[]
  return vim.tbl_map(function(line) return vim.fn.json_decode(line) end, contents)
end

local function register_rpc_discovered_tests(tests, project, options, win, on_job_finished)
  if #tests == 0 then
    win.tree.children[project.name] = nil
    win.refreshTree()
    on_job_finished()
    return
  end

  ---@type Test[]
  local converted = vim.tbl_map(
    ---@param discovered_test RPC_DiscoveredTest
    function(discovered_test)
      --HACK: This is necessary for MSTest cases where name is not a namespace.classname but rather classname
      local name = discovered_test.name:find("%.") and discovered_test.name or discovered_test.namespace or ""
      ---@type Test
      return {
        namespace = name,
        file_path = discovered_test.filePath,
        line_number = discovered_test.lineNumber,
        id = discovered_test.id,
        display_name = discovered_test.displayName,
        cs_project_path = project.cs_project_path,
        solution_file_path = project.solution_file_path,
        runtime = project.framework,
      }
    end,
    tests
  )

  local project_tree = generate_tree(converted, options, project)
  local hasChildren = next(project_tree.children) ~= nil

  if hasChildren then
    win.tree.children[project.name] = project_tree
  else
    win.tree.children[project.name] = nil
  end
  win.refreshTree()
  on_job_finished()
end

---@param projects DotnetProject[]
---@param win table
---@param options table
---@param sdk_path string
---@param solution_file_path string
local function start_batch_vstest_discovery(projects, win, options, sdk_path, solution_file_path)
  ---@param i DotnetProject
  local project_jobs = vim.tbl_map(function(i)
    local project = create_test_node_from_dotnet_project(i, solution_file_path, options)
    local on_job_finished = win.appendJob(project.name, "Discovery")
    win.tree.children[project.name] = project
    win.refreshTree()
    return {
      project = project,
      on_job_finished = on_job_finished,
      dll_path = i.get_dll_path(),
      out_file = vim.fs.normalize(os.tmpname()),
    }
  end, projects)

  local rpc_request = vim.tbl_map(function(i)
    return {
      dllPath = i.dll_path,
      outFile = i.out_file,
    }
  end, project_jobs)

  local function handle_rpc_response(response)
    if response.error then
      --TODO: proper error handling
      vim.schedule(function() vim.notify(string.format("[%s]: %s", response.error.code, response.error.message), vim.log.levels.ERROR) end)
      for _, value in pairs(project_jobs) do
        value.on_job_finished()
      end
      return
    end

    for _, value in pairs(project_jobs) do
      local success = pcall(function()
        local tests = json_decode_out_file(value.out_file)
        register_rpc_discovered_tests(tests, value.project, options, win, value.on_job_finished)
      end)
      if not success then
        logger.error("Failed to register discovered tests for " .. value.project.name)
        value.on_job_finished()
      end
    end
  end

  local vstest_dll = vim.fs.joinpath(sdk_path, "vstest.console.dll")
  coroutine.wrap(function()
    local client = M._server.client
    if not client then error("RPC client not initialized") end
    client.request("vstest/discover", { vsTestPath = vstest_dll, projects = rpc_request }, handle_rpc_response)
  end)()
end

---@param value DotnetProject
local function start_MTP_discovery_for_project(value, win, options, solution_file_path)
  ---@type TestNode
  local project = create_test_node_from_dotnet_project(value, solution_file_path, options)
  local on_job_finished = win.appendJob(project.name, "Discovery")
  win.tree.children[project.name] = project
  win.refreshTree()

  local function handle_rpc_response(response)
    if response.error then
      --TODO: proper error handling
      vim.schedule(function() vim.notify(string.format("[%s]: %s", response.error.code, response.error.message), vim.log.levels.ERROR) end)
      on_job_finished()
      return
    end

    local tests = json_decode_out_file(response.result)
    register_rpc_discovered_tests(tests, project, options, win, on_job_finished)
  end

  local out_file = vim.fs.normalize(os.tmpname())
  local absolute_dll_path = value.get_dll_path()

  local testPath = absolute_dll_path:gsub("%.dll", extensions.isWindows() and "." .. value.msbuild_props.outputType:lower() or "")

  coroutine.wrap(function()
    local client = M._server.client
    if not client then error("RPC client not initialized") end
    client.request("mtp/discover", { outFile = out_file, testExecutablePath = testPath }, handle_rpc_response)
  end)()
end

local function file_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "file"
end

local function refresh_runner(options, win, solution_file_path, sdk_path)
  --TODO: refactor, basically just want to prevent refresh if discovery, building or running is already in progress
  if #win.jobs > 0 and not (#win.jobs == 1 and win.jobs[1].id == "server") then
    logger.warn("Cant refresh while waiting for pending jobs")
    return
  end
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local async = require("easy-dotnet.async-utils")

  if options.noBuild == false then
    logger.info("Building")
    local _, build_err, build_code = async.await(async.job_run_async)({ "dotnet", "build", solution_file_path })
    if build_code ~= 0 then error("Build failed " .. vim.inspect(build_err)) end
  end

  ---@type TestNode
  win.tree = {
    id = "",
    solution_file_path = solution_file_path,
    cs_project_path = "",
    type = "sln",
    preIcon = options.icons.sln,
    name = solution_file_path:match("([^/\\]+)$"),
    displayName = "",
    full_name = solution_file_path:match("([^/\\]+)$"),
    file_path = solution_file_path,
    line_number = nil,
    indent = 0,
    namespace = "",
    icon = "",
    expand = nil,
    highlight = "EasyDotnetTestRunnerSolution",
    expanded = true,
    children = {},
    framework = "",
    is_MTP = false,
  }

  local test_projects = sln_parse.get_projects_and_frameworks_flattened_from_sln(solution_file_path, function(project) return project.isTestProject end)

  ---@param x DotnetProject
  local unbuilt_projects = vim.tbl_filter(function(x) return not file_exists(x.get_dll_path()) end, test_projects)
  if #unbuilt_projects > 0 then
    local complete = win.appendJob("build", "Build")
    local co = coroutine.running()
    local command = string.format("dotnet build %s", solution_file_path)
    vim.fn.jobstart(command, {
      on_exit = function(_, b, _)
        coroutine.resume(co)
        if b == 0 then
          logger.info("Built successfully")
        else
          logger.error("Build failed")
        end
      end,
    })
    coroutine.yield()
    complete()
  end

  ---@param i DotnetProject
  local vs_test_projects = vim.tbl_filter(function(i) return not i.isTestPlatformProject end, test_projects)

  local mtp_projects = vim.tbl_filter(function(i) return i.isTestPlatformProject end, test_projects)

  M._server.wait(function()
    for _, value in ipairs(mtp_projects) do
      start_MTP_discovery_for_project(value, win, options, solution_file_path)
    end
    for _, value in ipairs(vs_test_projects) do
      start_batch_vstest_discovery({ value }, win, options, sdk_path, solution_file_path)
    end
  end)

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
    logger.error(error_messages.no_project_definition_found)
    return
  end

  local is_reused = win.buf ~= nil and vim.api.nvim_buf_is_valid(win.buf) and win.tree and win.tree.solution_file_path == solutionFilePath

  win.buf_name = "Test manager"
  win.filetype = "easy-dotnet"
  --TODO: make plugin options state
  options.sdk_path = sdk_path
  win.setOptions(options).setKeymaps(require("easy-dotnet.test-runner.keymaps")).render(options.viewmode)

  if is_reused then return end

  start_server(win)
  refresh_runner(options, win, solutionFilePath, sdk_path)
end

M.refresh = function(options, sdk_path, args)
  options = options or require("easy-dotnet.options").options.test_runner
  sdk_path = sdk_path or require("easy-dotnet.options").options.get_sdk_path()
  args = args or { build = false }

  local win = require("easy-dotnet.test-runner.render")
  if #win.jobs > 0 then
    logger.warn("Cant refresh while waiting for pending jobs")
    return
  end

  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
  local error_messages = require("easy-dotnet.error-messages")
  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_project_file()

  if solutionFilePath == nil then
    logger.error(error_messages.no_project_definition_found)
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
          logger.info("Built successfully")
        else
          logger.error("Build failed")
        end
      end,
    })
    coroutine.yield()
    complete()
  end

  local is_active = win.buf ~= nil
  if not is_active then error("Testrunner not initialized") end
  refresh_runner(options, win, solutionFilePath, sdk_path)
end

M.runner = function(options, sdk_path)
  options = options or require("easy-dotnet.options").options.test_runner
  sdk_path = sdk_path or require("easy-dotnet.options").options.get_sdk_path()
  coroutine.wrap(function() open_runner(options, sdk_path) end)()
end

return M
