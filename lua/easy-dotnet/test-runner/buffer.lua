local M = {}

local state = require("easy-dotnet.test-runner.state")
local logger = require("easy-dotnet.logger")

local ns_signs = vim.api.nvim_create_namespace("easy_dotnet_test_signs")
local extmark_ids = {} -- filepath → { nodeId → extmark_id }
local registered_bufs = {} -- bufnr/filepath → true

local function norm(path)
  if not path then return nil end
  return vim.fs.normalize(path)
end

local function get_icons()
  local ok, opts = pcall(function() return require("easy-dotnet.options").get_option("test_runner").icons end)
  return ok and opts or {}
end

local function get_sign(node)
  local icons = get_icons()
  local raw = node.status and node.status.type or nil
  local stype = raw and (raw:sub(1, 1):upper() .. raw:sub(2)) or nil

  local text = ({
    Passed = (icons.passed or "") .. " ",
    Failed = (icons.failed or "") .. " ",
    Skipped = (icons.skipped or "") .. " ",
    Running = (icons.reload or "") .. " ",
    Debugging = (icons.reload or "") .. " ",
  })[stype] or (icons.test or "󰙨") .. " "

  local hl = ({
    Passed = "EasyDotnetTestRunnerPassed",
    Failed = "EasyDotnetTestRunnerFailed",
    Skipped = "EasyDotnetTestRunnerSkipped",
    Running = "EasyDotnetTestRunnerRunning",
    Debugging = "EasyDotnetTestRunnerRunning",
  })[stype] or "EasyDotnetTestRunnerTest"

  return text, hl
end

local ns_flash = vim.api.nvim_create_namespace("easy_dotnet_test_flash")

local function flash_method(bufnr, node, hl_group, duration)
  if not node.signatureLine then return end
  local fin = node.endLine or node.signatureLine

  vim.api.nvim_buf_clear_namespace(bufnr, ns_flash, 0, -1)

  for line = node.signatureLine, fin do
    vim.api.nvim_buf_set_extmark(bufnr, ns_flash, line, 0, {
      line_hl_group = hl_group or "CursorLine",
      priority = 200,
    })
  end

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_clear_namespace(bufnr, ns_flash, 0, -1) end
  end, duration or 300)
end

local function nodes_for_file(filepath)
  local result = {}
  local npath = norm(filepath)
  state.traverse_all(function(node)
    if norm(node.filePath) == npath and node.type and (node.type.type == "TestMethod" or node.type.type == "Subcase") and node.signatureLine ~= nil then table.insert(result, node) end
  end)
  return result
end

local function node_at_line(filepath, line)
  local npath = norm(filepath)

  for _, node in ipairs(nodes_for_file(filepath)) do
    local sig = node.signatureLine
    local fin = node.endLine or sig
    if sig and line >= sig and line <= fin then return node end
  end

  local class_match = nil
  state.traverse_all(function(node)
    if class_match then return end
    if norm(node.filePath) == npath and node.type and node.type.type == "TestClass" then
      local children = state.children(node.id)
      if #children == 0 then return end
      local first_line = math.huge
      local last_line = 0
      for _, child in ipairs(children) do
        if child.signatureLine then first_line = math.min(first_line, child.signatureLine) end
        if child.endLine then last_line = math.max(last_line, child.endLine) end
      end
      if line >= first_line and line <= last_line then class_match = node end
    end
  end)
  return class_match
end

-- ---------------------------------------------------------------------------
-- Extmarks
-- ---------------------------------------------------------------------------

function M.apply_signs(filepath)
  local bufnr = vim.fn.bufnr(filepath)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, ns_signs, 0, -1)
  extmark_ids[filepath] = {}

  for _, node in ipairs(nodes_for_file(filepath)) do
    local text, hl = get_sign(node)
    local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_signs, node.signatureLine, 0, {
      sign_text = text,
      sign_hl_group = hl,
      priority = 100,
    })
    if ok then extmark_ids[filepath][node.id] = id end
  end
end

function M.update_sign(node)
  if not node.filePath or node.signatureLine == nil then return end
  local bufnr = vim.fn.bufnr(node.filePath)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  local file_marks = extmark_ids[node.filePath]
  local existing_id = file_marks and file_marks[node.id]
  local text, hl = get_sign(node)

  if existing_id then
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_signs, node.signatureLine, 0, {
      id = existing_id,
      sign_text = text,
      sign_hl_group = hl,
      priority = 100,
    })
  else
    M.apply_signs(node.filePath)
  end
end

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------

