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

local function run_all(win)
  local matches = {}
  for _, line in ipairs(win.lines) do
    table.insert(matches, { ref = line, line = line.value })
    line.icon = "<Running>"
  end
  win.refreshLines()
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_csproj_file()
  if solutionFilePath == nil then
    vim.notify(messages.no_project_definition_found)
  end
  vim.fn.jobstart(
    string.format("dotnet test --nologo --no-build --no-restore %s", solutionFilePath), {
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

local function run_test_suite(name, win)
  -- set all loading
  local matches = {}
  local suite_name = name
  for _, line in ipairs(win.lines) do
    if line.value:match(suite_name) then
      table.insert(matches, { ref = line, line = line.value })
      line.icon = "<Running>"
    end
  end
  win.refreshLines()
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_csproj_file()
  if solutionFilePath == nil then
    vim.notify(messages.no_project_definition_found)
  end
  vim.fn.jobstart(
    string.format("dotnet test --filter='%s' --nologo --no-build --no-restore %s", suite_name, solutionFilePath), {
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


local keymaps = {
  ["E"] = function(_, _, win)
    for _, value in ipairs(win.lines) do
      value.hidden = false
    end
    win.refreshLines()
  end,
  ["W"] = function(_, _, win)
    for index, value in ipairs(win.lines) do
      if index ~= 1 then
        value.hidden = true
      end
    end
    win.refreshLines()
  end,
  ["o"] = function(index, line, win)
    if line.collapsable == false then
      return
    end

    local action = win.lines[index + 1].hidden == true and "expand" or "collapse"

    local newLines = {}
    for _, lineDef in ipairs(win.lines) do
      if lineDef.value:match(line.value) then
        if lineDef ~= line then
          lineDef.hidden = action == "collapse" and true or false
        end
      end
      table.insert(newLines, lineDef)
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
    run_all(win)
  end,
  ["<leader>r"] = function(_, line, win)
    if line.collapsable then
      run_test_suite(line.value, win)
      return
    end
    local original_line = line.value
    local sln_parse = require("easy-dotnet.parsers.sln-parse")
    local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
    line.icon = "<Running>"
    local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_csproj_file()
    if solutionFilePath == nil then
      vim.notify(messages.no_project_definition_found)
    end
    vim.fn.jobstart(
      string.format("dotnet test --filter='%s' --nologo --no-build --no-restore %s", original_line, solutionFilePath), {
        stdout_buffered = true,
        on_stdout = function(_, data)
          if data then
            local result = nil
            for index, stdout_line in ipairs(data) do
              local failed = stdout_line:match(string.format("%s %s", "Failed", line.value))
              if failed ~= nil then
                line.expand = peekStackTrace(index, data)
                result = "Failed"
              end
              local skipped = stdout_line:match(string.format("%s %s", "Skipped", line.value))

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
  end
}
return keymaps
