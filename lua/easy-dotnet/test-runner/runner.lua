local M = {}

---@param s string
---@return string
local function trim(s)
  -- Match the string and capture the non-whitespace characters
  return s:match("^%s*(.-)%s*$")
end

---@param tests Test[]
local function sort_tests(tests)
  table.sort(tests, function(a, b)
    -- Extract the base names (without arguments) for comparison
    local base_a = a.namespace:match("([^(]+)") or a
    local base_b = b.namespace:match("([^(]+)") or b

    -- Compare the base names lexicographically
    if base_a == base_b then
      -- If base names are the same, keep the original order (consider the entire string)
      return a.namespace < b.namespace
    else
      return base_a < base_b
    end
  end)
end

---@param tests Test[]
local function expand_test_names_with_flags(tests)
  local offset_indent = 2
  ---@type Test[]
  local expanded = {}
  local seen = {}

  sort_tests(tests)

  for _, test in ipairs(tests) do
    local full_test_name = test.namespace
    -- Extract the base name without arguments, or use the full name if there are no arguments
    local base_name = full_test_name:match("([^%(]+)") or full_test_name
    local has_arguments = full_test_name:find("%(") ~= nil
    local parts = {}
    local segment_count = 0

    -- Count the total number of segments in the base name
    for _ in base_name:gmatch("[^.]+") do
      segment_count = segment_count + 1
    end

    -- Reset the parts and segment_count for actual processing
    parts = {}
    local current_count = 0

    -- Split the base name by dot and process
    for part in base_name:gmatch("[^.]+") do
      table.insert(parts, part)
      current_count = current_count + 1
      local concatenated = table.concat(parts, ".")

      if not seen[concatenated] then
        -- Set is_full_path to true only if we are at the last segment
        local is_full_path = (current_count == segment_count)
        ---@type Test
        local entry = {
          id = test.id,
          name = part,
          full_name = test.full_name,
          solution_file_path = test.solution_file_path,
          cs_project_path = test.cs_project_path,
          highlight = test.highlight,
          hidden = test.hidden,
          expand = test.expand,
          icon = test.icon,
          collapsable = test.collapsable,
          namespace = concatenated,
          value = part,
          is_full_path = is_full_path and not has_arguments,
          indent = (current_count * 2) - 1 + offset_indent,
          preIcon = is_full_path == false and "📂" or has_arguments and "📦" or "🧪",
          type = is_full_path == false and "namespace" or has_arguments and "test_group" or "test",
          line_number = is_full_path and test.line_number or nil,
          file_path = is_full_path and test.file_path or nil
        }
        table.insert(expanded, entry)
        seen[concatenated] = true
      end
    end

    -- -- Add the full test name with arguments (if any) or just the base name
    if has_arguments and not seen[full_test_name] then
      ---@type Test
      local entry = {
        id = test.id,
        namespace = full_test_name,
        name = full_test_name:match("([^.]+%b())$"),
        full_name = test.full_name,
        is_full_path = true,
        indent = (segment_count * 2) + offset_indent,
        preIcon = "🧪",
        type = "subcase",
        collapsable = false,
        icon = nil,
        expand = test.expand,
        highlight = test.highlight,
        cs_project_path = test.cs_project_path,
        solution_file_path = test.solution_file_path,
        hidden = test.hidden,
        line_number = test.line_number,
        file_path = test.file_path
      }
      table.insert(expanded, entry)
      seen[full_test_name] = true
    end
  end

  return expanded
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
--- @field id string
--- @field type "csproject" | "sln" | "namespace" | "test" | "subcase" | "test_group"
--- @field solution_file_path string
--- @field cs_project_path string
--- @field name string
--- @field full_name string
--- @field namespace string
--- @field preIcon string
--- @field collapsable boolean
--- @field indent number
--- @field hidden boolean
--- @field expand table | nil
--- @field icon string | nil
--- @field highlight string | Highlight| nil
--- @field file_path string | nil
--- @field line_number number | nil

local ensure_and_get_fsx_path = function()
  local dir = require("easy-dotnet.constants").get_data_directory()
  local filepath = vim.fs.joinpath(dir, "test_discovery.fsx")
  local file = io.open(filepath, "r")
  if file then
    file:close()
  else
    file = io.open(filepath, "w")
    if file == nil then
      print("Failed to create the file: " .. filepath)
      return
    end
    file:write(require("easy-dotnet.test-runner.discovery").script_template)

    file:close()
  end

  return filepath
end


---@param project Test
---@param options TestRunnerOptions
local function discover_tests_for_project_and_update_lines(project, win, options, dll_path)
  local absolute_dll_path = vim.fs.joinpath(vim.fn.getcwd(), dll_path)
  local command = string.format("dotnet fsi %s '%s' '%s'", ensure_and_get_fsx_path(), options.vstest_path,
    absolute_dll_path)

  local tests = {}
  vim.fn.jobstart(command, {
    on_stderr = function(_, data)
      if #data > 0 and #trim(data[1]) > 0 then
        print(vim.inspect(data))
        error("Failed")
      end
    end,
    ---@param data string[]
    on_stdout = function(_, data)
      for _, stdout_line in ipairs(data) do
        if stdout_line:match("{") then
          local success, test = pcall(function() return vim.fn.json_decode(stdout_line) end)
          if success == true then
            table.insert(tests, test)
          else
            print("Malformed json: " .. test)
          end
        end
      end
    end,
    ---@param code number
    on_exit = function(_, code)
      if code ~= 0 then
        --TODO: check if project was not built
        vim.notify(string.format("Discovering tests for %s failed", project.name))
      else
        ---@type Test[]
        local converted = {}
        for _, value in ipairs(tests) do
          ---@type Test
          local test = {
            id = value.Id,
            name = value.Name,
            full_name = value.Name,
            namespace = value.Name,
            file_path = value.FilePath,
            line_number = value.Linenumber,
            preIcon = "",
            indent = 0,
            collapsable = true,
            type = "test",
            icon = "",
            hidden = false,
            expand = {},
            highlight = nil,
            cs_project_path = project.cs_project_path,
            solution_file_path = project.solution_file_path
          }
          table.insert(converted, test)
        end
        local expanded = expand_test_names_with_flags(converted)

        table.insert(win.lines, project)
        for _, value in ipairs(expanded) do
          table.insert(win.lines, value)
        end
        win.refreshLines()
      end
    end
  })
end

M.runner = function(options)
  ---@type TestRunnerOptions
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
    id = "",
    solution_file_path = solutionFilePath,
    cs_project_path = "",
    type = "sln",
    preIcon = "",
    name = solutionFilePath:match("([^/\\]+)$"),
    full_name = solutionFilePath:match("([^/\\]+)$"),
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
        id = "",
        collapsble = true,
        cs_project_path = value.path,
        solution_file_path = solutionFilePath,
        namespace = "",
        type = "csproject",
        name = value.name,
        full_name = value.name,
        indent = 2,
        preIcon = "",
        hidden = false,
        collapsable = true,
        icon = "",
        expand = {},
        highlight = "Character"
      }
      discover_tests_for_project_and_update_lines(project, win, mergedOpts, value.dll_path)
    end
  end


  win.lines = lines
  win.height = #lines > 20 and 20 or #lines

  win.refreshLines()
end

return M
