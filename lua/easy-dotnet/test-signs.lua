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

local function debug_test_from_buffer()
  local success, dap = pcall(function() return require("dap") end)
  if not success then
    logger.error("nvim-dap not installed")
    return
  end

  local curr_file = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  require("easy-dotnet.test-runner.render").traverse(nil, function(node)
    if (node.type == "test" or node.type == "test_group") and compare_paths(node.file_path, curr_file) and node.line_number - 1 == current_line then
      --TODO: Investigate why netcoredbg wont work without reopening the buffer????
      vim.cmd("bdelete")
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
      --return to avoid running multiple times in case of InlineData|ClassData
      return
    end
  end)
end

local function get_nearest_method_line()
  local ts_utils = require("nvim-treesitter.ts_utils")
  local node = ts_utils.get_node_at_cursor()

  while node do
    if node:type() == "method_declaration" then
      local wantedNode = node:field("name")[1]
      local wantedNodeStartRow, _, _ = wantedNode:start()
      -- treesitter uses 0 based indexing where as line numbers start at 1
      return wantedNodeStartRow + 1
    end
    node = node:parent()
  end
end

local function run_test_from_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local curr_file = vim.api.nvim_buf_get_name(bufnr)
  local requires_rebuild = get_buf_mtime() ~= get_mtime(curr_file)

  local handlers = {}

  ---@param node TestNode
  require("easy-dotnet.test-runner.render").traverse(nil, function(node)
    if (node.type == "test" or node.type == "test_group") and compare_paths(node.file_path, curr_file) then table.insert(handlers, node) end
  end)
  ---@type TestNode
  local first_node = handlers[1]

  if requires_rebuild and first_node then
    local on_finished = job.register_job({ name = "Building...", on_error_text = "Build failed", on_success_text = "Built successfully" })

    local res = runner.request_build(first_node.cs_project_path)
    if res then reset_buf_mtime(curr_file) end
    on_finished(res)
  end

  for _, node in ipairs(handlers) do
    if node.is_MTP and node.line_number == vim.api.nvim_win_get_cursor(0)[1] then
      keymaps.test_run(node, win, function() vim.schedule(M.add_gutter_test_signs) end)
      M.add_gutter_test_signs()
    elseif not node.is_MTP and (node.line_number - 1 == vim.api.nvim_win_get_cursor(0)[1] or node.line_number - 1 == get_nearest_method_line()) then
      keymaps.test_run(node, win, function() vim.schedule(M.add_gutter_test_signs) end)
      M.add_gutter_test_signs()
    end
  end
end

function M.add_gutter_test_signs()
  local options = require("easy-dotnet.test-runner.render").options
  local is_test_file = false
  local bufnr = vim.api.nvim_get_current_buf()
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  ---@param node TestNode
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
  end
end

---@class EasyDotnetTestResult
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
---@return EasyDotnetTestResult | nil res Aggregated results or `nil` if not found
M.get_test_results = function(file_path, line_number)
  local options = require("easy-dotnet.test-runner.render").options
  local res = { passed = 0, failed = 0, skipped = 0, running = 0 }

  ---@param node TestNode
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
