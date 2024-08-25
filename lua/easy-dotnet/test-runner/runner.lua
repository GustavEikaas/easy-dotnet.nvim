local M = {}

local function trim(s)
  -- Match the string and capture the non-whitespace characters
  return s:match("^%s*(.-)%s*$")
end

local function expand_test_names_with_flags(test_names)
  local expanded = {}
  local seen = {}

  for _, full_test_name in ipairs(test_names) do
    local parts = {}
    local segment_count = 0

    -- Count the total number of segments
    for _ in full_test_name:gmatch("[^.]+") do
      segment_count = segment_count + 1
    end

    -- Reset the parts and segment_count for actual processing
    parts = {}
    local current_count = 0

    -- Split the test name by dot and process
    for part in full_test_name:gmatch("[^.]+") do
      table.insert(parts, part)
      current_count = current_count + 1
      local concatenated = trim(table.concat(parts, "."))

      if not seen[concatenated] then
        -- Set is_full_path to true only if we are at the last segment
        local is_full_path = (current_count == segment_count)
        table.insert(expanded,
          {
            value = concatenated,
            is_full_path = is_full_path,
            indent = current_count - 1,
            preIcon = is_full_path == false and "📂" or "🧪"
          })
        seen[concatenated] = true
      end
    end
  end

  return expanded
end

local function extract_tests(lines)
  local tests = {}

  -- Extract lines that match the pattern for test names
  for _, line in ipairs(lines) do
    if not (line:match("^Test run for") or line:match("^No test is available in") or line:match("^The following Tests are available:") or line == "") then
      table.insert(tests, line)
    end
  end


  return expand_test_names_with_flags(tests)
end

local function merge_tables(table1, table2)
  local merged = {}
  for k, v in pairs(table1) do
    merged[k] = v
  end
  for k, v in pairs(table2) do
    merged[k] = v
  end
  return merged
end

local default_options = require("easy-dotnet.options").test_runner

M.runner = function(options)
  local mergedOpts = merge_tables(default_options, options or {})
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
  local error_messages = require("easy-dotnet.error-messages")

  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_csproj_file()
  if solutionFilePath == nil then
    vim.notify(error_messages.no_project_definition_found)
    return
  end

  local win = require("easy-dotnet.test-runner.render")
  local is_reused = win.buf ~= nil
  win.buf_name = "Test manager"
  win.filetype = "easy-dotnet"
  win.setKeymaps(require("easy-dotnet.test-runner.keymaps")).render()

  if is_reused then
    return
  end

  local command = string.format("dotnet test -t --nologo %s %s %s", mergedOpts.noBuild == true and "--no-build" or "",
    mergedOpts.noRestore == true and "--no-restore" or "", solutionFilePath)
  vim.fn.jobstart(
    command, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if data then
          --TODO:find a better way to handle this
          if #data == 1 then
            win.lines = { { value = "Failed to discover tests", preIcon = "❌" } }
          else
            local tests = extract_tests(data)
            local lines = {}
            for _, test in ipairs(tests) do
              table.insert(lines,
                {
                  value = test.value,
                  collapsable = test.is_full_path == false,
                  indent = test.indent,
                  preIcon = test.preIcon
                })
            end

            win.lines = lines
            win.height = #lines > 20 and 20 or #lines
          end
          win.refreshLines()
        end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          win.lines = { { value = "Failed to discover tests", preIcon = "❌" } }
          win.refreshLines()
        end
      end
    })
end

return M
