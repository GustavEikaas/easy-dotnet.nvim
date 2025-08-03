local M = {}

local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local ns = require("easy-dotnet.constants").ns_id
local hi = require("easy-dotnet.constants").highlights.EasyDotnetDebuggerVirtualVariable

local function redraw(cache, bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local sorted = {}
  for _, value in pairs(cache) do
    if value.roslyn and value.netcoredbg then table.insert(sorted, value) end
  end

  table.sort(sorted, function(a, b)
    if a.roslyn.lineStart == b.roslyn.lineStart then
      return a.roslyn.columnStart < b.roslyn.columnStart
    else
      return a.roslyn.lineStart < b.roslyn.lineStart
    end
  end)

  local grouped = {}
  for _, val in ipairs(sorted) do
    local line = val.roslyn.lineStart
    grouped[line] = grouped[line] or {}
    table.insert(grouped[line], " " .. (val.resolved and val.resolved.pretty or val.netcoredbg.value .. " (loading)"))
    grouped[line].hi = val.resolved and val.resolved.hi or hi
  end

  for line, texts in pairs(grouped) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
      virt_text = { { table.concat(texts, "  "), texts.hi } },
      virt_text_pos = "eol",
    })
  end
end

---@param type "roslyn" | "netcoredbg" | "frame"
local function append_redraw(virt, payload, type, bufnr, identifier)
  local curr = virt[identifier]
  curr = curr or {}
  curr[type] = payload
  virt[identifier] = curr

  redraw(virt, bufnr)
end

local function open_or_switch_to_file(filepath)
  local normalized_path = vim.fn.fnamemodify(filepath, ":p")

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buf_path = vim.api.nvim_buf_get_name(bufnr)
      if vim.fn.fnamemodify(buf_path, ":p") == normalized_path then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == bufnr then
            vim.api.nvim_set_current_win(win)
            return bufnr
          end
        end
        vim.api.nvim_set_current_buf(bufnr)
        return bufnr
      end
    end
  end

  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  return vim.api.nvim_get_current_buf()
end

---@param frame dap.StackFrame
---@param session dap.Session
---@param bufnr integer
---@param cache table
local function query_stack_frame(frame, session, bufnr, cache)
  local orig_line = frame.line
  local file = frame.source.path
  if not file then return end
  client:initialize(function()
    client:roslyn_scope_variables(file, frame.line, function(variable_locations)
      for _, value in ipairs(variable_locations) do
        append_redraw(cache, value, "roslyn", bufnr, value.identifier)
      end
    end)
  end)

  local frame_id = frame.id

  session:request("scopes", { frameId = frame_id }, function(err2, response2)
    if err2 then return end

    for _, scope in ipairs(response2.scopes) do
      local variables_reference = scope.variablesReference

      session:request("variables", { variablesReference = variables_reference }, function(err3, response3)
        if err3 then return end
        for _, value in ipairs(response3.variables) do
          append_redraw(cache, { frame_id = frame_id }, "frame", bufnr, value.evaluateName)
          append_redraw(cache, value, "netcoredbg", bufnr, value.evaluateName)
          if value.evaluateName == "$exception" then append_redraw(cache, { lineStart = orig_line }, "roslyn", bufnr, value.evaluateName) end

          require("easy-dotnet.netcoredbg").resolve_by_var_name(frame_id, value.evaluateName, function(res)
            cache[value.evaluateName].resolved = { pretty = res.formatted_value, hi = res.hi }
            redraw(cache, bufnr)
          end)
        end
      end)
    end
  end)
end

function M.register_listener()
  local keymap_backup = {}

  require("dap").listeners.after.event_stopped["easy-dotnet-scopes"] = function(session, body)
    ---@diagnostic disable-next-line: undefined-field
    if session.adapter.command ~= "netcoredbg" then return end

    session:request("stackTrace", { threadId = body.threadId }, function(err1, response1)
      if err1 then return end

      local frame = response1.stackFrames[1]
      if not frame then return end

      local file = frame.source.path
      local bufnr = open_or_switch_to_file(file)
      if not file then error("StackFrame file cannot be nil") end

      local cache = {}

      local existing = vim.fn.maparg("T", "n", false, true)
      if existing and existing.buffer == bufnr then
        keymap_backup[bufnr] = existing
      elseif vim.api.nvim_buf_is_loaded(bufnr) then
        keymap_backup[bufnr] = false
      end

      vim.keymap.set("n", "T", function()
        local current_line = vim.api.nvim_win_get_cursor(0)[1]
        local matches = {}
        for key, value in pairs(cache) do
          if value.netcoredbg and value.roslyn and value.roslyn.lineStart == current_line then table.insert(matches, { display = key, value = value }) end
        end
        if #matches == 0 then
          return
        else
          require("easy-dotnet.picker").picker(nil, matches, function(val)
            require("easy-dotnet.netcoredbg").resolve_by_var_name(
              val.value.frame.frame_id,
              val.display,
              function(res) require("easy-dotnet.netcoredbg.debugger-float").show(res.value, val.value.frame.frame_id) end
            )
          end, "Pick variable", true, true)
        end
      end, { silent = true, buffer = bufnr })

      query_stack_frame(frame, session, bufnr, cache)

      local frame2 = response1.stackFrames[2]
      if frame2 and frame2.source and frame2.source.path == file then query_stack_frame(frame2, session, bufnr, cache) end
    end)
  end

  require("dap").listeners.after.event_exited["easy-dotnet-cleanup"] = function()
    require("easy-dotnet.netcoredbg.debugger-float").close()
    require("easy-dotnet.netcoredbg").variable_cache = {}
    require("easy-dotnet.netcoredbg").pending_callbacks = {}
    for bufnr, original in pairs(keymap_backup) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        if original == false then
          pcall(vim.keymap.del, "n", "T", { buffer = bufnr })
        else
          if original.rhs then
            vim.keymap.set("n", "T", original.rhs, {
              noremap = original.noremap == 1,
              expr = original.expr == 1,
              silent = original.silent == 1,
              buffer = bufnr,
            })
          end
        end
      end
    end

    keymap_backup = {}
  end
end

return M
