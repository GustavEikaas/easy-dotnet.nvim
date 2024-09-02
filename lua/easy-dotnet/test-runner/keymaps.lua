local window = require "easy-dotnet.test-runner.window"

local resultIcons = {
  passed = "✔",
  skipped = "⏸",
  failed = "❌"
}

local function aggregateStatus(matches)
  for _, namespace in ipairs(matches) do
    if (namespace.ref.collapsable == true) then
      local worstStatus = nil
      for _, res in ipairs(matches) do
        if res.line:match(namespace.line) then
          if (res.ref.icon == resultIcons.failed) then
            worstStatus = resultIcons.failed
            namespace.ref.expand = res.ref.expand
          elseif res.ref.icon == resultIcons.skipped then
            if worstStatus ~= resultIcons.failed then
              worstStatus = resultIcons.skipped
            end
          end
        end
      end
      namespace.ref.icon = worstStatus == nil and resultIcons.passed or worstStatus
    end
  end
end


local function parse_status(result, test_line)
  --TODO: handle more cases like cancelled etc...
  if result.outcome == "Passed" then
    test_line.icon = resultIcons.passed
  elseif result.outcome == "Failed" then
    test_line.icon = resultIcons.failed
    test_line.expand = vim.split(result.stackTrace, "\n")
  elseif result.outcome == "NotExecuted" then
    test_line.icon = resultIcons.skipped
  else
    test_line.icon = "??"
  end
end


local function parse_log_file(relative_log_file_path, win, matches)
  require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
    ---@param unit_test_results TestCase[]
    function(unit_test_results)
      for _, match in ipairs(matches) do
        local test_line = match.ref
        if test_line.type == "test" or test_line.type == "subcase" then
          local result = unit_test_results[match.line]
          if result == nil then
            error(string.format("Status of %s was not present in xml file", match.line))
          end
          parse_status(result, test_line)
        end
      end
      aggregateStatus(matches)
      win.refreshLines()
    end)
end

local function run_csproject(win, cs_project_path)
  local log_file_name = string.format("%s.xml", cs_project_path:match("([^/\\]+)$"))
  local normalized_path = cs_project_path:gsub('\\', '/')
  -- Find the last slash and extract the directory path
  local directory_path = normalized_path:match('^(.*)/[^/]*$')
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local matches = {}
  for _, line in ipairs(win.lines) do
    --TODO: ensure sln
    if line.cs_project_path == cs_project_path then
      table.insert(matches, { ref = line, line = line.namespace, })
      line.icon = "<Running>"
    end
  end

  win.refreshLines()

  vim.fn.jobstart(
    string.format("dotnet test --nologo --no-build --no-restore %s --logger='trx;logFileName=%s'", cs_project_path,
      log_file_name), {
      on_exit = function(_, code)
        parse_log_file(relative_log_file_path, win, matches)
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
  for _, test_line in ipairs(win.lines) do
    if line.name == test_line.name:gsub("%b()", "") and test_line.namespace:match(suite_name) and line.cs_project_path == test_line.cs_project_path and line.solution_file_path == test_line.solution_file_path then
      table.insert(matches, { ref = test_line, line = test_line.namespace })
      test_line.icon = "<Running>"
    end
  end
  win.refreshLines()

  vim.fn.jobstart(
    string.format("dotnet test --filter='%s' --nologo --no-build --no-restore %s --logger='trx;logFileName=%s'",
      suite_name, line.cs_project_path, log_file_name),
    {
      on_exit = function()
        parse_log_file(relative_log_file_path, win, matches)
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
  local suite_name = line.namespace
  for _, test_line in ipairs(win.lines) do
    if test_line.namespace:match(suite_name) and line.cs_project_path == test_line.cs_project_path and line.solution_file_path == test_line.solution_file_path then
      table.insert(matches, { ref = test_line, line = test_line.namespace })
      test_line.icon = "<Running>"
    end
  end
  win.refreshLines()

  vim.fn.jobstart(
    string.format("dotnet test --filter='%s' --nologo --no-build --no-restore %s --logger='trx;logFileName=%s'",
      suite_name, line.cs_project_path, log_file_name),
    {
      on_exit = function()
        parse_log_file(relative_log_file_path, win, matches)
      end
    })
end

local function isAnyErr(lines)
  local err = false
  for _, value in ipairs(lines) do
    if value.icon == resultIcons.failed then
      err = true
      return err
    end
  end

  return err
end

local function filter_failed_tests(win)
  if win.filter == nil and isAnyErr(win.lines) then
    for _, value in ipairs(win.lines) do
      if value.icon ~= resultIcons.failed then
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
    "dotnet test --filter='%s' --nologo --no-build --no-restore %s --logger='trx;logFileName=%s'",
    line.namespace:gsub("%b()", ""), line.cs_project_path, log_file_name)

  line.icon = "<Running>"
  vim.fn.jobstart(
    command, {
      on_exit = function()
        require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
          ---@param unit_test_results TestCase
          function(unit_test_results)
            local result = unit_test_results[line.namespace]
            if result == nil then
              error(string.format("Status of %s was not present in xml file", line.namespace))
            end
            parse_status(result, line)
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
      vim.api.nvim_buf_add_highlight(0, ns_id, "ErrorMsg", path.line - 1, 0, -1)
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
  end
}

return keymaps
