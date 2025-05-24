local tests = require("easy-dotnet.integration-tests.tests")
local window = require("easy-dotnet.test-runner.window")

local M = {}

-- Highlight groups setup (you can put this in your plugin init too)
vim.api.nvim_set_hl(0, "TestPass", { fg = "green" })
vim.api.nvim_set_hl(0, "TestFail", { fg = "red" })

M.show_dashboard = function()
  local win = window.new_float():pos_center():create()
  local buf = win.buf

  local test_names = {}
  for name, _ in pairs(tests) do
    table.insert(test_names, name)
  end
  table.sort(test_names)
  win:write_buf(test_names)
  -- vim.api.nvim_buf_set_lines(buf, 0, -1, false, test_names)

  -- Save mapping of test name to line number
  M.test_line_map = {}
  for i, name in ipairs(test_names) do
    M.test_line_map[name] = i - 1 -- zero-indexed
  end

  vim.keymap.set("n", "<leader>r", function() M.run_test_under_cursor() end, { buffer = buf, noremap = true, silent = true })

  M.dashboard_buf = buf
end

M.run_test_under_cursor = function()
  local buf = M.dashboard_buf
  local line = vim.api.nvim_get_current_line()
  local test = tests[line]

  local ns = vim.api.nvim_create_namespace("test_status")
  local line_num = M.test_line_map[line]
  vim.api.nvim_buf_clear_namespace(buf, ns, line_num, line_num + 1)

  vim.api.nvim_buf_set_extmark(buf, ns, line_num, 0, {
    virt_text = { { " " .. "<Running>", "TestPass" } },
    virt_text_pos = "eol",
  })

  if test and type(test.handle) == "function" then
    vim.schedule(function()
      local ok = test.handle()
      local status = ok and "[PASS]" or "[FAIL]"
      local hl = ok and "TestPass" or "TestFail"

      vim.api.nvim_buf_clear_namespace(buf, ns, line_num, line_num + 1)
      vim.api.nvim_buf_set_extmark(buf, ns, line_num, 0, {
        virt_text = { { " " .. status, hl } },
        virt_text_pos = "eol",
      })

      if not ok then vim.notify("Test '" .. line .. "' failed", vim.log.levels.ERROR) end
    end)
  else
    vim.notify("No test found for: " .. line, vim.log.levels.WARN)
  end
end

return M
