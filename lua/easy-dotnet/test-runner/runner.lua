local win = require("easy-dotnet.test-runner.render")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local error_messages = require("easy-dotnet.error-messages")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local logger = require("easy-dotnet.logger")
local extensions = require("easy-dotnet.extensions")

local M = {
  sdk_path = nil,
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

---@class BuildJob
---@field state "pending" | "success" | "error"
---@field name "build"

---@class DiscoverJob
---@field state "pending" | "success" | "error"
---@field name "discover"

---@class TestNode
---@field id string
---@field job BuildJob | DiscoverJob | nil
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
---@field refresh function | nil
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

local function dump_to_file(obj, filepath)
  local serialized = vim.inspect(obj)
  local f = io.open(filepath, "w")
  if not f then error("Could not open file: " .. filepath) end
  f:write(serialized)
  f:close()
end

local function request_build(sln_path)
  local client = M._server.client
  if not client then error("RPC client not initialized") end
  local co = coroutine.running()
  local success = false

  client.request("msbuild/build", { request = { targetPath = sln_path, configuration = nil } }, function(response)
    if response.error then
      vim.schedule(function() vim.notify(string.format("[%s]: %s", response.error.code, response.error.message), vim.log.levels.ERROR) end)
      if response.error.data then
        local file = vim.fs.normalize(os.tmpname())
        dump_to_file(response, file)
        logger.error("Crash dump written at " .. file)
      end
      return
    end
    success = response.result.success == true
    coroutine.resume(co)
  end)
  coroutine.yield()
  return success
end

local function start_server(solution_file_path)
  if M._server.ready then return end
  local server_started = win.appendJob("server", "Server")
  local server_ready_prefix = "Named pipe server started: "

  local is_negotiating = false

  local handle = vim.fn.jobstart({ "dotnet", "easydotnet" }, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if M._server.ready or is_negotiating then return end
      if data then
        for _, line in ipairs(data) do
          if line:find(server_ready_prefix, 1, true) then
            local pipename = line:sub(#server_ready_prefix + 1)
            M._server.pipe_name = vim.trim(pipename)
            M._server.client = require("easy-dotnet.test-runner.rpc-client")
            local full_pipe_path
            if extensions.isWindows() then
              full_pipe_path = [[\\.\pipe\]] .. M._server.pipe_name
            elseif extensions.isDarwin() then
              full_pipe_path = os.getenv("TMPDIR") .. "CoreFxPipe_" .. M._server.pipe_name
            else
              full_pipe_path = "/tmp/CoreFxPipe_" .. M._server.pipe_name
            end

            is_negotiating = true
            M._server.client.setup({ pipe_path = full_pipe_path, debug = false })
            M._server.client.connect(function()
              vim.schedule(function()
                M._server.client.request("initialize", {
                  request = {
                    clientInfo = { name = "EasyDotnet", version = "0.0.5" },
                    projectInfo = { solutionFilePath = solution_file_path, rootDir = vim.fs.normalize(vim.fn.getcwd()) },
                  },
                }, function(response)
                  if response.error then
                    vim.schedule(function() vim.notify(string.format("[%s]: %s", response.error.code, response.error.message), vim.log.levels.ERROR) end)
                    M._server.ready = false
                    is_negotiating = false
                    server_started()
                    return
                  end

                  M._server.ready = true
                  vim.schedule(function()
                    server_started()
                    for _, cb in ipairs(M._server.callbacks) do
                      pcall(cb)
                    end
                    is_negotiating = false
                    M._server.callbacks = {}
                  end)
                end)
              end)
            end)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then logger.warn("[server stderr] " .. line) end
        end
      end
    end,
    on_exit = function(_, code, _)
      vim.notify("Testrunner server exited with code " .. code, code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
      M._server.ready = false
      M._server.id = nil
    end,
  })

  if handle <= 0 then
    error("Failed to start testrunner server")
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

local function update_indent_recursively(node, base_indent)
  node.indent = base_indent
  for _, child in pairs(node.children or {}) do
    update_indent_recursively(child, base_indent + 2)
  end
end

local function flatten_namespaces(node)
  for _, child in pairs(node.children or {}) do
    flatten_namespaces(child)
  end

  while true do
    local keys = vim.tbl_keys(node.children or {})

    if #keys == 1 then
      local only_key = keys[1]
      local child = node.children[only_key]

      if child.type == "namespace" and node.type == "namespace" then
        local merged = vim.deepcopy(child)
        merged.name = node.name .. "." .. child.name
        merged.namespace = child.namespace
        update_indent_recursively(merged, node.indent)

        for k in pairs(node) do
          node[k] = nil
        end
        for k, v in pairs(merged) do
          node[k] = v
        end
      else
        break
      end
    else
      break
    end
  end
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

  for _, child in pairs(project.children) do
    flatten_namespaces(child)
  end

  return project
end

---@param dotnet_project DotnetProject
---@param solution_file_path string
---@param options table
---@param refresh function | nil
---@return TestNode
local function create_test_node_from_dotnet_project(dotnet_project, solution_file_path, options, refresh)
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
    refresh = refresh,
  }
end

---@param file string
---@return RPC_DiscoveredTest[]
local function json_decode_out_file(file)
  local ok, contents = pcall(vim.fn.readfile, file)

  if not ok then
    logger.warn("File does not exist ")
    contents = { "[]" }
  end
  if #contents == 1 and contents[1] == "[]" then return {} end
  pcall(vim.loop.fs_unlink, file)
  ---@type RPC_DiscoveredTest[]
  return vim.tbl_map(function(line) return vim.fn.json_decode(line) end, contents)
end

local function register_rpc_discovered_tests(tests, project, options)
  if #tests == 0 then
    win.tree.children[project.name] = nil
    win.refreshTree()
    return
  end

  ---@type Test[]
  local converted = vim.tbl_map(
    ---@param discovered_test RPC_DiscoveredTest
    function(discovered_test)
      ---@type Test
      return {
        namespace = discovered_test.name,
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
    if #converted > 0 then logger.error(string.format("%s returned %d tests but constructing a tree was not successful", project.name, #converted)) end
  end
  win.refreshTree()
end

---@param project_node TestNode
---@param options table
local function handle_rpc_response(project_node, options)
  ---@param response RPC_Response
  return function(response)
    if response.error then
      vim.schedule(function() vim.notify(string.format("[%s]: %s", response.error.code, response.error.message), vim.log.levels.ERROR) end)
      if response.error.data then
        local file = vim.fs.normalize(os.tmpname())
        dump_to_file(response, file)
        logger.error("Crash dump written at " .. file)
      end

      project_node.job = { name = "discover", state = "error" }
      return
    end

    local tests = json_decode_out_file(response.result.outFile)
    register_rpc_discovered_tests(tests, project_node, options)

    project_node.job = nil
    win.refreshTree()
  end
end

---@param project DotnetProject
---@param options table
---@param sdk_path string
---@param solution_file_path string
local function start_vstest_discovery(project, options, sdk_path, solution_file_path)
  local project_node = create_test_node_from_dotnet_project(project, solution_file_path, options, function() start_vstest_discovery(project, options, sdk_path, solution_file_path) end)
  win.tree.children[project_node.name] = project_node

  project_node.job = { name = "build", state = "pending" }
  win.refreshTree()
  local build_success = request_build(project.path)
  if not build_success then
    project_node.job = { name = "build", state = "error" }
    win.refreshTree()
    return
  end

  project_node.job = { name = "discover", state = "pending" }
  win.refreshTree()

  local vstest_dll = vim.fs.joinpath(sdk_path, "vstest.console.dll")
  local client = M._server.client
  if not client then error("RPC client not initialized") end
  client.request("vstest/discover", { vsTestPath = vstest_dll, dllPath = project.get_dll_path() }, handle_rpc_response(project_node, options))
end

---@param project DotnetProject
local function start_MTP_discovery_for_project(project, options, solution_file_path)
  ---@type TestNode
  local project_node = create_test_node_from_dotnet_project(project, solution_file_path, options, function() start_MTP_discovery_for_project(project, options, solution_file_path) end)
  project_node.job = { state = "pending", name = "build" }
  win.tree.children[project_node.name] = project_node
  win.refreshTree()

  local success = request_build(project.path)
  if not success then
    project_node.job = { name = "build", state = "error" }
    return
  end

  project_node.job = { name = "discover", state = "pending" }
  win.refreshTree()

  local absolute_dll_path = project.get_dll_path()

  local testPath = absolute_dll_path:gsub("%.dll", extensions.isWindows() and "." .. project.msbuild_props.outputType:lower() or "")

  local client = M._server.client
  if not client then error("RPC client not initialized") end
  client.request("mtp/discover", { testExecutablePath = testPath }, handle_rpc_response(project_node, options))
end

local function refresh_runner(options, solution_file_path)
  --TODO: refactor, basically just want to prevent refresh if discovery, building or running is already in progress
  if #win.jobs > 0 and not (#win.jobs == 1 and win.jobs[1].id == "server") then
    logger.warn("Cant refresh while waiting for pending jobs")
    return
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
  win.refreshTree()

  local test_projects = sln_parse.get_projects_and_frameworks_flattened_from_sln(solution_file_path, function(project) return project.isTestProject end)

  ---@param i DotnetProject
  local vs_test_projects = vim.tbl_filter(function(i) return not i.isTestPlatformProject end, test_projects)

  local mtp_projects = vim.tbl_filter(function(i) return i.isTestPlatformProject end, test_projects)

  M._server.wait(function()
    for _, value in ipairs(mtp_projects) do
      coroutine.wrap(function() start_MTP_discovery_for_project(value, options, solution_file_path) end)()
    end
    if #vs_test_projects > 0 then
      local sdk_path = M.sdk_path or require("easy-dotnet.options").options.get_sdk_path()
      M.sdk_path = sdk_path
      for _, value in ipairs(vs_test_projects) do
        coroutine.wrap(function() start_vstest_discovery(value, options, sdk_path, solution_file_path) end)()
      end
    end
  end)

  win.refreshTree()
end

---@param options TestRunnerOptions
local function open_runner(options)
  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end

  local is_reused = win.buf ~= nil and vim.api.nvim_buf_is_valid(win.buf) and win.tree and win.tree.solution_file_path == solutionFilePath

  win.buf_name = "Test manager"
  win.filetype = "easy-dotnet"
  win.setOptions(options).setKeymaps(require("easy-dotnet.test-runner.keymaps").keymaps).render(options.viewmode)

  if is_reused then return end

  start_server(solutionFilePath)
  refresh_runner(options, solutionFilePath)
end

M.refresh = function(options)
  options = options or require("easy-dotnet.options").options.test_runner

  if #win.jobs > 0 then
    logger.warn("Cant refresh while waiting for pending jobs")
    return
  end

  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_project_file()

  if solutionFilePath == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end

  local is_active = win.buf ~= nil
  if not is_active then error("Testrunner not initialized") end
  refresh_runner(options, solutionFilePath)
end

local function run_with_traceback(func)
  local co = coroutine.create(func)
  local ok, err = coroutine.resume(co)

  if not ok then error(debug.traceback(co, err), 0) end
end

M.runner = function(options)
  options = options or require("easy-dotnet.options").options.test_runner
  run_with_traceback(function() open_runner(options) end)
end

return M
