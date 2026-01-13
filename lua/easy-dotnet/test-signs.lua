local picker = require("easy-dotnet.picker")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local constants = require("easy-dotnet.constants")
local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local keymaps = require("easy-dotnet.test-runner.keymaps")
local win = require("easy-dotnet.test-runner.render")
local runner = require("easy-dotnet.test-runner.runner")

---@param path string Absolute path to the file
---@return integer mtime File's last modification time in seconds since epoch
local get_mtime = function(path)
  local stat = vim.loop.fs_stat(path)
  if not stat then error("File not found: " .. path) end
  return stat.mtime.sec
end

---@param path string Absolute path to the file
local function reset_buf_mtime(path) vim.b.easy_dotnet_mtime = get_mtime(path) end
local get_buf_mtime = function() return vim.b.easy_dotnet_mtime end

local M = {}

local function compare_paths(path1, path2)
  if not path1 or type(path1) == "userdata" then return false end
  if not path2 or type(path2) == "userdata" then return false end

  return vim.fs.normalize(path1):lower() == vim.fs.normalize(path2):lower()
end

---@return integer? start_row, integer? end_row
local function get_nearest_method_range()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]

  local parser = vim.treesitter.get_parser(bufnr)
  if not parser then return nil end
  local tree = parser:parse()[1]
  local root = tree:root()

  local node = root:named_descendant_for_range(row, col, row, col)

  while node do
    if node:type() == "method_declaration" then
      local start_row, _, end_row, _ = node:range()
      return start_row + 1, end_row + 1
    end
    node = node:parent()
  end
end

local function debug_test_from_buffer()
  local success, dap = pcall(function() return require("dap") end)
  if not success then
    logger.error("nvim-dap not installed")
    return
  end

  local curr_file = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  local start_row, end_row = get_nearest_method_range()
  if not start_row or not end_row then
    logger.warn("Didn't find nearest method range")
    return
  end

  require("easy-dotnet.test-runner.render").traverse(nil, function(node)
    if (node.type == "test" or node.type == "test_group") and compare_paths(node.file_path, curr_file) and (node.line_number >= start_row and node.line_number <= end_row) then
      vim.api.nvim_win_set_cursor(0, { node.line_number and (node.line_number - 1) or 0, 0 })
      dap.set_breakpoint()
      local client = require("easy-dotnet.rpc.rpc").global_rpc_client
      local project_path = node.cs_project_path
      local sln_file = sln_parse.try_get_selected_solution_file()
      assert(sln_file, "Failed to find a solution file")
      local test_projects = sln_parse.get_projects_and_frameworks_flattened_from_sln(sln_file, function(i) return i.isTestProject end)
      local test_project = project_path and project_path or picker.pick_sync(nil, test_projects, "Pick test project").path
      assert(test_project, "No project selected")
      client:initialize(function()
        client.debugger:debugger_start({ targetPath = test_project }, function(res)
          local debug_conf = {
            type = constants.debug_adapter_name,
            name = constants.debug_adapter_name,
            request = "attach",
            port = res.port,
          }
          dap.run(debug_conf)
        end)
      end)
      return
    end
  end)
end

---@param predicate (fun(node: easy-dotnet.TestRunner.Node): boolean)|nil
local function run_tests_from_buffer(predicate)
  local bufnr = vim.api.nvim_get_current_buf()
  local curr_file = vim.api.nvim_buf_get_name(bufnr)
  local requires_rebuild = get_buf_mtime() ~= get_mtime(curr_file)

  ---@type easy-dotnet.TestRunner.Node[]
  local handlers = {}

  ---@param node easy-dotnet.TestRunner.Node
  require("easy-dotnet.test-runner.render").traverse(nil, function(node)
    if (node.type == "test" or node.type == "test_group") and compare_paths(node.file_path, curr_file) then table.insert(handlers, node) end
  end)
  ---@type easy-dotnet.TestRunner.Node
  local first_node = handlers[1]

  if requires_rebuild and first_node then
    local on_finished = job.register_job({ name = "Building...", on_error_text = "Build failed", on_success_text = "Built successfully" })

    local res = runner.request_build(first_node.cs_project_path)
    if res then reset_buf_mtime(curr_file) end
    on_finished(res)
  end

  for _, node in ipairs(handlers) do
    if not predicate or predicate(node) then
      keymaps.test_run(node, win, function() vim.schedule(M.add_gutter_test_signs) end)
      M.add_gutter_test_signs()
    end
  end
end

local function run_test_from_buffer()
  local start_row, end_row = get_nearest_method_range()
  if not start_row or not end_row then
    logger.warn("Didn't find nearest method range")
    return
  end

  run_tests_from_buffer(function(node) return node.line_number >= start_row and node.line_number <= end_row end)
end

local function open_stack_trace_from_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  local start_row, end_row = get_nearest_method_range()
  if not start_row or not end_row then
    logger.warn("Didn't find nearest method range")
    return
  end

  local handlers = {}

  ---@param node easy-dotnet.TestRunner.Node
  require("easy-dotnet.test-runner.render").traverse(nil, function(node)
    if (node.type == "test" or node.type == "subcase") and compare_paths(node.file_path, curr_file) and node.line_number >= start_row and node.line_number <= end_row then
      table.insert(handlers, node)
    end
  end)

  -- In case of multiple tests on the same line (e.g. [TheoryData]), show the first one with a stack trace
  ---@type easy-dotnet.TestRunner.Node
  for _, node in ipairs(handlers) do
    if node.expand then
      local window = require("easy-dotnet.test-runner.window")
      window:new_float():write_buf(node.expand):create()
      return
    end
  end
