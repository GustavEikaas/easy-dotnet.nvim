local win = require("easy-dotnet.test-runner.render")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local error_messages = require("easy-dotnet.error-messages")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local logger = require("easy-dotnet.logger")
local qf_list = require("easy-dotnet.build-output.qf-list")
local current_solution = require("easy-dotnet.current_solution")

---@class easy-dotnet.TestRunner.Module
---@field client easy-dotnet.RPC.Client.Dotnet

---@type easy-dotnet.TestRunner.Module
local M = {
  client = require("easy-dotnet.rpc.rpc").global_rpc_client,
}

---@class easy-dotnet.MSBuild.BuildJob
---@field state "pending" | "success" | "error"
---@field name "build"

---@class easy-dotnet.Job.DiscoverJob
---@field state "pending" | "success" | "error"
---@field name "discover"

---@class easy-dotnet.TestRunner.Node
---@field id string
---@field job easy-dotnet.MSBuild.BuildJob | easy-dotnet.Job.DiscoverJob | nil
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
---@field pretty_stack_trace RPC_PrettyStackTrace[] \ nil
---@field failing_frame RPC_PrettyStackTrace \ nil
---@field error_message string[] \ nil
---@field std_out string[] \ nil
---@field framework string
---@field is_MTP boolean
---@field refresh function | nil
---@field children table<string, easy-dotnet.TestRunner.Node>

---@class easy-dotnet.Highlight
---@field group string
---@field column_start number | nil
---@field column_end number | nil

---@class easy-dotnet.TestRunner.Test
---@field id string
---@field display_name string
---@field solution_file_path string
---@field cs_project_path string
---@field namespace string
---@field file_path string | nil
---@field line_number number | nil
---@field runtime string | nil

---@param project_path string path to csproject file
---@return boolean indicating success
function M.request_build(project_path)
  qf_list.clear_all()
  local co = coroutine.running()
  local success = false

  M.client.msbuild:msbuild_build({ targetPath = project_path, configuration = nil }, function(response)
    if not response.success then qf_list.set_project_diagnostics(project_path, response.errors) end
    success = response.success == true
    coroutine.resume(co)
  end)
  coroutine.yield()
  return success
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

---@param root easy-dotnet.TestRunner.Node Treenode
---@param path string E.X neovimdebugproject.test.helpers
---@param has_arguments boolean does the test class use classdata,inlinedata etc. Add_ShouldReturnSum(a: -1, b: 1, expected: 0) == true
---@param test easy-dotnet.TestRunner.Test The test the path was referenced from, used for getting stuff like csproject path and sln path
---@param options easy-dotnet.TestRunner.Options
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

---@param tests easy-dotnet.TestRunner.Test[]
---@param options easy-dotnet.TestRunner.Options
---@param project easy-dotnet.TestRunner.Node
---@return easy-dotnet.TestRunner.Node
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

---@param dotnet_project easy-dotnet.Project.Project
---@param solution_file_path string
---@param options table
---@param refresh function | nil
---@return easy-dotnet.TestRunner.Node
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

local function register_rpc_discovered_tests(tests, project, options)
  if #tests == 0 then
    win.tree.children[project.name] = nil
    win.refreshTree()
    return
  end

  ---@type easy-dotnet.TestRunner.Test[]
  local converted = vim.tbl_map(
    ---@param discovered_test easy-dotnet.RPC.DiscoveredTest
    function(discovered_test)
      ---@type easy-dotnet.TestRunner.Test
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

---@param project_node easy-dotnet.TestRunner.Node
---@param options table
---@param co thread
local function handle_rpc_response(project_node, options, co)
  return function(tests)
    register_rpc_discovered_tests(tests, project_node, options)

    project_node.job = nil
    win.refreshTree()

    if co then coroutine.resume(co) end
  end
end

---@param project easy-dotnet.Project.Project
---@param options table
---@param solution_file_path string
local function start_test_discovery(project, options, solution_file_path)
  local co = coroutine.running()

  local project_node = create_test_node_from_dotnet_project(project, solution_file_path, options, function() start_test_discovery(project, options, solution_file_path) end)
  win.tree.children[project_node.name] = project_node

  win.refreshTree()
  project_node.job = { name = "discover", state = "pending" }
  win.refreshTree()

  M.client.test:test_discover({ projectPath = project.path, configuration = "Debug", targetFrameworkMoniker = project_node.framework }, handle_rpc_response(project_node, options, co))

  coroutine.yield()
end

local function refresh_runner(options, solution_file_path)
  --TODO: refactor, basically just want to prevent refresh if discovery, building or running is already in progress
  if #win.jobs > 0 and not (#win.jobs == 1 and win.jobs[1].id == "server") then
    logger.warn("Cant refresh while waiting for pending jobs")
    return
  end

  ---@type easy-dotnet.TestRunner.Node
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

  local test_projects = sln_parse.get_projects_and_frameworks_flattened_from_sln(solution_file_path, function(project) return project.isTestProject or project.isTestPlatformProject end)

  local success = M.request_build(solution_file_path)
  if not success then return end

  for _, value in ipairs(test_projects) do
    M.client:initialize(function()
      coroutine.wrap(function() start_test_discovery(value, options, solution_file_path) end)()
    end)
  end
  win.refreshTree()
end

---@param options easy-dotnet.TestRunner.Options
local function open_runner(options)
  current_solution.get_or_pick_solution(function(solution_path)
    if solution_path == nil then
      logger.error(error_messages.no_project_definition_found)
      return
    end

    local is_reused = win.buf ~= nil and vim.api.nvim_buf_is_valid(win.buf) and win.tree and win.tree.solution_file_path == solution_path

    win.buf_name = "Test manager"
    win.filetype = "easy-dotnet"
    win.setOptions(options).setKeymaps(require("easy-dotnet.test-runner.keymaps").keymaps).render(options.viewmode)

    if is_reused then return end

    refresh_runner(options, solution_path)
  end)
end

M.refresh = function(options)
  options = options or require("easy-dotnet.options").options.test_runner

  if #win.jobs > 0 then
    logger.warn("Cant refresh while waiting for pending jobs")
    return
  end

  current_solution.get_or_pick_solution(function(solution_path)
    solution_path = solution_path or csproj_parse.find_project_file()

    if solution_path == nil then
      logger.error(error_messages.no_project_definition_found)
      return
    end

    local is_active = win.buf ~= nil
    if not is_active then error("Testrunner not initialized") end
    refresh_runner(options, solution_path)
  end)
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
