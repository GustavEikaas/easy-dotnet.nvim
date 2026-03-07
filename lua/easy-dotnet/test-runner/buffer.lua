local M = {}

local state = require("easy-dotnet.test-runner.state")
local logger = require("easy-dotnet.logger")

local ns_signs = vim.api.nvim_create_namespace("easy_dotnet_test_signs")
local extmark_ids = {}
local registered_bufs = {}

local function norm(path)
  if not path then return nil end
  return vim.fs.normalize(path)
end

local function get_icons()
  local ok, opts = pcall(function() return require("easy-dotnet.options").get_option("test_runner").icons end)
  return ok and opts or {}
end

local ns_flash = vim.api.nvim_create_namespace("easy_dotnet_test_flash")

local function flash_method(bufnr, sig_line, end_line, hl_group, duration)
  if sig_line == nil then return end
  local fin = end_line or sig_line

  vim.api.nvim_buf_clear_namespace(bufnr, ns_flash, 0, -1)

  for line = sig_line, fin do
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
    if
      norm(node.filePath) == npath
      and node.type
      and (node.type.type == "TestMethod" or node.type.type == "Subcase" or node.type.type == "TheoryGroup" or node.type.type == "TestClass")
      and node.signatureLine ~= nil
    then
      table.insert(result, node)
    end
  end)
  return result
end

local function group_nodes_by_line(filepath)
  local groups = {}
  for _, node in ipairs(nodes_for_file(filepath)) do
    local sig = node.signatureLine
    if not groups[sig] then groups[sig] = { nodes = {}, endLine = node.endLine or sig } end
    table.insert(groups[sig].nodes, node)
    if node.endLine and node.endLine > groups[sig].endLine then groups[sig].endLine = node.endLine end
  end

  -- Prefer TheoryGroup over individual Subcase nodes at the same line
  for sig, group in pairs(groups) do
    for _, node in ipairs(group.nodes) do
      if node.type and node.type.type == "TheoryGroup" then
        groups[sig].nodes = { node }
        break
      end
    end
  end

  return groups
end

local function aggregate_status(nodes)
  local order = { Running = 4, Debugging = 4, Failed = 3, Skipped = 2, Passed = 1 }
  local best = nil
  local best_rank = 0
  for _, node in ipairs(nodes) do
    local stype = node.status and node.status.type or nil
    local norm_type = stype and (stype:sub(1, 1):upper() .. stype:sub(2)) or nil
    local rank = (norm_type and order[norm_type]) or 0
    if rank > best_rank then
      best_rank = rank
      best = norm_type
    end
  end
  return best
end

local function node_at_line(filepath, line)
  local npath = norm(filepath)
  local groups = group_nodes_by_line(filepath)

  -- Pick the narrowest matching range so a method sign always wins over a class sign
  local best_nodes, best_sig, best_fin = nil, nil, nil
  for sig_line, group in pairs(groups) do
    local fin = group.endLine or sig_line
    if line >= sig_line and line <= fin then
      if best_fin == nil or (fin - sig_line) < (best_fin - best_sig) then
        best_nodes, best_sig, best_fin = group.nodes, sig_line, fin
      end
    end
  end
  if best_nodes then return best_nodes, best_sig, best_fin end

  -- Fallback: cursor is somewhere inside a class body between method groups
  local class_match, class_sig, class_fin = nil, nil, nil
  state.traverse_all(function(node)
    if class_match then return end
    if norm(node.filePath) == npath and node.type and node.type.type == "TestClass" then
      local children = state.children(node.id)
      if #children == 0 then return end
      local first_line, last_line = math.huge, 0
      for _, child in ipairs(children) do
        if child.signatureLine then first_line = math.min(first_line, child.signatureLine) end
        if child.endLine then last_line = math.max(last_line, child.endLine) end
      end
      if line >= first_line and line <= last_line then
        class_match = node
        class_sig = first_line
        class_fin = last_line
      end
    end
  end)
  return class_match and { class_match } or nil, class_sig, class_fin
end

local sign_text_for = {
  Passed = function(icons) return (icons.passed or "") .. " " end,
  Failed = function(icons) return (icons.failed or "") .. " " end,
  Skipped = function(icons) return (icons.skipped or "") .. " " end,
  Running = function(icons) return (icons.reload or "") .. " " end,
  Debugging = function(icons) return (icons.reload or "") .. " " end,
}
local sign_hl_for = {
  Passed = "EasyDotnetTestRunnerPassed",
  Failed = "EasyDotnetTestRunnerFailed",
  Skipped = "EasyDotnetTestRunnerSkipped",
  Running = "EasyDotnetTestRunnerRunning",
  Debugging = "EasyDotnetTestRunnerRunning",
}

