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


---@param project Test
---@param options TestRunnerOptions
---@param sdk_path string
---@param dotnet_project DotnetProject
---@param on_job_finished function
local function discover_tests_for_project_and_update_lines(project, win, options, dotnet_project, sdk_path,
                                                           on_job_finished)
  local vstest_dll = vim.fs.joinpath(sdk_path, "vstest.console.dll")
  local absolute_dll_path = vim.fs.joinpath(vim.fn.getcwd(), dotnet_project.get_dll_path())
  local outfile = os.tmpname()
  local script_path = require("easy-dotnet.test-runner.discovery").get_script_path()
  local command = string.format("dotnet fsi %s '%s' '%s' '%s'", script_path, vstest_dll,
    absolute_dll_path, outfile)

  local tests = {}
  vim.fn.jobstart(command, {
    on_stderr = function(_, data)
      if #data > 0 and #trim(data[1]) > 0 then
        print(vim.inspect(data))
        error("Failed")
      end
    end,
    ---@param code number
    on_exit = function(_, code)
      on_job_finished()
      if code ~= 0 then
        --TODO: check if project was not built
        vim.notify(string.format("Discovering tests for %s failed", project.name))
      else
        local file = io.open(outfile)
        if file == nil then
          error("Discovery script emitted no file for " .. project.name)
        end

        for line in file:lines() do
          local success, json_test = pcall(function()
            return vim.fn.json_decode(line)
          end)

          if success then
            if #line ~= 2 then
              table.insert(tests, json_test)
            end
          else
            print("Malformed JSON: " .. line)
          end
        end

        local success = pcall(function()
          os.remove(outfile)
        end)

        if not success then
          print("Failed to delete tmp file " .. outfile)
        end

        ---@type Test[]
        local converted = {}
        for _, value in ipairs(tests) do
          --HACK: This is necessary for MSTest cases where name is not a namespace.classname but rather classname
          local name = value.Name:find("%.") and value.Name or value.Namespace
          ---@type Test
          local test = {
            id = value.Id,
            name = name,
            full_name = name,
            namespace = name,
            file_path = value.FilePath,
            line_number = value.Linenumber,
            preIcon = "",
            indent = 0,
            collapsable = true,
            type = "test",
            icon = "",
            hidden = true,
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

M.runner = function(options, sdk_path)
  ---@type TestRunnerOptions
  local mergedOpts = merge_tables(default_options, options or {})
  local sln_parse = require("easy-dotnet.parsers.sln-parse")
  local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
  local error_messages = require("easy-dotnet.error-messages")

  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_project_file()
  if solutionFilePath == nil then
    vim.notify(error_messages.no_project_definition_found)
    return
  end

  local win = require("easy-dotnet.test-runner.render")
  local is_reused = win.buf ~= nil
  win.buf_name = "Test manager"
  win.filetype = "easy-dotnet"
  win.setKeymaps(require("easy-dotnet.test-runner.keymaps")).render(mergedOpts.viewmode)

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
      local on_job_finished = win.appendJob(value.name, "Discovery")
      vim.schedule(function()
        discover_tests_for_project_and_update_lines(project, win, mergedOpts, value, sdk_path, on_job_finished)
      end)
    end
  end


  win.lines = lines
  win.height = #lines > 20 and 20 or #lines

  win.refreshLines()
end

return M
