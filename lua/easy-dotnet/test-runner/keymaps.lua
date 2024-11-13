local window = require "easy-dotnet.test-runner.window"

---@param node TestNode
---@param options table
local function aggregateStatus(node, options)
  --BUG: Failed aggregation does not propagate to grandparents
  if not node.children or next(node.children) == nil then
    return node.icon
  end

  local worstStatus = options.icons.passed

  for _, child in pairs(node.children) do
    local childWorstStatus = aggregateStatus(child, options)

    if childWorstStatus == options.icons.failed then
      worstStatus = options.icons.failed
    elseif childWorstStatus == options.icons.skipped and worstStatus ~= options.icons.failed then
      worstStatus = options.icons.skipped
    end
  end

  node.icon = worstStatus
end

local function parse_status(result, test_line, options)
  --TODO: handle more cases like cancelled etc...
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


---@param relative_log_file_path string
---@param win table
---@param node TestNode
---@param on_completed function
local function parse_log_file(relative_log_file_path, win, node, on_completed)
  require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
    ---@param unit_test_results TestCase[]
    function(unit_test_results)
      if #unit_test_results == 0 then
        win.traverse(node, function(child)
          if child.icon == "<Running>" then
            child.icon = "<No status reported>"
          end
        end)
        on_completed()
        win.refreshTree()
        return
      end

      for _, value in ipairs(unit_test_results) do
        win.traverse(node, function(child_node)
          if (child_node.type == "test" or child_node.type == "subcase") and child_node.id == value.id then
            parse_status(value, child_node, win.options)
          end
        end)
      end

      -- for _, match in ipairs(matches) do
      --   local test_line = match.ref
      --   if test_line.type == "test" or test_line.type == "subcase" then
      --     for _, value in ipairs(unit_test_results) do
      --       if match.id == value.id then
      --         parse_status(value, test_line, win.options)
      --       end
      --     end
      --   end
      -- end

      aggregateStatus(node, win.options)
      on_completed()
      win.refreshTree()
    end)
end

---@param options TestRunnerOptions
local function get_dotnet_args(options)
  local args = {}
  if options.noBuild == true then
    table.insert(args, "--no-build")
  end
  if options.noRestore == true then
    table.insert(args, "--no-restore")
  end
  return table.concat(args, " ") .. " " .. table.concat(options.additional_args or {}, " ")
end

---@param node TestNode
local function run_csproject(win, node)
  local log_file_name = string.format("%s.xml", node.cs_project_path:match("([^/\\]+)$"))
  local normalized_path = node.cs_project_path:gsub('\\', '/')
  -- Find the last slash and extract the directory path
  local directory_path = normalized_path:match('^(.*)/[^/]*$')
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local matches = {}
  local testcount = 0
  ---@param child TestNode
  win.traverse(node, function(child)
    child.icon = "<Running>"
    table.insert(matches, { ref = child, line = child.namespace, id = child.id })
    if child.type == "test" or child.type == "subcase" then
      testcount = testcount + 1
    end
  end)

  -- for _, line in ipairs(win.tree) do
  --   if line.cs_project_path == cs_project_path then
  --     table.insert(matches, { ref = line, line = line.namespace, id = line.id })
  --     line.icon = "<Running>"
  --     if line.type == "test" or line.type == "subcase" then
  --       testcount = testcount + 1
  --     end
  --   end
  -- end
  --
  local on_job_finished = win.appendJob(node.cs_project_path, "Run", testcount)

  win.refreshTree()
  vim.fn.jobstart(
    string.format('dotnet test --nologo %s %s --logger="trx;logFileName=%s"', get_dotnet_args(win.options),
      node.cs_project_path,
      log_file_name), {
      on_exit = function(_, code)
        parse_log_file(relative_log_file_path, win, node, on_job_finished)
      end
    })
end


