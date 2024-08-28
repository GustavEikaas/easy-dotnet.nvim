local messages = require "easy-dotnet.error-messages"
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
  local matches = {}
  for _, line in ipairs(win.lines) do
    if line.cs_project_path == cs_project_path then
      table.insert(matches, { ref = line, line = line.namespace, })
      line.icon = "<Running>"
    end
  end
  win.refreshLines()
  vim.fn.jobstart(
    string.format("dotnet test --nologo --no-build --no-restore %s", cs_project_path), {
      on_stdout = function(_, data)
        if data == nil then
          error("Failed to parse dotnet test output")
        end
        for stdoutIndex, stdout in ipairs(data) do
          for _, match in ipairs(matches) do
            local failed = stdout:match(string.format("%s %s", "Failed", match.line))
            if failed ~= nil then
              match.ref.icon = resultIcons.failed
              match.ref.expand = peekStackTrace(stdoutIndex, data)
            end

            local skipped = stdout:match(string.format("%s %s", "Skipped", match.line))
            if skipped ~= nil then
              match.ref.icon = resultIcons.skipped
            end
          end
        end
        win.refreshLines()
      end,
      on_exit = function(_, code)
        -- If no stdout assume passed
        for _, test in ipairs(matches) do
          if (test.ref.icon == resultIcons.failed or test.ref.icon == resultIcons.skipped) then
          elseif test.ref.collapsable == false then
            test.ref.icon = resultIcons.passed
          end
        end

        -- Aggregate namespace status
        for _, namespace in ipairs(matches) do
          if (namespace.ref.collapsable == true) then
            local worstStatus = nil
            --TODO: check array for worst status
            for _, res in ipairs(matches) do
              if res.line:match(namespace.line) then
                if (res.ref.icon == resultIcons.failed) then
                  worstStatus = resultIcons.failed
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
        if code ~= 0 then
          -- if (line.value:match("<Running>")) then
          --   line.value = original_line .. " <Panic! command failed>"
          --   win.refreshLines()
        end
        -- end
      end
    })
end


local function run_sln(win)
  local matches = {}
  for _, line in ipairs(win.lines) do
    table.insert(matches, { ref = line, line = line.namespace, })
    line.icon = "<Running>"
  end
  win.refreshLines()
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
  local solution_file_path = sln_parse.find_solution_file() or csproj_parse.find_csproj_file()
  if solution_file_path == nil then
    vim.notify(messages.no_project_definition_found)
  end
  vim.fn.jobstart(
    string.format("dotnet test --nologo --no-build --no-restore %s", solution_file_path), {
      on_stdout = function(_, data)
        if data == nil then
          error("Failed to parse dotnet test output")
        end
        for stdoutIndex, stdout in ipairs(data) do
          for _, match in ipairs(matches) do
            local failed = stdout:match(string.format("%s %s", "Failed", match.line))
            if failed ~= nil then
              match.ref.icon = resultIcons.failed
              match.ref.expand = peekStackTrace(stdoutIndex, data)
            end

            local skipped = stdout:match(string.format("%s %s", "Skipped", match.line))
            if skipped ~= nil then
              match.ref.icon = resultIcons.skipped
            end
          end
        end
        win.refreshLines()
      end,
      on_exit = function(_, code)
        -- If no stdout assume passed
        for _, test in ipairs(matches) do
          if (test.ref.icon == resultIcons.failed or test.ref.icon == resultIcons.skipped) then
          elseif test.ref.collapsable == false then
            test.ref.icon = resultIcons.passed
          end
        end

        -- Aggregate namespace status
        for _, namespace in ipairs(matches) do
          if (namespace.ref.collapsable == true) then
            local worstStatus = nil
            --TODO: check array for worst status
            for _, res in ipairs(matches) do
              if res.line:match(namespace.line) then
                if (res.ref.icon == resultIcons.failed) then
                  worstStatus = resultIcons.failed
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
        if code ~= 0 then
          -- if (line.value:match("<Running>")) then
          --   line.value = original_line .. " <Panic! command failed>"
          --   win.refreshLines()
        end
        -- end
      end
    })
