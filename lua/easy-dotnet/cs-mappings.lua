local M = {}

local function find_csproj_for_cs_file(cs_file_path, maxdepth)
  local curr_depth = 0

  local function get_directory(path)
    return vim.fn.fnamemodify(path, ":h")
  end

  local function find_csproj_in_directory(dir)
    local result = vim.fn.globpath(dir, "*.csproj", false, true)
    if #result > 0 then
      return result[1]
    end
    return nil
  end

  local cs_file_dir = vim.fs.dirname(cs_file_path)

  while cs_file_dir ~= "/" and cs_file_dir ~= "~" and cs_file_dir ~= "" and curr_depth < maxdepth do
    curr_depth = curr_depth + 1
    local csproj_file = find_csproj_in_directory(cs_file_dir)
    if csproj_file then
      return csproj_file
    end
    cs_file_dir = get_directory(cs_file_dir)
  end

  return nil
end

local function generate_csharp_namespace(cs_file_path, csproj_path, maxdepth)
  local curr_depth = 0

  local function get_parent_directory(path)
    return vim.fn.fnamemodify(path, ":h")
  end

  local function get_basename_without_ext(path)
    return vim.fn.fnamemodify(path, ":t:r")
  end

  local cs_file_dir = vim.fs.dirname(cs_file_path)
  local csproj_dir = vim.fs.dirname(csproj_path)

  local csproj_basename = get_basename_without_ext(csproj_path)

  local relative_path_parts = {}
  while cs_file_dir ~= csproj_dir and cs_file_dir ~= "/" and cs_file_dir ~= "~" and cs_file_dir ~= "" and curr_depth < maxdepth do
    table.insert(relative_path_parts, 1, vim.fn.fnamemodify(cs_file_dir, ":t"))
    cs_file_dir = get_parent_directory(cs_file_dir)
    curr_depth = curr_depth + 1
  end

  if cs_file_dir ~= csproj_dir then
    return nil, "The .cs file is not located under the .csproj directory."
  end

  table.insert(relative_path_parts, 1, csproj_basename)
  return table.concat(relative_path_parts, ".")
end

local function is_buffer_empty(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for _, line in ipairs(lines) do
    if line ~= "" then
      return false
    end
  end
  return true
end

local function auto_bootstrap_namespace(bufnr)
  local max_depth = 50
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  if not is_buffer_empty(bufnr) then
    return
  end

  local csproject_file_path = find_csproj_for_cs_file(curr_file, max_depth)
  if not csproject_file_path then
    vim.notify("Failed to bootstrap namespace, csproject file not found", vim.log.levels.WARN)
    return
  end
  local namespace = generate_csharp_namespace(curr_file, csproject_file_path, max_depth)
  local file_name = vim.fn.fnamemodify(curr_file, ":t:r")

  local is_interface = file_name:sub(1, 1) == "I" and file_name:sub(2, 2):match("%u")
  local type_keyword = is_interface and "interface" or "class"

  local bootstrap_lines = {
    string.format("namespace %s", namespace),
    "{",
    string.format("  public %s %s", type_keyword, file_name),
    "  {",
    "",
    "  }",
    "}",
    " "
  }

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, bootstrap_lines)
  vim.cmd("w")
end

M.auto_bootstrap_namespace = function()
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = "*.cs",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      auto_bootstrap_namespace(bufnr)
    end
  })
end

local function compare_paths(path1, path2)
  local normalized_path1 = path1:gsub("\\", "/")
  local normalized_path2 = path2:gsub("\\", "/")

  normalized_path1 = normalized_path1:lower()
  normalized_path2 = normalized_path2:lower()

  return normalized_path1 == normalized_path2
end


local function run_test(name, namespace, cs_project_path, cb)
  local log_file_name = string.format("%s.xml", namespace:gsub("%b()", ""))
  local normalized_path = vim.fs.normalize(cs_project_path)
  local directory_path = vim.fs.dirname(normalized_path)
  local relative_log_file_path = vim.fs.joinpath(directory_path, "TestResults", log_file_name)

  local command = string.format(
    "dotnet test --filter='%s' --nologo %s --logger='trx;logFileName=%s'",
    namespace:gsub("%b()", ""), cs_project_path, log_file_name)

  vim.fn.jobstart(
    command, {
      on_exit = function()
        require("easy-dotnet.test-runner.test-parser").xml_to_json(relative_log_file_path,
          ---@param unit_test_results TestCase
          function(unit_test_results)
            local result = unit_test_results[1]
            if result == nil then
              error(string.format("Status of %s was not present in xml file", name))
            end
            cb(result)
          end)
      end
    })
end



