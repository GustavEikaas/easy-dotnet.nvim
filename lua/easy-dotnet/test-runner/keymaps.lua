local window = require("easy-dotnet.test-runner.window")
local polyfills = require("easy-dotnet.polyfills")
local logger = require("easy-dotnet.logger")

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
  if result.outcome == "Passed" then
    test_line.icon = options.icons.passed
  elseif result.outcome == "Failed" then
    test_line.icon = options.icons.failed
    if result.message or result.stackTrace then test_line.expand = vim.split((result.message or "") .. "\n" .. (result.stackTrace or ""):gsub("^%s+", ""):gsub("\n%s+", "\n"), "\n") end
  elseif result.outcome == "NotExecuted" then
    test_line.icon = options.icons.skipped
  else
    test_line.icon = "??"
  end
end

---@param relative_log_file_path string
---@param win table
---@param node TestNode
---@param on_completed function
local function parse_log_file(relative_log_file_path, win, node, on_completed)
  require("easy-dotnet.test-runner.test-parser").xml_to_json(
    relative_log_file_path,
    ---@param unit_test_results TestCase[]
    function(unit_test_results)
      if #unit_test_results == 0 then
        win.traverse(node, function(child)
          if child.icon == "<Running>" then child.icon = "<No status reported>" end
        end)
        on_completed()
        win.refreshTree()
        return
      end

      for _, value in ipairs(unit_test_results) do
        win.traverse(node, function(child_node)
          if (child_node.type == "test" or child_node.type == "subcase") and child_node.id == value.id then parse_status(value, child_node, win.options) end
        end)
      end

      aggregate_status(win.tree, win.options)
      on_completed()
      win.refreshTree()
    end
  )
end

---@param options TestRunnerOptions
local function get_dotnet_args(options)
  local args = {}
  if options.noBuild == true then table.insert(args, "--no-build") end
  if options.noRestore == true then table.insert(args, "--no-restore") end
  return table.concat(args, " ") .. " " .. table.concat(options.additional_args or {}, " ")
end

---@param node TestNode
local function run_csproject(win, node)
  local log_file_name = string.format("%s_%s.xml", vim.fs.basename(node.cs_project_path), node.framework)
  local normalized_path = vim.fs.normalize(node.cs_project_path)
  local directory_path = vim.fs.dirname(normalized_path)
  local relative_log_file_path = polyfills.fs.joinpath(directory_path, "TestResults", log_file_name)

  local matches = {}
  local testcount = 0
  ---@param child TestNode
  win.traverse(node, function(child)
    child.icon = "<Running>"
    table.insert(matches, { ref = child, line = child.namespace, id = child.id })
    if child.type == "test" or child.type == "subcase" then testcount = testcount + 1 end
  end)

  local on_job_finished = win.appendJob(node.cs_project_path, "Run", testcount)

  win.refreshTree()
  local cmd = string.format('dotnet test --nologo %s %s --framework %s --logger="trx;logFileName=%s"', get_dotnet_args(win.options), node.cs_project_path, node.framework, log_file_name)
  vim.fn.jobstart(cmd, {
    on_exit = function(_) parse_log_file(relative_log_file_path, win, node, on_job_finished) end,
  })
end

---@param line TestNode
local function run_test_group(line, win)
  local log_file_name = string.format("%s.xml", line.name)
  local normalized_path = vim.fs.normalize(line.cs_project_path)
  local directory_path = vim.fs.dirname(normalized_path)
  local relative_log_file_path = polyfills.fs.joinpath(directory_path, "TestResults", log_file_name)

  local suite_name = line.namespace
  local testcount = 0
  ---@param child TestNode
  win.traverse(line, function(child)
    child.icon = "<Running>"
    if child.type == "test" or child.type == "subcase" then testcount = testcount + 1 end
  end)

  local on_job_finished = win.appendJob(line.name, "Run", testcount)
  win.refreshTree()
  vim.fn.jobstart(
    string.format('dotnet test --filter=%s --nologo %s %s --framework %s --logger="trx;logFileName=%s"', suite_name, get_dotnet_args(win.options), line.cs_project_path, line.framework, log_file_name),
    {
      on_exit = function() parse_log_file(relative_log_file_path, win, line, on_job_finished) end,
    }
  )
end

---@param line TestNode
local function run_test_suite(line, win)
  local log_file_name = string.format("%s.xml", line.namespace)
  local normalized_path = vim.fs.normalize(line.cs_project_path)
  local directory_path = vim.fs.dirname(normalized_path)
  local relative_log_file_path = polyfills.fs.joinpath(directory_path, "TestResults", log_file_name)

  local testcount = 0
  local suite_name = line.namespace
  win.traverse(line, function(child)
    child.icon = "<Running>"
    if child.type == "test" or child.type == "subcase" then testcount = testcount + 1 end
  end)
  win.refreshTree()

  local on_job_finished = win.appendJob(line.namespace, "Run", testcount)
  vim.fn.jobstart(
    string.format('dotnet test --filter=%s --nologo %s %s --framework %s --logger="trx;logFileName=%s"', suite_name, get_dotnet_args(win.options), line.cs_project_path, line.framework, log_file_name),
    {
      on_exit = function() parse_log_file(relative_log_file_path, win, line, on_job_finished) end,
    }
  )
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

---@param node TestNode
local function run_test(node, win)
  local log_file_name = string.format("%s.xml", node.name)
  local normalized_path = vim.fs.normalize(node.cs_project_path)
  local directory_path = vim.fs.dirname(normalized_path)
  local relative_log_file_path = polyfills.fs.joinpath(directory_path, "TestResults", log_file_name)

  local command = string.format(
    'dotnet test --filter=%s --nologo %s %s --framework %s --logger="trx;logFileName=%s"',
    node.namespace:gsub("%b()", ""),
    get_dotnet_args(win.options),
    node.cs_project_path,
    node.framework,
    log_file_name
  )

  local on_job_finished = win.appendJob(node.name, "Run")

  node.icon = "<Running>"
  vim.fn.jobstart(command, {
    on_exit = function()
      require("easy-dotnet.test-runner.test-parser").xml_to_json(
        relative_log_file_path,
        ---@param unit_test_results TestCase
        function(unit_test_results)
          local result = unit_test_results[1]
          if result == nil then error(string.format("Status of %s was not present in xml file", node.name)) end
          parse_status(result, node, win.options)
          on_job_finished()
          win.refreshTree()
        end
      )
    end,
  })

  win.refreshTree()
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
    ---@param node Test
    [keymap.go_to_file.lhs] = {
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
    ---@param node TestNode
    [keymap.expand.lhs] = {
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
          if node.type == "csproject" then run_csproject(win, node) end
        end)
      end,
      desc = keymap.run_all.desc,
    },
    ---@param node TestNode
    [keymap.run.lhs] = {
      handle = function(node, win)
        if node.type == "sln" then
          for _, value in pairs(node.children) do
            run_csproject(win, value)
          end
        elseif node.type == "csproject" then
          run_csproject(win, node)
        elseif node.type == "namespace" then
          run_test_suite(node, win)
        elseif node.type == "test_group" then
          run_test_group(node, win)
        elseif node.type == "subcase" then
          logger.error("Running specific subcases is not supported")
        elseif node.type == "test" then
          run_test(node, win)
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
