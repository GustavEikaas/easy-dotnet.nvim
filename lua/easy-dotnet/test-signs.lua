local M = {}

local function compare_paths(path1, path2)
  return vim.fs.normalize(path1):lower() == vim.fs.normalize(path2):lower()
end


local function run_test(name, namespace, cs_project_path, cb)
  local log_file_name = string.format("%s.xml", namespace:gsub("%b()", ""))
  local normalized_path = vim.fs.normalize(cs_project_path)
  local directory_path = vim.fs.dirname(normalized_path)
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local command = string.format(
    "dotnet test --filter='%s' --nologo %s --logger='trx;logFileName=%s'",
    namespace:gsub("%b()", ""), cs_project_path, log_file_name)

  vim.fn.jobstart(
    command, {
      on_exit = function()
        require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
          ---@param unit_test_results TestCase
          function(unit_test_results)
            local result = unit_test_results[1]
            if result == nil then
              error(string.format("Status of %s was not present in xml file", name))
            end
            cb(unit_test_results)
          end)
      end
    })
end

local function parse_status(result, test_line, options)
  if result.outcome == "Passed" then
    test_line.icon = options.icons.passed
  elseif result.outcome == "Failed" then
    test_line.icon = options.icons.failed
    test_line.expand = vim.split(result.stackTrace, "\n")
  elseif result.outcome == "NotExecuted" then
    test_line.icon = options.icons.skipped
  else
    test_line.icon = "??"
  end
end


function M.add_gutter_test_signs()
  local constants = require("easy-dotnet.constants")
  local signs = constants.signs
  local sign_ns = constants.sign_namespace
  local is_test_file = false
  local bufnr = vim.api.nvim_get_current_buf()
  local curr_file = vim.api.nvim_buf_get_name(bufnr)
  for _, value in ipairs(require("easy-dotnet.test-runner.runner").test_register) do
    if compare_paths(value.file_path, curr_file) then
      is_test_file = true
      local line = value.line_number
      vim.fn.sign_place(0, sign_ns, signs.EasyDotnetTestSign, vim.api.nvim_get_current_buf(),
        { lnum = line - 1, priority = 20 })
    end
  end

  if is_test_file == true then
    -- vim.keymap.set("n", "<leader>d", function()
    --   local success, dap = pcall(function() return require("dap") end)
    --   if not success then
    --     vim.notify("nvim-dap not installed", vim.log.levels.ERROR)
    --     return
    --   end
    --
    --   local bufnr = vim.api.nvim_get_current_buf()
    --   local curr_file = vim.api.nvim_buf_get_name(bufnr)
    --   local current_line = vim.api.nvim_win_get_cursor(0)[1]
    --   for _, value in ipairs(require("easy-dotnet.test-runner.runner").test_register) do
    --     if compare_paths(value.file_path, curr_file) and value.line_number - 1 == current_line then
    --       --TODO: Investigate why netcoredbg wont work without reopening the buffer????
    --       vim.cmd("bdelete")
    --       vim.cmd("edit " .. value.file_path)
    --       vim.api.nvim_win_set_cursor(0, { value.line_number and (value.line_number - 1) or 0, 0 })
    --       dap.toggle_breakpoint()
    --
    --       local dap_configuration = {
    --         type = "coreclr",
    --         name = value.name,
    --         request = "attach",
    --         processId = function()
    --           local project_path = value.cs_project_path
    --           local res = require("easy-dotnet.debugger").start_debugging_test_project(project_path)
    --           return res.process_id
    --         end
    --       }
    --       dap.run(dap_configuration)
    --       --return to avoid running multiple times in case of InlineData|ClassData
    --       return
    --     end
    --   end
    --   vim.notify("No tests found on this line")
    -- end, { silent = true, buffer = bufnr })

    vim.keymap.set("n", "<leader>r", function()
      local bufnr = vim.api.nvim_get_current_buf()
      local curr_file = vim.api.nvim_buf_get_name(bufnr)
      local current_line = vim.api.nvim_win_get_cursor(0)[1]
      for _, value in ipairs(require("easy-dotnet.test-runner.runner").test_register) do
        if compare_paths(value.file_path, curr_file) and value.line_number - 1 == current_line then
          local spinner = require("easy-dotnet.ui-modules.spinner").new()
          spinner:start_spinner("Running test")

          run_test(value.name, value.namespace, value.cs_project_path, function(results)
            local worst_outcome = "Passed"

            for _, result in pairs(results) do
              if result.outcome == "Failed" then
                worst_outcome = "Failed"
              elseif result.outcome == "NotExecuted" and worst_outcome ~= "Failed" then
                worst_outcome = "NotExecuted"
              elseif result.outcome == "Passed" and worst_outcome ~= "Failed" and worst_outcome ~= "NotExecuted" then
                worst_outcome = "Passed"
              end
            end

            local tests = require("easy-dotnet.test-runner.render").lines
            for _, test in ipairs(tests) do
              if test.id == results[1].id then
                local options = require("easy-dotnet.test-runner.render").options
                parse_status(results[1], test, options)
              end
              require("easy-dotnet.test-runner.render").refreshLines()
            end


            if worst_outcome == "Passed" then
              vim.fn.sign_place(0, sign_ns, signs.EasyDotnetTestPassed, bufnr,
                { lnum = current_line - 1, priority = 20 })
              spinner:stop_spinner("Passed")
            elseif worst_outcome == "Failed" then
              vim.fn.sign_place(0, sign_ns, signs.EasyDotnetTestFailed, bufnr,
                { lnum = current_line - 1, priority = 20 })
              spinner:stop_spinner("Failed", vim.log.levels.ERROR)
            elseif worst_outcome == "NotExecuted" then
              vim.fn.sign_place(0, sign_ns, signs.EasyDotnetTestSkipped, bufnr,
                { lnum = current_line - 1, priority = 20 })
              spinner:stop_spinner("Skipped", vim.log.levels.WARN)
            else
              spinner:stop_spinner("Test Result Errors", vim.log.levels.WARN)
              vim.fn.sign_place(0, sign_ns, signs.EasyDotnetTestError, bufnr,
                { lnum = current_line - 1, priority = 20 })
            end
          end)
          return
        end
      end
      vim.notify("No tests found on this line")
    end, { silent = true, buffer = bufnr })
  end
end

return M