---@param line TestNode
local function run_test_group(line, win)
  local log_file_name = string.format("%s.xml", line.name)
  local normalized_path = line.cs_project_path:gsub('\\', '/')
  local directory_path = normalized_path:match('^(.*)/[^/]*$')
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local matches = {}
  local suite_name = line.namespace
  local testcount = 0
  ---@param child TestNode
  win.traverse(line, function(child)
    child.icon = "<Running>"
    if child.type == "test" or child.type == "subcase" then
      testcount = testcount + 1
    end
  end)
  -- for _, test_line in ipairs(win.tree) do
  --   if line.name == test_line.name:gsub("%b()", "") and line.cs_project_path == test_line.cs_project_path and line.solution_file_path == test_line.solution_file_path then
  --     table.insert(matches, { ref = test_line, line = test_line.namespace, id = test_line.id })
  --     test_line.icon = "<Running>"
  --   end
  -- end
  win.refreshTree()

  local on_job_finished = win.appendJob(line.name, "Run", testcount)
  vim.fn.jobstart(
    string.format('dotnet test --filter=%s --nologo %s %s --logger="trx;logFileName=%s"',
      suite_name, get_dotnet_args(win.options), line.cs_project_path, log_file_name),
    {
      on_exit = function()
        parse_log_file(relative_log_file_path, win, line, on_job_finished)
      end
    })
end



---@param line TestNode
local function run_test_suite(line, win)
  local log_file_name = string.format("%s.xml", line.namespace)
  local normalized_path = line.cs_project_path:gsub('\\', '/')
  local directory_path = normalized_path:match('^(.*)/[^/]*$')
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local testcount = 0
  local suite_name = line.namespace
  win.traverse(line, function(child)
    child.icon = "<Running>"
    if child.type == "test" or child.type == "subcase" then
      testcount = testcount + 1
    end
  end)
  -- for _, test_line in ipairs(win.tree) do
  --   if test_line.namespace:match(suite_name) and line.cs_project_path == test_line.cs_project_path and line.solution_file_path == test_line.solution_file_path then
  --     table.insert(matches, { ref = test_line, line = test_line.namespace, id = test_line.id })
  --     if test_line.type == "test" or test_line.type == "subcase" then
  --       testcount = testcount + 1
  --     end
  --     test_line.icon = "<Running>"
  --   end
  -- end
  win.refreshTree()

  local on_job_finished = win.appendJob(line.namespace, "Run", testcount)
  vim.fn.jobstart(
    string.format('dotnet test --filter=%s --nologo %s %s --logger="trx;logFileName=%s"',
      suite_name, get_dotnet_args(win.options), line.cs_project_path, log_file_name),
    {
      on_exit = function()
        parse_log_file(relative_log_file_path, win, line, on_job_finished)
      end
    })
end

local function isAnyErr(lines, options)
  local err = false
  for _, value in ipairs(lines) do
    if value.icon == options.icons.failed then
      err = true
      return err
    end
  end

  return err
end

local function filter_failed_tests(win)
  if win.filter == nil and isAnyErr(win.tree, win.options) then
    for _, value in ipairs(win.tree) do
      if value.icon ~= win.options.icons.failed then
        value.hidden = true
      end
    end
    win.filter = "failed"
  else
    for _, value in ipairs(win.tree) do
      value.hidden = false
    end
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
  local normalized_path = node.cs_project_path:gsub('\\', '/')
  local directory_path = normalized_path:match('^(.*)/[^/]*$')
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local command = string.format(
    'dotnet test --filter=%s --nologo %s %s --logger="trx;logFileName=%s"',
    node.namespace:gsub("%b()", ""), get_dotnet_args(win.options), node.cs_project_path, log_file_name)

  local on_job_finished = win.appendJob(node.name, "Run")

  node.icon = "<Running>"
  vim.fn.jobstart(
    command, {
      on_exit = function()
        require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
          ---@param unit_test_results TestCase
          function(unit_test_results)
            local result = unit_test_results[1]
            if result == nil then
              error(string.format("Status of %s was not present in xml file", node.name))
            end
            parse_status(result, node, win.options)
            on_job_finished()
            win.refreshTree()
          end)
      end
    })

  win.refreshTree()
end


