local constants = require("easy-dotnet.constants")
local logger = require("easy-dotnet.logger")
local keymaps = require("easy-dotnet.test-runner.keymaps")
local win = require("easy-dotnet.test-runner.render")
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
  --BUG: This wont work in case of test-groups, need to collect all id's and run or run the parent(if possible?)

  ---@param node TestNode
  require("easy-dotnet.test-runner.render").traverse(nil, function(node)
    --TODO: move line logic in here. Need to know if test is MTP or vstest before calculating get_nearest_method_line()
    --Should be fine to take first test in file because mixing mtp and vstest is not supported
    if (node.type == "test" or node.type == "test_group") and compare_paths(node.file_path, curr_file) then
      if node.is_MTP and node.line_number == vim.api.nvim_win_get_cursor(0)[1] then
        keymaps.MTP_Run(node, win, function() M.add_gutter_test_signs() end)
      elseif not node.is_MTP and (node.line_number - 1 == vim.api.nvim_win_get_cursor(0)[1] or node.line_number - 1 == get_nearest_method_line()) then
        keymaps.VsTest_Run(node, win, function() M.add_gutter_test_signs() end)
      end
    end
  end)
end

function M.add_gutter_test_signs()
  local options = require("easy-dotnet.test-runner.render").options
  local signs = constants.signs
  local sign_ns = constants.sign_namespace
  local is_test_file = false
  local bufnr = vim.api.nvim_get_current_buf()
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  --BUG: This wont work in case of test-groups, need to aggregate the statuses and choose the worst outcome

  ---@param node TestNode
  require("easy-dotnet.test-runner.render").traverse(nil, function(node)
    if (node.type == "test" or node.type == "test_group") and compare_paths(node.file_path, curr_file) then
      is_test_file = true
      --INFO: line number for MTP is on the [Test] attribute. VSTest is on the method_declaration
      local line_offset = node.line_number - (node.is_MTP and 0 or 1)
      vim.fn.sign_place(0, sign_ns, signs.EasyDotnetTestSign, bufnr, { lnum = line_offset, priority = 20 })

      if node.icon then
        if node.icon == options.icons.failed then
          vim.print(node)
          vim.fn.sign_place(0, sign_ns, signs.EasyDotnetTestFailed, bufnr, { lnum = line_offset, priority = 20 })
        elseif node.icon == options.icons.skipped then
          vim.fn.sign_place(0, sign_ns, signs.EasyDotnetTestSkipped, bufnr, { lnum = line_offset, priority = 20 })
        elseif node.icon == options.icons.passed then
          vim.fn.sign_place(0, sign_ns, signs.EasyDotnetTestPassed, bufnr, { lnum = line_offset, priority = 20 })
        end
      end
    end
  end)

  local keymap = require("easy-dotnet.test-runner.render").options.mappings
  if is_test_file == true then
    vim.keymap.set("n", keymap.debug_test_from_buffer.lhs, function() debug_test_from_buffer() end, { silent = true, buffer = bufnr, desc = keymap.debug_test_from_buffer.desc })

    vim.keymap.set("n", keymap.run_test_from_buffer.lhs, function() run_test_from_buffer() end, { silent = true, buffer = bufnr, desc = keymap.run_test_from_buffer.desc })
  end
end

return M
