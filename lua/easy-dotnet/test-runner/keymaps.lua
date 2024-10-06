local window = require "easy-dotnet.test-runner.window"

local function aggregateStatus(matches, options)
  for _, namespace in ipairs(matches) do
    if (namespace.ref.collapsable == true) then
      local worstStatus = nil
      for _, res in ipairs(matches) do
        if res.line:match(namespace.line) then
          if (res.ref.icon == options.icons.failed) then
            worstStatus = options.icons.failed
            namespace.ref.expand = res.ref.expand
          elseif res.ref.icon == options.icons.skipped then
            if worstStatus ~= options.icons.failed then
              worstStatus = options.icons.skipped
            end
          end
        end
      end
      namespace.ref.icon = worstStatus == nil and options.icons.passed or worstStatus
    end
  end
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


local function parse_log_file(relative_log_file_path, win, matches, on_completed)
  require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
    ---@param unit_test_results TestCase[]
    function(unit_test_results)
      if #unit_test_results == 0 then
        for _, value in ipairs(matches) do
          if value.ref.icon == "<Running>" then
            value.ref.icon = "<No status reported>"
            on_completed()
          end
        end
        win.refreshLines()
        return
      end

      for _, match in ipairs(matches) do
        local test_line = match.ref
        if test_line.type == "test" or test_line.type == "subcase" then
          for _, value in ipairs(unit_test_results) do
            if match.id == value.id then
              parse_status(value, test_line, win.options)
            end
          end
        end
      end

      aggregateStatus(matches, win.options)
      on_completed()
      win.refreshLines()
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

local function run_csproject(win, cs_project_path)
  local log_file_name = string.format("%s.xml", cs_project_path:match("([^/\\]+)$"))
  local normalized_path = cs_project_path:gsub('\\', '/')
  -- Find the last slash and extract the directory path
  local directory_path = normalized_path:match('^(.*)/[^/]*$')
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local matches = {}
  local testcount = 0
  for _, line in ipairs(win.lines) do
    if line.cs_project_path == cs_project_path then
      table.insert(matches, { ref = line, line = line.namespace, id = line.id })
      line.icon = "<Running>"
      if line.type == "test" or line.type == "subcase" then
        testcount = testcount + 1
      end
    end
  end

  local on_job_finished = win.appendJob(cs_project_path, "Run", testcount)

  win.refreshLines()
  vim.fn.jobstart(
    string.format("dotnet test --nologo %s %s --logger='trx;logFileName=%s'", get_dotnet_args(win.options),
      cs_project_path,
      log_file_name), {
      on_exit = function(_, code)
        parse_log_file(relative_log_file_path, win, matches, on_job_finished)
      end
    })
end


---@param line Test
local function run_test_group(line, win)
  local log_file_name = string.format("%s.xml", line.name)
  local normalized_path = line.cs_project_path:gsub('\\', '/')
  local directory_path = normalized_path:match('^(.*)/[^/]*$')
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local matches = {}
  local suite_name = line.namespace
  local testcount = 0
  for _, test_line in ipairs(win.lines) do
    if line.name == test_line.name:gsub("%b()", "") and line.cs_project_path == test_line.cs_project_path and line.solution_file_path == test_line.solution_file_path then
      table.insert(matches, { ref = test_line, line = test_line.namespace, id = test_line.id })
      test_line.icon = "<Running>"
      if test_line.type == "test" or test_line.type == "subcase" then
        testcount = testcount + 1
      end
    end
  end
  win.refreshLines()

  local on_job_finished = win.appendJob(line.name, "Run", testcount)
  vim.fn.jobstart(
    string.format("dotnet test --filter='%s' --nologo %s %s --logger='trx;logFileName=%s'",
      suite_name, get_dotnet_args(win.options), line.cs_project_path, log_file_name),
    {
      on_exit = function()
        parse_log_file(relative_log_file_path, win, matches, on_job_finished)
      end
    })
end