function M.register_buf_keymaps(bufnr, client)
  local km = require("easy-dotnet.options").get_option("test_runner").mappings

  local function map(lhs, desc, fn) vim.keymap.set("n", lhs, fn, { silent = true, buffer = bufnr, desc = desc }) end

  local function current_node()
    local filepath = norm(vim.api.nvim_buf_get_name(bufnr))
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
    local node = node_at_line(filepath, line)
    if not node then logger.warn(string.format("No test at line %d", line + 1)) end
    return node
  end

  map(km.run_test_from_buffer and km.run_test_from_buffer.lhs or "<leader>r", "Run test", function()
    local node = current_node()
    if not node then return end
    flash_method(bufnr, node)
    client.testrunner:run(node.id, function(result)
      if not result or not result.success then logger.error("Run failed") end
    end)
  end)

  map(km.debug_test_from_buffer and km.debug_test_from_buffer.lhs or "<leader>d", "Debug test", function()
    local node = current_node()
    if not node then return end
    if node.type and node.type.type == "TestClass" then
      logger.warn("Debug not supported for entire class")
      return
    end
    client.testrunner:debug(node.id, function() end)
  end)

  map(km.run_all_tests_from_buffer and km.run_all_tests_from_buffer.lhs or "<leader>t", "Run all tests in file", function()
    local filepath = norm(vim.api.nvim_buf_get_name(bufnr))
    local seen, project_ids = {}, {}
    state.traverse_all(function(node)
      if norm(node.filePath) == filepath and node.projectId and not seen[node.projectId] then
        seen[node.projectId] = true
        table.insert(project_ids, node.projectId)
      end
    end)
    if #project_ids == 0 then
      logger.warn("No tests found in this file")
      return
    end
    for _, pid in ipairs(project_ids) do
      client.testrunner:run(pid, function() end)
    end
  end)

  map(km.peek_stack_trace_from_buffer and km.peek_stack_trace_from_buffer.lhs or "<leader>p", "Peek test output", function()
    local node = current_node()
    if not node then return end
    if node.type and node.type.type == "TestClass" then
      logger.warn("Peek not available for class")
      return
    end
    client.testrunner:get_results(node.id, function(result)
      if not result or not result.found then
        logger.warn("No results yet — run the test first")
        return
      end
      require("easy-dotnet.test-runner.results-float").open(node, result)
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function M.attach(filepath, client)
  if not filepath then return end

  local bufnr = vim.fn.bufnr(filepath)
  if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
    M.apply_signs(filepath)
    if not registered_bufs[bufnr] then
      M.register_buf_keymaps(bufnr, client)
      registered_bufs[bufnr] = true
    end
  end

  if not registered_bufs[filepath] then
    registered_bufs[filepath] = true

    vim.api.nvim_create_autocmd("BufReadPost", {
      pattern = filepath,
      callback = function(ev)
        vim.schedule(function()
          M.apply_signs(filepath)
          if not registered_bufs[ev.buf] then
            M.register_buf_keymaps(ev.buf, client)
            registered_bufs[ev.buf] = true
          end
        end)
      end,
    })

    -- Per-file monotonic version counter — echoed back by the server so we
    -- can discard responses that arrive out of order (save twice quickly).
    local version = 0

    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = filepath,
      callback = function(ev)
        version = version + 1
        local v = version -- capture for closure

        local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false)
        local content = table.concat(lines, "\n")

        client.testrunner:sync_file(filepath, content, v, function(result)
          if not result then return end
          -- Discard if a newer save has been sent since this one
          if result.version < version then return end

          local any_changed = false
          for _, update in ipairs(result.updates or {}) do
            state.update_line_numbers(update)
            any_changed = true
          end

          if any_changed then M.apply_signs(filepath) end
        end)
      end,
    })
  end
end

function M.on_status_update(node)
  vim.schedule(function()
    M.update_sign(node)

    -- Flash the method group when a terminal result arrives
    local stype = node.status and node.status.type or nil
    if not stype then return end
    local stype_norm = stype:sub(1, 1):upper() .. stype:sub(2)

    local hl = ({
      Passed = "EasyDotnetTestRunnerPassed",
      Failed = "EasyDotnetTestRunnerFailed",
      Skipped = "EasyDotnetTestRunnerSkipped",
    })[stype_norm]

    if not hl then return end -- Running/Debugging — no result flash

    local bufnr = vim.fn.bufnr(node.filePath or "")
    if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then return end

    flash_method(bufnr, node, hl, 500)
  end)
end

function M.clear_all()
  for filepath in pairs(extmark_ids) do
    local bufnr = vim.fn.bufnr(filepath)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_clear_namespace(bufnr, ns_signs, 0, -1) end
  end
  extmark_ids = {}
  registered_bufs = {}
end

return M