end

---@param line Test
local function run_test_suite(line, win)
  -- set all loading
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
    string.format("dotnet test --filter='%s' --nologo --no-build --no-restore %s", suite_name, line.cs_project_path),
    {
      on_stdout = function(_, data)
        if data == nil then
          error("Failed to parse dotnet test output")
        end
        for stdoutIndex, stdout in ipairs(data) do
          for _, match in ipairs(matches) do
            local failed = stdout:match(string.format("%s %s", "Failed", match.line))
            if failed ~= nil then
              match.ref.icon = resultIcons.failed
              match.ref.expand = peekStackTrace(stdoutIndex, data)
            end

            local skipped = stdout:match(string.format("%s %s", "Skipped", match.line))
            if skipped ~= nil then
              match.ref.icon = resultIcons.skipped
            end
          end
        end
        win.refreshLines()
      end,
      on_exit = function(_, code)
        -- If no stdout assume passed
        for _, test in ipairs(matches) do
          if (test.ref.icon == resultIcons.failed or test.ref.icon == resultIcons.skipped) then
          elseif test.ref.collapsable == false then
            test.ref.icon = resultIcons.passed
          end
        end

        -- Aggregate namespace status
        for _, namespace in ipairs(matches) do
          if (namespace.ref.collapsable == true) then
            local worstStatus = nil
            --TODO: check array for worst status
            for _, res in ipairs(matches) do
              if res.line:match(namespace.line) then
                if (res.ref.icon == resultIcons.failed) then
                  worstStatus = resultIcons.failed
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
        if code ~= 0 then
          -- if (line.value:match("<Running>")) then
          --   line.value = original_line .. " <Panic! command failed>"
          --   win.refreshLines()
        end
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
    local buf = vim.api.nvim_create_buf(false, true)
    local width = 70
    local height = 10

    local opts = {
      relative = 'editor',
      width = width,
      height = height,
      col = (vim.o.columns - width) / 2,
      row = (vim.o.lines - height) / 2,
      style = 'minimal',
      border = 'single',
    }
    local win = vim.api.nvim_open_win(buf, true, opts)
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>lua vim.api.nvim_win_close(' .. win .. ', true)<CR>',
      { noremap = true, silent = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, line.expand)
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  end,
  ["<leader>R"] = function(_, _, win)
    run_sln(win)
  end,
  ---@param line Test
  ["<leader>r"] = function(_, line, win)
    if line.type == "sln" then
      local projects = require("easy-dotnet.parsers.sln-parse").get_projects_from_sln(line.solution_file_path)
      for _, value in ipairs(projects) do
        run_csproject(win, value.path)
      end
    elseif line.type == "csproject" then
      vim.notify("Running csproject")
      run_csproject(win, line.cs_project_path)
    elseif line.type == "namespace" then
      vim.notify("Running namespace")
      run_test_suite(line, win)
    elseif line.type == "test" then
      vim.notify("Running Test ")
      line.icon = "<Running>"
      vim.fn.jobstart(
        string.format("dotnet test --filter='%s' --nologo --no-build --no-restore %s", line.namespace,
          line.cs_project_path),
        {
          stdout_buffered = true,
          on_stdout = function(_, data)
            if data then
              local result = nil
              for index, stdout_line in ipairs(data) do
                local failed = stdout_line:match(string.format("%s %s", "Failed", line.namespace))
                if failed ~= nil then
                  line.expand = peekStackTrace(index, data)
                  result = "Failed"
                end
                local skipped = stdout_line:match(string.format("%s %s", "Skipped", line.namespace))

                if skipped ~= nil then
                  result = "Skipped"
                end
              end
              if result == nil then
                result = "Passed"
              end

              line.icon = getIcon(result)
              win.refreshLines()
            end
          end,
          on_exit = function(_, code)
            if code ~= 0 then
              if (line.icon == "<Running>") then
                line.icon = "<Panic! command failed>"
                win.refreshLines()
              end
            end
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
