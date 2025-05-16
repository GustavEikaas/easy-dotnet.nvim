local window = require("easy-dotnet.test-runner.window")
local logger = require("easy-dotnet.logger")
local extensions = require("easy-dotnet.extensions")

---@class RPC_RunRequest
---@field testExecutablePath string Path to the test runner binary
---@field filter RunRequestNode[] Optional filter for which tests to run
---@field outFile string Path where test results should be written

---@class RunRequestNode
---@field uid string Unique test run identifier
---@field displayName string Human-readable name for the run

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

local function dump_to_file(obj, filepath)
  local serialized = vim.inspect(obj)
  local f = io.open(filepath, "w")
  if not f then error("Could not open file: " .. filepath) end
  f:write(serialized)
  f:close()
end

local function get_test_result_handler(win, node, on_job_finished)
  ---@param rpc_res RPC_Response
  return function(rpc_res)
    if rpc_res.error then
      vim.schedule(function() vim.notify(string.format("[%s]: %s", rpc_res.error.code, rpc_res.error.message), vim.log.levels.ERROR) end)
      if rpc_res.error.data then
        local file = vim.fs.normalize(os.tmpname())
        dump_to_file(rpc_res, file)
        logger.error("Crash dump written at " .. file)
      end
      on_job_finished()

      win.traverse(node, function(child)
        if child.icon == "<Running>" then child.icon = "<Operation failed>" end
      end)
      win.refreshTree()
      return
    end

    ---@type TestCase[]
    local test_results = vim.tbl_map(function(i) return vim.fn.json_decode(i) end, vim.fn.readfile(rpc_res.result.outFile))
    test_status_updater(test_results, win, node)
    on_job_finished()
  end
end

---@param node TestNode
---@param win table
local function VsTest_Run(node, win)
  ---@type TestNode[]
  local tests = {}
  ---@param child TestNode
  win.traverse(node, function(child)
    child.icon = "<Running>"
    if child.type == "test" or child.type == "subcase" then table.insert(tests, child) end
  end)

  local on_job_finished = win.appendJob(node.cs_project_path, "Run", #tests)
  local mtp_out_file = vim.fs.normalize(os.tmpname())

  local filter = vim.tbl_map(function(test)
    ---@type RunRequestNode
    return test.id
  end, tests)

  local project = require("easy-dotnet.parsers.csproj-parse").get_project_from_project_file(node.cs_project_path)
  local testPath = project.get_dll_path()

  -- string VsTestPath,
  -- string DllPath,
  -- Guid[] TestIds,
  -- string OutFile
  local options = require("easy-dotnet.options").options.test_runner
  local vstest_dll = vim.fs.joinpath(options.sdk_path, "vstest.console.dll")
  coroutine.wrap(function()
    ---@type StreamJsonRpc | nil
    local client = require("easy-dotnet.test-runner.runner")._server.client
    if not client then error("RPC client not initialized") end
    client.request("vstest/run", { outFile = mtp_out_file, vsTestPath = vstest_dll, dllPath = testPath, testIds = filter }, get_test_result_handler(win, node, on_job_finished))
  end)()
end
---@param node TestNode
---@param win table
local function MTP_Run(node, win)
  ---@type TestNode[]
  local tests = {}
  ---@param child TestNode
  win.traverse(node, function(child)
    child.icon = "<Running>"
    if child.type == "test" or child.type == "subcase" then table.insert(tests, child) end
  end)

  local on_job_finished = win.appendJob(node.cs_project_path, "Run", #tests)
  local mtp_out_file = vim.fs.normalize(os.tmpname())

  local filter = vim.tbl_map(function(test)
    ---@type RunRequestNode
    return {
      uid = test.id,
      displayName = test.displayName,
    }
  end, tests)

  local project = require("easy-dotnet.parsers.csproj-parse").get_project_from_project_file(node.cs_project_path)
  local testPath = project.get_dll_path():gsub("%.dll", extensions.isWindows() and "." .. project.msbuild_props.outputType:lower() or "")

  coroutine.wrap(function()
    ---@type StreamJsonRpc | nil
    local client = require("easy-dotnet.test-runner.runner")._server.client
    if not client then error("RPC client not initialized") end
    client.request("mtp/run", { outFile = mtp_out_file, testExecutablePath = testPath, filter = filter }, get_test_result_handler(win, node, on_job_finished))
  end)()
end

---@param node TestNode
local function run_tests(node, win)
  if node.is_MTP then
    MTP_Run(node, win)
    return
  else
    VsTest_Run(node, win)
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

local keymaps = function()
  local keymap = require("easy-dotnet.test-runner.render").options.mappings
  return {
    [keymap.filter_failed_tests.lhs] = { handle = function(_, win) filter_failed_tests(win) end, desc = keymap.filter_failed_tests.desc },
    [keymap.refresh_testrunner.lhs] = { handle = function(_) vim.cmd("Dotnet testrunner refresh build") end, desc = keymap.refresh_testrunner.desc },
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
          --TODO: batching for vstest
          if node.type == "csproject" then run_tests(node, win) end
        end)
      end,
      desc = keymap.run_all.desc,
    },
    [keymap.run.lhs] = {
      ---@param node TestNode
      handle = function(node, win)
        if node.type == "sln" then
          for _, value in pairs(node.children) do
            --TODO: batching for vstest
            run_tests(value, win)
          end
        elseif node.type == "csproject" then
          run_tests(node, win)
        elseif node.type == "namespace" then
          run_tests(node, win)
        elseif node.type == "test_group" then
          run_tests(node, win)
        elseif node.type == "subcase" then
          run_tests(node, win)
        elseif node.type == "test" then
          run_tests(node, win)
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

return keymaps
