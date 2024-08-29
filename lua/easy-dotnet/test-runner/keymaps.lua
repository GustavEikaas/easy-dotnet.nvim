local messages    = require "easy-dotnet.error-messages"
local window      = require "easy-dotnet.test-runner.window"
local resultIcons = {
  passed = "✔",
  skipped = "⏸",
  failed = "❌"
}

local function getIcon(res)
  if res == "Passed" then
    return resultIcons.passed
  elseif res == "Failed" then
    return resultIcons.failed
  elseif res == "Skipped" then
    return resultIcons.skipped
  end
end

local function peekStackTrace(index, lines)
  local stackTrace = {}
  for i, line in ipairs(lines) do
    if i > index then
      local testPattern = "(%w+) ([%w%.]+) %[(.-)%]"
      local newSection = line:match(testPattern)
      if newSection ~= nil then
        break
      else
        table.insert(stackTrace, line)
      end
    end
  end
  return stackTrace
end

local function run_csproject(win, cs_project_path)
  local log_file_name = string.format("%s.xml", cs_project_path:match("([^/\\]+)$"))
  local normalized_path = cs_project_path:gsub('\\', '/')
  -- Find the last slash and extract the directory path
  local directory_path = normalized_path:match('^(.*)/[^/]*$')
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local matches = {}
  for _, line in ipairs(win.lines) do
    if line.cs_project_path == cs_project_path then
      table.insert(matches, { ref = line, line = line.namespace, })
      line.icon = "<Running>"
    end
  end

  win.refreshLines()

  vim.fn.jobstart(
    string.format("dotnet test --nologo --no-build --no-restore %s --logger='trx;logFileName=%s'", cs_project_path,
      log_file_name), {
      on_stdout = function(_, data)
        -- if data == nil then
        --   error("Failed to parse dotnet test output")
        -- end
        -- for stdoutIndex, stdout in ipairs(data) do
        --   for _, match in ipairs(matches) do
        --     local failed = stdout:match(string.format("%s %s", "Failed", match.line))
        --     if failed ~= nil then
        --       match.ref.icon = resultIcons.failed
        --       match.ref.expand = peekStackTrace(stdoutIndex, data)
        --     end
        --
        --     local skipped = stdout:match(string.format("%s %s", "Skipped", match.line))
        --     if skipped ~= nil then
        --       match.ref.icon = resultIcons.skipped
        --     end
        --   end
        -- end
        -- win.refreshLines()
      end,
      on_exit = function(_, code)
        require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
          ---@param unit_test_results TestCase[]
          function(unit_test_results)
            for _, test_result in ipairs(unit_test_results) do
              local test_name = test_result["@testName"]
              local outcome = test_result["@outcome"]
              for _, test_line in ipairs(win.lines) do
                if test_line.cs_project_path == cs_project_path and test_line.type == "test" and test_line.namespace == test_name then
                  --TODO: handle more cases like cancelled etc...
                  if outcome == "Passed" then
                    test_line.icon = resultIcons.passed
                  elseif outcome == "Failed" then
                    test_line.icon = resultIcons.failed
                    test_line.expand = vim.split(test_result.Output.ErrorInfo.StackTrace, "\n")
                  elseif outcome == "NotExecuted" then
                    test_line.icon = resultIcons.skipped
                  else
                    test_line.icon = "??"
                  end
                end
              end
            end

            --aggregate namespaces/csproject status
            for _, namespace in ipairs(matches) do
              if (namespace.ref.collapsable == true) then
                local worstStatus = nil
                --TODO: check array for worst status
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
            win.refreshLines()
          end)

        -- if code ~= 0 then
        --   vim.notify("dotnet test command failed")
        -- end
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
      on_stdout = function(_, data)
        -- if data == nil then
        --   error("Failed to parse dotnet test output")
        -- end
        -- for stdoutIndex, stdout in ipairs(data) do
        --   for _, match in ipairs(matches) do
        --     local failed = stdout:match(string.format("%s %s", "Failed", match.line))
        --     if failed ~= nil then
        --       match.ref.icon = resultIcons.failed
        --       match.ref.expand = peekStackTrace(stdoutIndex, data)
        --     end
        --
        --     local skipped = stdout:match(string.format("%s %s", "Skipped", match.line))
        --     if skipped ~= nil then
        --       match.ref.icon = resultIcons.skipped
        --     end
        --   end
        -- end
        -- win.refreshLines()
      end,
      on_exit = function(_, code)
        require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
          ---@param unit_test_results TestCase[]
          function(unit_test_results)
            for _, test_result in ipairs(unit_test_results) do
              local test_name = test_result["@testName"]
              local outcome = test_result["@outcome"]
              for _, test_line in ipairs(win.lines) do
                if test_line.cs_project_path == line.cs_project_path and test_line.type == "test" and test_line.namespace == test_name then
                  --TODO: handle more cases like cancelled etc...
                  if outcome == "Passed" then
                    test_line.icon = resultIcons.passed
                  elseif outcome == "Failed" then
                    test_line.icon = resultIcons.failed
                    test_line.expand = vim.split(test_result.Output.ErrorInfo.StackTrace, "\n")
                  elseif outcome == "NotExecuted" then
                    test_line.icon = resultIcons.skipped
                  else
                    test_line.icon = "??"
                  end
                end
              end
            end


            for _, namespace in ipairs(matches) do
              if (namespace.ref.collapsable == true) then
                local worstStatus = nil
                --TODO: check array for worst status
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
            win.refreshLines()
          end)

        -- if code ~= 0 then
        --   vim.notify("dotnet test command failed")
        -- end
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
    elseif line.type == "test" then
      --TODO: go to file
      return
    end

    win.lines = newLines
    win.refreshLines()
  end,
  ["<leader>p"] = function(_, line)
    if line.expand == nil then
      return
    end

    local path = get_path_from_stack_trace(line.expand)

    if path ~= nil then
      local contents = vim.fn.readfile(path.path)

      local file_float = window.new_float():pos_center():write_buf(contents):buf_set_filetype("csharp"):create()

      vim.api.nvim_win_set_cursor(file_float.win, { path.line, 0 })
      local ns_id = require("easy-dotnet.constants").ns_id

      local s = {}
      for _, value in ipairs(line.expand) do
        table.insert(s, { value, "ErrorMsg" })
      end

      vim.api.nvim_buf_set_virtual_text(file_float.buf, ns_id, path.line - 1, s, {})
    end
  end,
  ["<leader>R"] = function(_, line, win)
    local projects = require("easy-dotnet.parsers.sln-parse").get_projects_from_sln(line.solution_file_path)
    for _, value in ipairs(projects) do
      if value.isTestProject == true then
        run_csproject(win, value.path)
      end
    end
  end,
  ---@param line Test
  ["<leader>r"] = function(_, line, win)
    if line.type == "sln" then
      local projects = require("easy-dotnet.parsers.sln-parse").get_projects_from_sln(line.solution_file_path)
      for _, value in ipairs(projects) do
        if value.isTestProject == true then
          run_csproject(win, value.path)
        end
      end
    elseif line.type == "csproject" then
      run_csproject(win, line.cs_project_path)
    elseif line.type == "namespace" then
      run_test_suite(line, win)
    elseif line.type == "test" then
      vim.notify(line.cs_project_path)
      local log_file_name = string.format("%s.xml", line.name)
      local normalized_path = line.cs_project_path:gsub('\\', '/')
      local directory_path = normalized_path:match('^(.*)/[^/]*$')
      local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

      local command = string.format(
        "dotnet test --filter='%s' --nologo --no-build --no-restore %s --logger='trx;logFileName=%s'",
        line.namespace:gsub("%b()", ""), line.cs_project_path, log_file_name)

      require("easy-dotnet.debug").write_to_log(command)
      line.icon = "<Running>"
      vim.fn.jobstart(
        command, {
          stdout_buffered = true,
          on_stdout = function(_, data)
            -- if data then
            --   local result = nil
            --   for index, stdout_line in ipairs(data) do
            --     local failed = stdout_line:match(string.format("%s %s", "Failed", line.namespace))
            --     if failed ~= nil then
            --       line.expand = peekStackTrace(index, data)
            --       result = "Failed"
            --     end
            --     local skipped = stdout_line:match(string.format("%s %s", "Skipped", line.namespace))
            --
            --     if skipped ~= nil then
            --       result = "Skipped"
            --     end
            --   end
            --   if result == nil then
            --     result = "Passed"
            --   end
            --
            --   line.icon = getIcon(result)
            --   win.refreshLines()
          end,
          on_exit = function(_, code)
            require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
              ---@param unit_test_results TestCase
              function(unit_test_results)
                local test_name = unit_test_results["@testName"]
                local outcome = unit_test_results["@outcome"]

                if test_name == line.namespace then
                  if outcome == "Passed" then
                    line.icon = resultIcons.passed
                  elseif outcome == "Failed" then
                    line.icon = resultIcons.failed
                    line.expand = vim.split(unit_test_results.Output.ErrorInfo.StackTrace, "\n")
                  elseif outcome == "NotExecuted" then
                    line.icon = resultIcons.skipped
                  else
                    line.icon = "??"
                  end
                end

                win.refreshLines()
              end)


            -- TODO: If the tests are failing then exit code 1 is expected
            -- if code ~= 0 then
            --   if (line.icon == "<Running>") then
            --     line.icon = "<Panic! command failed>"
            --     win.refreshLines()
            --   end
            -- end
          end
        })

      win.refreshLines()
    else
      vim.notify("Unknown line type " .. line.type)
      return
    end
  end
}
return keymaps
