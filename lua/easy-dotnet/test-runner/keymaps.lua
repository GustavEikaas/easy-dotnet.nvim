local M = {}
local window = require("easy-dotnet.test-runner.window")
local runner = require("easy-dotnet.test-runner.runner")
local logger = require("easy-dotnet.logger")
local extensions = require("easy-dotnet.extensions")

---@param node TestNode
---@param options table
local function aggregate_status(node, options)
  if not node.children or next(node.children) == nil then return node.icon end

  local worstStatus = ""

  for _, child in pairs(node.children) do
    local childWorstStatus = aggregate_status(child, options)

    if childWorstStatus == options.icons.failed then
      worstStatus = options.icons.failed
    elseif childWorstStatus == options.icons.skipped and worstStatus ~= options.icons.failed then
      worstStatus = options.icons.skipped
    elseif childWorstStatus == options.icons.passed and worstStatus ~= options.icons.failed and worstStatus ~= options.icons.skipped then
      worstStatus = options.icons.passed
    end
  end

  node.icon = worstStatus
  return worstStatus
end

local function parse_status(result, test_line, options)
  if result.duration then test_line.duration = result.duration end
  --TODO: handle more cases like cancelled etc...
  if result.outcome == "passed" then
    test_line.icon = options.icons.passed
    --TODO: figure this shit out
  elseif result.outcome == "failed" or result.outcome == "error" then
    test_line.icon = options.icons.failed
    if result.errorMessage or result.stackTrace then test_line.expand = vim.split((result.errorMessage or "") .. "\n" .. (result.stackTrace or ""):gsub("^%s+", ""):gsub("\n%s+", "\n"), "\n") end
  elseif result.outcome == "skipped" then
    test_line.icon = options.icons.skipped
  else
    vim.print({
      detail = "encountered unexpected status",
      field = result.outcome,
    })
    test_line.icon = "??"
  end
end

---@param unit_test_results TestCase[]
---@param win table
---@param node TestNode
local test_status_updater = function(unit_test_results, win, node)
  if #unit_test_results == 0 then
    win.traverse(node, function(child)
      if child.icon == "<Running>" then child.icon = "<No status reported>" end
    end)
    win.refreshTree()
    return
  end

  for _, value in ipairs(unit_test_results) do
    win.traverse(node, function(child_node)
      if (child_node.type == "test" or child_node.type == "subcase") and child_node.id == value.id then parse_status(value, child_node, win.options) end
    end)
  end

  aggregate_status(win.tree, win.options)
  win.refreshTree()
end

local function get_test_result_handler(win, node, on_job_finished)
  ---@param rpc_res RPC_Response
  return function(rpc_res)
    ---@type TestCase[]
    local test_results = vim.tbl_map(function(i) return vim.fn.json_decode(i) end, vim.fn.readfile(rpc_res.result.outFile))
    test_status_updater(test_results, win, node)
    on_job_finished()
  end
end