---@param line Test
local function run_test_suite(line, win)
  local log_file_name = string.format("%s.xml", line.namespace)
  local normalized_path = line.cs_project_path:gsub('\\', '/')
  local directory_path = normalized_path:match('^(.*)/[^/]*$')
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local matches = {}
  local testcount = 0
  local suite_name = line.namespace
  for _, test_line in ipairs(win.lines) do
    if test_line.namespace:match(suite_name) and line.cs_project_path == test_line.cs_project_path and line.solution_file_path == test_line.solution_file_path then
      table.insert(matches, { ref = test_line, line = test_line.namespace, id = test_line.id })
      if test_line.type == "test" or test_line.type == "subcase" then
        testcount = testcount + 1
      end
      test_line.icon = "<Running>"
    end
  end
  win.refreshLines()

  local on_job_finished = win.appendJob(line.namespace, "Run", testcount)
  vim.fn.jobstart(
    string.format("dotnet test --filter='%s' --nologo %s %s --logger='trx;logFileName=%s'",
      suite_name, get_dotnet_args(win.options), line.cs_project_path, log_file_name),
    {
      on_exit = function()
        parse_log_file(relative_log_file_path, win, matches, on_job_finished)
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
  if win.filter == nil and isAnyErr(win.lines, win.options) then
    for _, value in ipairs(win.lines) do
      if value.icon ~= win.options.icons.failed then
        value.hidden = true
      end
    end
    win.filter = "failed"
  else
    for _, value in ipairs(win.lines) do
      value.hidden = false
    end
    win.filter = nil
  end
  win.refreshLines()
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

local function run_test(line, win)
  local log_file_name = string.format("%s.xml", line.name)
  local normalized_path = line.cs_project_path:gsub('\\', '/')
  local directory_path = normalized_path:match('^(.*)/[^/]*$')
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local command = string.format(
    "dotnet test --filter='%s' --nologo %s %s --logger='trx;logFileName=%s'",
    line.namespace:gsub("%b()", ""), get_dotnet_args(win.options), line.cs_project_path, log_file_name)

  local on_job_finished = win.appendJob(line.name, "Run")

  line.icon = "<Running>"
  vim.fn.jobstart(
    command, {
      on_exit = function()
        require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
          ---@param unit_test_results TestCase
          function(unit_test_results)
            local result = unit_test_results[1]
            if result == nil then
              error(string.format("Status of %s was not present in xml file", line.name))
            end
            parse_status(result, line, win.options)
            on_job_finished()
            win.refreshLines()
          end)
      end
    })

  win.refreshLines()
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

local function expand_section(line, index, win)
  local newLines = {}
  local action = win.lines[index + 1].hidden == true and "expand" or "collapse"

  if line.type == "sln" then
    for _, lineDef in ipairs(win.lines) do
      if line.solution_file_path == lineDef.solution_file_path then
        if lineDef ~= line then
          lineDef.hidden = action == "collapse" and true or false
        end
      end
      table.insert(newLines, lineDef)
    end
  elseif line.type == "csproject" then
    for _, lineDef in ipairs(win.lines) do
      if line.cs_project_path == lineDef.cs_project_path and line.solution_file_path == lineDef.solution_file_path then
        if lineDef ~= line then
          lineDef.hidden = action == "collapse" and true or false
        end
      end
      table.insert(newLines, lineDef)
    end
  elseif line.type == "namespace" then
    for _, lineDef in ipairs(win.lines) do
      if lineDef.namespace:match(line.namespace) and line.cs_project_path == lineDef.cs_project_path and line.solution_file_path == lineDef.solution_file_path then
        if lineDef ~= line then
          lineDef.hidden = action == "collapse" and true or false
        end
      end
      table.insert(newLines, lineDef)
    end
  elseif line.type == "test_group" then
    for _, test_line in ipairs(win.lines) do
      if test_line.type == "subcase" and line.namespace == test_line.namespace:gsub("%b()", "") then
        if line ~= test_line then
          test_line.hidden = action == "collapse" and true or false
        end
      end
      table.insert(newLines, test_line)
    end
  elseif line.type == "test" or line.type == "subcase" then
    --TODO: go to file
    return
  else
    error(string.format("Unknown linetype %s", line.type))
  end


  win.lines = newLines
  win.refreshLines()
end


local keymaps = {
  ["<leader>fe"] = function(_, _, win)
    filter_failed_tests(win)
  end,
  ["<leader>d"] = function(_, line, win)
    if line.type ~= "test" and line.type ~= "test_group" then
      vim.notify("Debugging is only supported for tests and test_groups")
      return
    end
    local dap = require("dap")
    vim.cmd("Dotnet testrunner")
    vim.cmd("edit " .. line.file_path)
    print(vim.inspect(line))
    vim.api.nvim_win_set_cursor(0, { line.line_number and (line.line_number - 1) or 0, 0 })
    dap.toggle_breakpoint()

    local dap_configuration = {
      type = "coreclr",
      name = line.name,
      request = "attach",
      processId = function()
        local project_path = line.cs_project_path
        local res = require("easy-dotnet").experimental.start_debugging_test_project(project_path)
        return res.process_id
      end
    }

    dap.run(dap_configuration)
  end,
  ---@param line Test
  ["g"] = function(_, line, win)
    if line.type == "test" or line.type == "subcase" or line.type == "test_group" then
      if line.file_path ~= nil then
        vim.cmd("edit " .. line.file_path)
        vim.api.nvim_win_set_cursor(0, { line.line_number and (line.line_number - 1) or 0, 0 })
      end
    else
      vim.notify("Cant go to " .. line.type)
    end
  end,
  ["E"] = function(_, _, win)
    for _, value in ipairs(win.lines) do
      value.hidden = false
    end
    win.refreshLines()
  end,
  ["W"] = function(_, _, win)
    for _, value in ipairs(win.lines) do
      if not (value.type == "csproject" or value.type == "sln") then
        value.hidden = true
      end
    end
    win.refreshLines()
  end,
  ---@param index number
  ---@param line Test
  ["o"] = function(index, line, win)
    expand_section(line, index, win)
  end,
  ["<leader>p"] = function(_, line)
    open_stack_trace(line)
  end,
  ["<leader>R"] = function(_, _, win)
    for _, value in ipairs(win.lines) do
      if value.type == "csproject" then
        run_csproject(win, value.cs_project_path)
      end
    end
  end,
  ---@param line Test
  ["<leader>r"] = function(_, line, win)
    if line.type == "sln" then
      for _, value in ipairs(win.lines) do
        if value.type == "csproject" and value.solution_file_path == line.solution_file_path then
          run_csproject(win, value.cs_project_path)
        end
      end
    elseif line.type == "csproject" then
      run_csproject(win, line.cs_project_path)
    elseif line.type == "namespace" then
      run_test_suite(line, win)
    elseif line.type == "test_group" then
      run_test_group(line, win)
    elseif line.type == "subcase" then
      vim.notify("Running specific subcases is not supported")
    elseif line.type == "test" then
      run_test(line, win)
    else
      vim.notify("Unknown line type " .. line.type)
      return
    end
  end,
  ["q"] = function()
    vim.cmd("Dotnet testrunner")
  end
}

return keymaps