end

function M.add_gutter_test_signs()
  local options = require("easy-dotnet.test-runner.render").options
  local is_test_file = false
  local bufnr = vim.api.nvim_get_current_buf()
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  ---@param node easy-dotnet.TestRunner.Node
  require("easy-dotnet.test-runner.render").traverse(nil, function(node)
    if (node.type == "test" or node.type == "test_group") and compare_paths(node.file_path, curr_file) then
      is_test_file = true
      --INFO: line number for MTP is on the [Test] attribute. VSTest is on the method_declaration
      local line_offset = node.line_number - 1 - (node.is_MTP and 0 or 1)

      vim.api.nvim_buf_set_extmark(bufnr, constants.ns_id, line_offset, 0, {
        id = node.line_number,
        sign_text = options.icons.test,
        priority = 20,
        sign_hl_group = constants.highlights.EasyDotnetTestRunnerProject,
      })

      if node.icon then
        if node.icon == options.icons.failed then
          vim.api.nvim_buf_set_extmark(bufnr, constants.ns_id, line_offset, 0, {
            id = node.line_number,
            sign_text = options.icons.failed,
            priority = 20,
            sign_hl_group = constants.highlights.EasyDotnetTestRunnerFailed,
          })
        elseif node.icon == options.icons.skipped then
          vim.api.nvim_buf_set_extmark(bufnr, constants.ns_id, line_offset, 0, {
            id = node.line_number,
            sign_text = options.icons.skipped,
            priority = 20,
            sign_hl_group = constants.highlights.EasyDotnetTestRunnerTest,
          })
        elseif node.icon == "<Running>" then
          vim.api.nvim_buf_set_extmark(bufnr, constants.ns_id, line_offset, 0, {
            id = node.line_number,
            sign_text = options.icons.reload,
            priority = 20,
            sign_hl_group = constants.highlights.EasyDotnetTestRunnerRunning,
          })
        elseif node.icon == options.icons.passed then
          vim.api.nvim_buf_set_extmark(bufnr, constants.ns_id, line_offset, 0, {
            id = node.line_number,
            sign_text = options.icons.passed,
            priority = 20,
            sign_hl_group = constants.highlights.EasyDotnetTestRunnerPassed,
          })
        end
      end
    end
  end)

  local keymap = require("easy-dotnet.test-runner.render").options.mappings
  if is_test_file == true then
    if not get_buf_mtime() then reset_buf_mtime(curr_file) end
    vim.keymap.set("n", keymap.debug_test_from_buffer.lhs, function() debug_test_from_buffer() end, { silent = true, buffer = bufnr, desc = keymap.debug_test_from_buffer.desc })

    vim.keymap.set("n", keymap.run_test_from_buffer.lhs, function()
      coroutine.wrap(function() run_test_from_buffer() end)()
    end, { silent = true, buffer = bufnr, desc = keymap.run_test_from_buffer.desc })

    vim.keymap.set("n", keymap.run_all_tests_from_buffer.lhs, function()
      coroutine.wrap(function() run_tests_from_buffer(nil) end)()
    end, { silent = true, buffer = bufnr, desc = keymap.run_all_tests_from_buffer.desc })

    vim.keymap.set("n", keymap.peek_stack_trace_from_buffer.lhs, function()
      coroutine.wrap(function() open_stack_trace_from_buffer() end)()
    end, { silent = true, buffer = bufnr, desc = keymap.peek_stack_trace_from_buffer.desc })
  end
end

---@class easy-dotnet.TestResult
---@field passed integer Number of passed tests
---@field failed integer Number of failed tests
---@field skipped integer Number of skipped tests
---@field running integer Number of currently running tests

---Get aggregated test results for a specific test node in a file.
---
---This function queries the internal test runner state and returns the
---counts of passed, failed, skipped, or running tests for a given file
---and line number. Returns `nil` if no results are available.
---
---@param file_path string Absolute path to the file containing the test(s)
---@param line_number integer The line number of the test or test group
---@return easy-dotnet.TestResult | nil res Aggregated results or `nil` if not found
M.get_test_results = function(file_path, line_number)
  local options = require("easy-dotnet.test-runner.render").options
  local res = { passed = 0, failed = 0, skipped = 0, running = 0 }

  ---@param node easy-dotnet.TestRunner.Node
  require("easy-dotnet.test-runner.render").traverse(nil, function(node)
    if (node.type == "test" or node.type == "test_group") and compare_paths(node.file_path, file_path) and line_number == node.line_number then
      if node.icon then
        if node.icon == options.icons.failed then
          res.failed = res.failed + 1
        elseif node.icon == options.icons.skipped then
          res.skipped = res.skipped + 1
        elseif node.icon == "<Running>" then
          res.running = res.running + 1
        elseif node.icon == options.icons.passed then
          res.passed = res.passed + 1
        end
      end
    end
  end)

  local any_results = vim.iter(vim.tbl_values(res)):any(function(r) return r > 0 end)
  return any_results and res or nil
end

return M