M.add_test_signs = function()
  vim.fn.sign_define("EasyDotnetTestSign", { text = "", texthl = "Question" })
  vim.fn.sign_define("EasyDotnetTestPassed", { text = "", texthl = "Question" })
  vim.fn.sign_define("EasyDotnetTestFailed", { text = "", texthl = "Question" })
  vim.fn.sign_define("EasyDotnetTestSkipped", { text = "", texthl = "Question" })
  vim.fn.sign_define("EasyDotnetTestError", { text = "??", texthl = "Question" })

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = "*.cs",
    callback = function()
      local is_test_file = false
      local bufnr = vim.api.nvim_get_current_buf()
      local curr_file = vim.api.nvim_buf_get_name(bufnr)
      for _, value in ipairs(require("easy-dotnet.test-runner.runner").test_register) do
        if compare_paths(value.file_path, curr_file) then
          is_test_file = true
          local line = value.line_number
          vim.fn.sign_place(0, "EasyDotnetTestSignGroup", "EasyDotnetTestSign", vim.api.nvim_get_current_buf(),
            { lnum = line - 1, priority = 20 })
        end
      end

      if is_test_file == true then
        vim.keymap.set("n", "<leader>d", function()
          local success, dap = pcall(function() return require("dap") end)
          if not success then
            vim.notify("nvim-dap not installed", vim.log.levels.ERROR)
            return
          end

          local bufnr = vim.api.nvim_get_current_buf()
          local curr_file = vim.api.nvim_buf_get_name(bufnr)
          local current_line = vim.api.nvim_win_get_cursor(0)[1]
          for _, value in ipairs(require("easy-dotnet.test-runner.runner").test_register) do
            if compare_paths(value.file_path, curr_file) and value.line_number - 1 == current_line then
              --TODO: Investigate why netcoredbg wont work without reopening the buffer????
              vim.cmd("bdelete")
              vim.cmd("edit " .. value.file_path)
              vim.api.nvim_win_set_cursor(0, { value.line_number and (value.line_number - 1) or 0, 0 })
              dap.toggle_breakpoint()

              local dap_configuration = {
                type = "coreclr",
                name = value.name,
                request = "attach",
                processId = function()
                  local project_path = value.cs_project_path
                  local res = require("easy-dotnet.debugger").start_debugging_test_project(project_path)
                  return res.process_id
                end
              }
              dap.run(dap_configuration)
              --return to avoid running multiple times in case of InlineData|ClassData
              return
            end
          end
          vim.notify("No tests found on this line")
        end, { silent = true, buffer = bufnr })

        vim.keymap.set("n", "<leader>r", function()
          local bufnr = vim.api.nvim_get_current_buf()
          local curr_file = vim.api.nvim_buf_get_name(bufnr)
          local current_line = vim.api.nvim_win_get_cursor(0)[1]
          for _, value in ipairs(require("easy-dotnet.test-runner.runner").test_register) do
            if compare_paths(value.file_path, curr_file) and value.line_number - 1 == current_line then
              local spinner = require("easy-dotnet.ui-modules.spinner").new()
              spinner:start_spinner("Running test")

              run_test(value.name, value.namespace, value.cs_project_path, function(result)
                if result.outcome == "Passed" then
                  spinner:stop_spinner("Passed")
                  vim.fn.sign_place(0, "EasyDotnetTestSignGroup", "EasyDotnetTestPassed", vim.api.nvim_get_current_buf(),
                    { lnum = current_line - 1, priority = 20 })
                elseif result.outcome == "Failed" then
                  spinner:stop_spinner("Failed", vim.log.levels.ERROR)
                  vim.fn.sign_place(0, "EasyDotnetTestSignGroup", "EasyDotnetTestFailed", vim.api.nvim_get_current_buf(),
                    { lnum = current_line - 1, priority = 20 })
                elseif result.outcome == "NotExecuted" then
                  spinner:stop_spinner("Skipped", vim.log.levels.WARN)
                  vim.fn.sign_place(0, "EasyDotnetTestSignGroup", "EasyDotnetTestSkipped", vim.api.nvim_get_current_buf(),
                    { lnum = current_line - 1, priority = 20 })
                else
                  spinner:stop_spinner("Failed to validate test result", vim.log.levels.WARN)
                  vim.fn.sign_place(0, "EasyDotnetTestSignGroup", "EasyDotnetTestError", vim.api.nvim_get_current_buf(),
                    { lnum = current_line - 1, priority = 20 })
                end
              end)
              return
            end
          end
          vim.notify("No tests found on this line")
        end, { silent = true, buffer = bufnr })
      end
    end
  })
end

return M