local function open_stack_trace(line)
  if line.expand == nil then
    return
  end

  local path = get_path_from_stack_trace(line.expand)

  if path ~= nil then
    local ns_id = require("easy-dotnet.constants").ns_id
    local contents = vim.fn.readfile(path.path)

    local file_float = window.new_float():pos_left():write_buf(contents):buf_set_filetype("csharp"):create()

    local stack_trace = window:new_float():link_close(file_float):pos_right():write_buf(line.expand):create()

    local function go_to_file()
      vim.api.nvim_win_close(file_float.win, true)
      vim.cmd(string.format("edit %s", path.path))
      vim.api.nvim_win_set_cursor(0, { path.line, 0 })
      vim.api.nvim_buf_add_highlight(0, ns_id, "EasyDotnetTestRunnerFailed", path.line - 1, 0, -1)
    end

    vim.keymap.set("n", "<leader>gf", function()
      go_to_file()
    end, { silent = true, noremap = true, buffer = file_float.buf })

    vim.keymap.set("n", "<leader>gf", function()
      go_to_file()
    end, { silent = true, noremap = true, buffer = stack_trace.buf })


    vim.api.nvim_win_set_cursor(file_float.win, { path.line, 0 })
  end
end



local keymaps = function()
  local keymap = require("easy-dotnet.test-runner.render").options.mappings
  return {
    [keymap.filter_failed_tests.lhs] = function(_, win)
      filter_failed_tests(win)
    end,
    [keymap.refresh_testrunner.lhs]  = function(_, win)
      local function co_wrapper()
        require("easy-dotnet.test-runner.runner").refresh(win.options, win.options.sdk_path, { build = true })
      end

      local co = coroutine.create(co_wrapper)
      coroutine.resume(co)
    end,
    [keymap.debug_test.lhs]          = function(node, win)
      if node.type ~= "test" and node.type ~= "test_group" then
        vim.notify("Debugging is only supported for tests and test_groups")
        return
      end
      local success, dap = pcall(function() return require("dap") end)
      if not success then
        vim.notify("nvim-dap not installed", vim.log.levels.ERROR)
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
        end
      }

      dap.run(dap_configuration)
    end,
    ---@param node Test
    [keymap.go_to_file.lhs]          = function(node, win)
      if node.type == "test" or node.type == "subcase" or node.type == "test_group" then
        if node.file_path ~= nil then
          win.hide()
          vim.cmd("edit " .. node.file_path)
          vim.api.nvim_win_set_cursor(0, { node.line_number and (node.line_number - 1) or 0, 0 })
        end
      else
        vim.notify("Cant go to " .. node.type)
      end
    end,
    [keymap.expand_all.lhs]          = function(_, win)
      ---@param node TestNode
      win.traverse(win.tree, function(node)
        node.expanded = true
      end)

      win.refreshTree()
    end,
    [keymap.collapse_all.lhs]        = function(_, win)
      ---@param node TestNode
      win.traverse(win.tree, function(node)
        node.expanded = false
      end)
      win.refreshTree()
    end,
    ---@param node TestNode
    [keymap.expand.lhs]              = function(node, win)
      node.expanded = node.expanded == false
      win.refreshTree()
    end,
    [keymap.peek_stacktrace.lhs]     = function(node)
      open_stack_trace(node)
    end,
    [keymap.run_all.lhs]             = function(_, win)
      win.traverse(win.tree, function(node)
        if node.type == "csproject" then
          print(node.name)
          run_csproject(win, node)
        end
      end)
    end,
    ---@param node TestNode
    [keymap.run.lhs]                 = function(node, win)
      if node.type == "sln" then
        for _, value in ipairs(win.tree) do
          if value.type == "csproject" and value.solution_file_path == node.solution_file_path then
            run_csproject(win, value)
          end
        end
      elseif node.type == "csproject" then
        run_csproject(win, node)
      elseif node.type == "namespace" then
        run_test_suite(node, win)
      elseif node.type == "test_group" then
        run_test_group(node, win)
      elseif node.type == "subcase" then
        vim.notify("Running specific subcases is not supported")
      elseif node.type == "test" then
        run_test(node, win)
      else
        vim.notify("Unknown line type " .. node.type)
        return
      end
    end,
    [keymap.close.lhs]               = function(_, win)
      win.hide()
    end
  }
end

return keymaps
