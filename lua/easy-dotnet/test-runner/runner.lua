local M = {}

local function trim(s)
  -- Match the string and capture the non-whitespace characters
  return s:match("^%s*(.-)%s*$")
end

local function expand_test_names_with_flags(test_names)
  local expanded = {}
  local seen = {}

  -- Sort the test_names based on the number of segments and lexicographically
  table.sort(test_names, function(a, b)
    local a_segment_count = #a:gsub("[^.]+", "")
    local b_segment_count = #b:gsub("[^.]+", "")

    if a_segment_count == b_segment_count then
      return a < b -- Lexicographical order if segment counts are the same
    else
      return a_segment_count < b_segment_count
    end
  end)

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
            ns = concatenated,
            value = trim(part),
            is_full_path = is_full_path,
            indent = (current_count * 2) - 1,
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
    if not #(trim(line)) == 0 or not (line:match("^Test run for") or line:match("^No test is available in") or line:match("^The following Tests are available:") or line == "") then
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

--- @class Test
--- @field type "csproject" | "sln" | "namespace" | "test"
--- @field solution_file_path string
--- @field cs_project_path string
--- @field name string
--- @field namespace string
--- @field preIcon string
--- @field collapsable boolean
--- @field indent number
--- @field hidden boolean
--- @field expand table
--- @field icon string


-- local function discover_tests_for_project(project_path, solution_file_path, co)
--   local command = string.format("dotnet test -t --nologo --no-build --no-restore %s", project_path)
--   local err_lines = {}
--   local lines = {}
--
--   vim.fn.jobstart(
--     command, {
--       stdout_buffered = true,
--       on_stderr = function(_, data)
--         for _, line in ipairs(data) do
--           if #line > 0 then
--             table.insert(err_lines, { value = line, preIcon = "❌" })
--           end
--         end
--       end,
--       on_stdout = function(_, data)
--         if data then
--           --TODO:find a better way to handle this
--           if #data == 1 then
--             --TODO: error handling
--           else
--             local tests = extract_tests(data)
--             for _, test in ipairs(tests) do
--               ---@type Test
--               local test_item = {
--                 name = test.value,
--                 preIcon = test.preIcon,
--                 indent = test.indent,
--                 collapsable = test.is_full_path == false,
--                 type = test.is_full_path == true and "test" or "namespace",
--                 namespace = test.ns,
--                 solution_file_path = solution_file_path,
--                 cs_project_path = project_path
--               }
--               table.insert(lines, test_item)
--             end
--           end
--         end
--       end,
--       on_exit = function(_, code)
--         coroutine.resume(co)
--         if code ~= 0 then
--           vim.notify("command failed")
--           -- -- win.lines = { { value = "Failed to discover tests", preIcon = "❌" } }
--           -- win.lines = err_lines
--           -- win.refreshLines()
--         end
--       end
--     })
--   coroutine.yield()
--   return lines
-- end
--
--
---@return Test[]
local function discover_tests_for_project(project_path, solution_file_path)
  local command = string.format(
    "dotnet test -t --nologo --no-build --no-restore %s",
    project_path
  )

  -- Use vim.fn.system to run the command synchronously
  local output = vim.fn.system(command)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify("Command failed with exit code: " .. exit_code, vim.log.levels.ERROR)
    return {}
  end

  local lines = {}
  local tests = extract_tests(vim.split(output, "\n", { trimempty = true }))

  for _, test in ipairs(tests) do
    ---@type Test
    local test_item = {
      name = test.value,
      preIcon = test.preIcon,
      indent = test.indent + 3,
      collapsable = not test.is_full_path,
      type = test.is_full_path and "test" or "namespace",
      namespace = test.ns,
      solution_file_path = solution_file_path,
      cs_project_path = project_path,
      hidden = true
    }
    table.insert(lines, test_item)
  end

  return lines
end

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

  ---@type Test[]
  local lines = {}

  --Find sln
  ---@type Test
  local sln = {
    solution_file_path = solutionFilePath,
    cs_project_path = "",
    type = "sln",
    preIcon = "",
    name = solutionFilePath:match("([^/\\]+)$"),
    indent = 0,
    collapsable = true,
    namespace = "",
    hidden = false
  }
  table.insert(lines, sln)

  local projects = sln_parse.get_projects_from_sln(solutionFilePath)

  for _, value in ipairs(projects) do
    if value.isTestProject == true then
      ---@type Test
      local project = {
        collapsable = true,
        cs_project_path = value.path,
        solution_file_path = solutionFilePath,
        namespace = "",
        type = "csproject",
        name = value.name,
        indent = 2,
        preIcon = "",
        hidden = false
      }
      table.insert(lines, project)
      local tests = discover_tests_for_project(value.path, solutionFilePath)
      for _, test in ipairs(tests) do
        table.insert(lines, test)
      end
    end
  end


  win.lines = lines
  win.height = #lines > 20 and 20 or #lines

  -- find csprojects and foreach

  win.refreshLines()
end

return M
