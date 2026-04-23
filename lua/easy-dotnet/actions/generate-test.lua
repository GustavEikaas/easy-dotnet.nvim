local M = {}
local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")
local inspect = require("easy-dotnet.test-generation.inspect")
local template = require("easy-dotnet.test-generation.template")
local write = require("easy-dotnet.test-generation.write")

---Resolves all context upfront then prompts for test name and writes the file.
---Must be called within a coroutine context.
---@param method_name string
---@param class_name string
---@param source_file string
local function run_pipeline(method_name, class_name, source_file)
  local sln_path = current_solution.try_get_selected_solution()
  if not sln_path then
    logger.error("generate-test: no solution selected")
    return
  end

  local source_project = inspect.get_source_project(sln_path, source_file)
  if not source_project then
    logger.error("generate-test: could not determine source project for current file")
    return
  end

  local test_projects = inspect.get_test_projects(sln_path, source_project.name)
  if #test_projects == 0 then
    logger.error("generate-test: no test projects found in solution")
    return
  end

  local function proceed_with_project(test_project)
    local framework = inspect.detect_test_framework(test_project.path)
    local test_file_path = inspect.derive_test_file_path(source_file, source_project.path, test_project.path, class_name)
    local namespace = inspect.derive_test_namespace(source_file, source_project.path, test_project.path)

    vim.ui.input({ prompt = "Test name: ", default = method_name }, function(test_name)
      if not test_name or test_name:match("^%s*$") then return end

      if vim.fn.filereadable(test_file_path) == 1 then
        local ok = write.append_method_to_test_file(test_file_path, template.build_test_method_stub(framework, test_name))
        if ok then vim.schedule(function() write.open_and_place_cursor_on_assert(test_file_path, test_name) end) end
      else
        write.write_test_file(test_file_path, template.build_new_test_file(framework, test_name, namespace, class_name))
        vim.schedule(function() write.open_and_place_cursor_on_assert(test_file_path, test_name) end)
      end
    end)
  end

  if #test_projects == 1 then
    proceed_with_project(test_projects[1])
  else
    local choices = vim.tbl_map(function(p) return { display = p.name, value = p } end, test_projects)
    require("easy-dotnet.picker").picker(nil, choices, function(picked)
      if picked then proceed_with_project(picked.value) end
    end, "Select test project", false)
  end
end

---Generates a test method stub for the method under the cursor.
---Prompts the user for the test name, then creates or appends to the mirrored test file.
function M.generate_test()
  if not inspect.assert_ts_parser() then return end

  local method_name, class_name, restricted_modifier = inspect.get_method_context_at_cursor()

  if not method_name then
    logger.error("generate-test: cursor is not inside a method")
    return
  end

  if not class_name then
    logger.error("generate-test: could not determine class name")
    return
  end

  local source_file = vim.fn.expand("%:p")

  local function start()
    local co = coroutine.create(function() run_pipeline(method_name, class_name, source_file) end)
    local ok, err = coroutine.resume(co)
    if not ok then logger.error("generate-test: " .. tostring(err)) end
  end

  if restricted_modifier then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "'" .. method_name .. "' is " .. restricted_modifier .. ". Generate test anyway?",
    }, function(choice)
      if choice == "Yes" then start() end
    end)
  else
    start()
  end
end

return M