---@param node TestNode
---@param win table
function M.VsTest_Run(node, win, cb)
  ---@type TestNode[]
  local tests = {}
  ---@param child TestNode
  win.traverse_filtered(node, function(child)
    child.icon = "<Running>"
    if child.type == "test" or child.type == "subcase" then table.insert(tests, child) end
  end)

  local _on_job_finished = win.appendJob(node.cs_project_path, "Run", #tests)
  local function on_job_finished()
    _on_job_finished()
    if cb then cb() end
  end

  local filter = vim.tbl_map(function(test) return test.id end, tests)

  local project = require("easy-dotnet.parsers.csproj-parse").get_project_from_project_file(node.cs_project_path)
  local project_framework = project.get_specific_runtime_definition(node.framework)
  local testPath = project_framework.get_dll_path()

  local vstest_dll = vim.fs.joinpath(runner.sdk_path, "vstest.console.dll")
  coroutine.wrap(function()
    local client = require("easy-dotnet.test-runner.runner").client
    client:vstest_run({ vsTestPath = vstest_dll, dllPath = testPath, testIds = filter }, get_test_result_handler(win, node, on_job_finished))
  end)()
end
---@param node TestNode
---@param win table
---@param cb function | nil
function M.MTP_Run(node, win, cb)
  ---@type TestNode[]
  local tests = {}
  ---@param child TestNode
  win.traverse_filtered(node, function(child)
    child.icon = "<Running>"
    if child.type == "test" or child.type == "subcase" then table.insert(tests, child) end
  end)

  local _on_job_finished = win.appendJob(node.cs_project_path, "Run", #tests)
  local on_job_finished = function()
    _on_job_finished()
    if cb then cb() end
  end

  local filter = vim.tbl_map(function(test)
    ---@type RunRequestNode
    return {
      uid = test.id,
      displayName = test.displayName,
    }
  end, tests)

  local project = require("easy-dotnet.parsers.csproj-parse").get_project_from_project_file(node.cs_project_path)
  local project_framework = project.get_specific_runtime_definition(node.framework)

  local testPath = project_framework.get_dll_path():gsub("%.dll", extensions.isWindows() and "." .. project_framework.msbuild_props.outputType:lower() or "")

  coroutine.wrap(function()
    local client = require("easy-dotnet.test-runner.runner").client
    client:mtp_run({ testExecutablePath = testPath, filter = filter }, get_test_result_handler(win, node, on_job_finished))
  end)()
end

---@param node TestNode
local function run_tests(node, win)
  if not win.options.noBuild then
    local build_success = runner.request_build(node.cs_project_path)
    if not build_success then
      logger.error("Failed to build project")
      return
    end
  end
  if node.is_MTP then
    M.MTP_Run(node, win)
    return
  else
    M.VsTest_Run(node, win)
  end
end

local function filter_failed_tests(win)
  if win.filter == nil then
    win.filter = win.options.icons.failed
  else
    win.filter = nil
  end
  win.refreshTree()
end

local function get_path_from_stack_trace(stack_trace)
  stack_trace = table.concat(stack_trace)
  -- Pattern to match the file path and line number
  local pattern = "in%s+(.-):line%s+(%d+)"

  -- Search for the first match
  local path, line = stack_trace:match(pattern)

  -- Return the result as a table
  if path and line then
    return { path = path, line = tonumber(line) }
  else
    return nil -- Return nil if no match is found
  end
end

local function open_stack_trace(line)
  if line.expand == nil then return end

  local path = get_path_from_stack_trace(line.expand)

  local ns_id = require("easy-dotnet.constants").ns_id
  local contents = vim.fn.readfile(line.file_path)

  --TODO: handle fsharp
  local file_float = window.new_float():pos_left():write_buf(contents):buf_set_filetype("csharp"):create()

  local stack_trace = window:new_float():link_close(file_float):pos_right():write_buf(line.expand):create()

  local function go_to_file()
    vim.api.nvim_win_close(file_float.win, true)
    vim.cmd(string.format("edit %s", line.file_path))
    if path == nil or path.line == nil then return end
    vim.api.nvim_win_set_cursor(0, { path.line, 0 })
    vim.api.nvim_buf_add_highlight(0, ns_id, "EasyDotnetTestRunnerFailed", path.line - 1, 0, -1)
  end

  vim.keymap.set("n", "<leader>gf", function() go_to_file() end, { silent = true, noremap = true, buffer = file_float.buf })

  vim.keymap.set("n", "<leader>gf", function() go_to_file() end, { silent = true, noremap = true, buffer = stack_trace.buf })

  if path ~= nil and path.line ~= nil then vim.api.nvim_win_set_cursor(file_float.win, { path.line, 0 }) end
end

M.keymaps = function()
  local keymap = require("easy-dotnet.test-runner.render").options.mappings
  return {
    [keymap.filter_failed_tests.lhs] = { handle = function(_, win) filter_failed_tests(win) end, desc = keymap.filter_failed_tests.desc },
    [keymap.refresh_testrunner.lhs] = {
      ---@param node TestNode
      handle = function(node)
        if node.type == "csproject" then
          coroutine.wrap(function() node.refresh() end)()
        else
          vim.cmd("Dotnet testrunner refresh build")
        end
      end,
      desc = keymap.refresh_testrunner.desc,
    },
    [keymap.debug_test.lhs] = {
      handle = function(node, win)
        if node.type ~= "test" and node.type ~= "test_group" then
          logger.error("Debugging is only supported for tests and test_groups")
          return
        end
        local success, dap = pcall(function() return require("dap") end)
        if not success then
          logger.error("nvim-dap not installed")
          return
        end
        win.hide()
        vim.cmd("edit " .. node.file_path)
        vim.api.nvim_win_set_cursor(0, { node.line_number and (node.line_number - 1) or 0, 0 })
        dap.toggle_breakpoint()

        local dap_configuration = {
          type = "coreclr",
          name = node.name,
          request = "attach",
          processId = function()
            local project_path = node.cs_project_path
            local res = require("easy-dotnet.debugger").start_debugging_test_project(project_path)
            return res.process_id
          end,
        }

        dap.run(dap_configuration)
      end,
      desc = keymap.debug_test.desc,
    },
    [keymap.go_to_file.lhs] = {
      ---@param node TestNode
      handle = function(node, win)
        if node.type == "test" or node.type == "subcase" or node.type == "test_group" then
          if node.file_path ~= nil then
            win.hide()
            vim.cmd("edit " .. node.file_path)
            vim.api.nvim_win_set_cursor(0, { node.line_number and (node.line_number - 1) or 0, 0 })
          end
        else
          logger.warn("Cant go to " .. node.type)
        end
      end,
      desc = keymap.go_to_file.desc,
    },
    [keymap.expand_all.lhs] = {
      handle = function(_, win)
        ---@param node TestNode
        win.traverse(win.tree, function(node) node.expanded = true end)

        win.refreshTree()
      end,
      desc = keymap.expand_all.desc,
    },
    [keymap.expand_node.lhs] = {
      handle = function(target_node, win)
        ---@param node TestNode
        win.traverse(target_node, function(node) node.expanded = true end)

        win.refreshTree()
      end,
      desc = keymap.expand_node.desc,
    },

    [keymap.collapse_all.lhs] = {
      handle = function(_, win)
        ---@param node TestNode
        win.traverse(win.tree, function(node) node.expanded = false end)
        win.refreshTree()
      end,
      desc = keymap.collapse_all.desc,
    },
    [keymap.expand.lhs] = {
      ---@param node TestNode
      handle = function(node, win)
        node.expanded = node.expanded == false
        win.refreshTree()
      end,
      desc = keymap.expand.desc,
    },
    [keymap.peek_stacktrace.lhs] = { handle = function(node) open_stack_trace(node) end, desc = keymap.peek_stacktrace.desc },
    [keymap.run_all.lhs] = {
      handle = function(_, win)
        win.traverse(win.tree, function(node)
          if node.type == "csproject" then coroutine.wrap(function() run_tests(node, win) end)() end
        end)
      end,
      desc = keymap.run_all.desc,
    },
    [keymap.run.lhs] = {
      ---@param node TestNode
      handle = function(node, win)
        if node.type == "sln" then
          for _, value in pairs(node.children) do
            coroutine.wrap(function() run_tests(value, win) end)()
          end
        elseif node.type == "csproject" then
          coroutine.wrap(function() run_tests(node, win) end)()
        elseif node.type == "namespace" then
          coroutine.wrap(function() run_tests(node, win) end)()
        elseif node.type == "test_group" then
          coroutine.wrap(function() run_tests(node, win) end)()
        elseif node.type == "subcase" then
          coroutine.wrap(function() run_tests(node, win) end)()
        elseif node.type == "test" then
          coroutine.wrap(function() run_tests(node, win) end)()
        else
          logger.warn("Unknown line type " .. node.type)
          return
        end
      end,
      desc = keymap.run.desc,
    },
    [keymap.close.lhs] = { handle = function(_, win) win.hide() end, desc = keymap.close.desc },
  }
end

return M