local function resolve_sign(nodes)
  local icons = get_icons()
  local stype = aggregate_status(nodes)
  local text = stype and sign_text_for[stype] and sign_text_for[stype](icons) or (icons.test or "󰙨") .. " "
  local hl = sign_hl_for[stype] or "EasyDotnetTestRunnerTest"
  return text, hl
end

local function apply_sign_for_group(bufnr, sig_line, group, filepath)
  local text, hl = resolve_sign(group.nodes)

  local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_signs, sig_line, 0, {
    sign_text = text,
    sign_hl_group = hl,
    priority = 100,
  })

  if ok then
    if not extmark_ids[filepath] then extmark_ids[filepath] = {} end
    extmark_ids[filepath]["line:" .. sig_line] = id
  end
end

function M.apply_signs(filepath)
  local bufnr = vim.fn.bufnr(filepath)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, ns_signs, 0, -1)
  extmark_ids[filepath] = {}

  local groups = group_nodes_by_line(filepath)
  for sig_line, group in pairs(groups) do
    apply_sign_for_group(bufnr, sig_line, group, filepath)
  end
end

function M.update_sign(node)
  if not node.filePath or node.signatureLine == nil then return end
  local bufnr = vim.fn.bufnr(node.filePath)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then return end

  local groups = group_nodes_by_line(node.filePath)
  local group = groups[node.signatureLine]
  if not group then
    M.apply_signs(node.filePath)
    return
  end

  local file_marks = extmark_ids[node.filePath]
  local existing_id = file_marks and file_marks["line:" .. node.signatureLine]
  local text, hl = resolve_sign(group.nodes)

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

function M.register_buf_keymaps(bufnr, client)
  local km = require("easy-dotnet.options").get_option("test_runner").mappings

  local function map(lhs, desc, fn) vim.keymap.set("n", lhs, fn, { silent = true, buffer = bufnr, desc = desc }) end

  local function current_nodes()
    local filepath = norm(vim.api.nvim_buf_get_name(bufnr))
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local nodes, sig_line, end_line = node_at_line(filepath, line)
    if not nodes then logger.warn(string.format("No test at line %d", line + 1)) end
    return nodes, sig_line, end_line
  end

  map(km.run_test_from_buffer and km.run_test_from_buffer.lhs or "<leader>r", "Run test", function()
    local nodes, sig_line, end_line = current_nodes()
    if not nodes then return end
    flash_method(bufnr, sig_line, end_line, "CursorLine", 300)
    for _, node in ipairs(nodes) do
      client.testrunner:run(node.id, function(result)
        if not result or not result.success then logger.error("Run failed") end
      end)
    end
  end)

  map(km.debug_test_from_buffer and km.debug_test_from_buffer.lhs or "<leader>d", "Debug test", function()
    local nodes, sig_line, end_line = current_nodes()
    if not nodes then return end
    local node = nodes[1]
    if node.type and node.type.type == "TestClass" then
      logger.warn("Debug not supported for entire class")
      return
    end
    flash_method(bufnr, sig_line, end_line, "CursorLine", 300)
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
    local nodes = current_nodes()
    if not nodes then return end
    local node = nodes[1]
    if node.type and node.type.type == "TestClass" then
      logger.warn("Peek not available for class")
      return
    end
    client.testrunner:get_results(node.id, function(result)
      if not result or not result.found then
        logger.warn("No results yet — run the test first")
        return
      end
      require("easy-dotnet.test-runner.results-float").open(node, result, { source = "buffer" })
    end)
  end)
end

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

    local version = 0

    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = filepath,
      callback = function(ev)
        version = version + 1
        local v = version

        local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false)
        local content = table.concat(lines, "\n")

        client.testrunner:sync_file(filepath, content, v, function(result)
          if not result then return end
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
    local stype = node.status and node.status.type or nil
    if not stype then return end
    local stype_norm = stype:sub(1, 1):upper() .. stype:sub(2)

    local hl = sign_hl_for[stype_norm]
    if not hl then return end

    local bufnr = vim.fn.bufnr(node.filePath or "")
    if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then return end

    flash_method(bufnr, node.signatureLine, node.endLine, hl, 500)
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
