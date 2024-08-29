local M = {}

---@param s string
---@return string
local function trim(s)
  -- Match the string and capture the non-whitespace characters
  return s:match("^%s*(.-)%s*$")
end

---@param test_names string[]
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
  ---@type string[]
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

--- @class Highlight
--- @field group string
--- @field column_start number | nil
--- @field column_end number | nil

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
--- @field expand table | nil
--- @field icon string | nil
--- @field highlight string | Highlight| nil


---@return Test[]
---@param project Test
local function discover_tests_for_project_and_update_lines(project, win)
  local command = string.format("dotnet test -t --nologo --no-build --no-restore %s", project.cs_project_path)

  ---@type Test[]
  local lines = {}
  table.insert(lines, project)

  vim.fn.jobstart(command, {
    stdout_buffered = true,
    ---@param data string[]
    on_stdout = function(_, data)
      local tests = extract_tests(data)

      for _, test in ipairs(tests) do
        ---@type Test
        local test_item = {
          name = test.value,
          preIcon = test.preIcon,
          indent = test.indent + 3,
          collapsable = not test.is_full_path,
          type = test.is_full_path and "test" or "namespace",
          namespace = test.ns,
          solution_file_path = project.solution_file_path,
          cs_project_path = project.cs_project_path,
          hidden = true,
          expand = {},
          icon = "",
        }
        table.insert(lines, test_item)
      end
      for _, value in ipairs(lines) do
        table.insert(win.lines, value)
      end
      win.refreshLines()
    end,
    ---@param code number
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify(string.format("Discovering tests for %s failed", project.name))
      end
    end
  })
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
    namespace = "",
    hidden = false,
    collapsable = true,
    icon = "",
    expand = {},
    highlight = "Question"

  }
  table.insert(lines, sln)

  local projects = sln_parse.get_projects_from_sln(solutionFilePath)

  for _, value in ipairs(projects) do
    if value.isTestProject == true then
      ---@type Test
      local project = {
        collapsble = true,
        cs_project_path = value.path,
        solution_file_path = solutionFilePath,
        namespace = "",
        type = "csproject",
        name = value.name,
        indent = 2,
        preIcon = "",
        hidden = false,
        collapsable = true,
        icon = "",
        expand = {},
        highlight = "Character"
      }
      discover_tests_for_project_and_update_lines(project, win)
    end
  end


  win.lines = lines
  win.height = #lines > 20 and 20 or #lines

  win.refreshLines()
end

return M
