local M = {}

local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local ns = require("easy-dotnet.constants").ns_id

local function redraw(cache, bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, value in pairs(cache) do
    if value.roslyn and value.netcoredbg then
      vim.api.nvim_buf_set_extmark(bufnr, ns, value.roslyn.lineStart - 1, 0, {
        virt_text = { { " " .. (value.resolved and value.resolved.pretty or value.netcoredbg.value .. " (loading)"), "Question" } },
        virt_text_pos = "eol",
      })
    end
  end
end

---@param type "roslyn" | "netcoredbg"
local function append_redraw(virt, payload, type, bufnr, identifier)
  local curr = virt[identifier]
  curr = curr or {}
  curr[type] = payload
  virt[identifier] = curr

  redraw(virt, bufnr)
end

local function open_or_switch_to_file(filepath)
  -- Normalize path
  local normalized_path = vim.fn.fnamemodify(filepath, ":p")

  -- Check if buffer is already loaded
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buf_path = vim.api.nvim_buf_get_name(bufnr)
      if vim.fn.fnamemodify(buf_path, ":p") == normalized_path then
        -- Switch to the buffer's window if it's visible
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == bufnr then
            vim.api.nvim_set_current_win(win)
            return bufnr
          end
        end
        -- Otherwise just switch to the buffer
        vim.api.nvim_set_current_buf(bufnr)
        return bufnr
      end
    end
  end

  -- Buffer not found, open file
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  return vim.api.nvim_get_current_buf()
end

function M.register_listener()
  local keymap_backup = {}
  local curr_frame = nil

  require("dap").listeners.after.event_stopped["easy-dotnet-scopes"] = function(session, body)
    ---@diagnostic disable-next-line: undefined-field
    if session.adapter.command ~= "netcoredbg" then return end
    local orig_line = vim.api.nvim_win_get_cursor(0)[1]

    session:request("stackTrace", { threadId = body.threadId }, function(err1, response1)
      if err1 then return end

      local frame = response1.stackFrames[1]
      if not frame then return end
      orig_line = frame.line
      curr_frame = frame

      local file = frame.source.path
      local bufnr = open_or_switch_to_file(file)
      if not file then error("StackFrame file cannot be nil") end

      local existing = vim.fn.maparg("T", "n", false, true)
      if existing and existing.buffer == bufnr then
        keymap_backup[bufnr] = existing
      elseif vim.api.nvim_buf_is_loaded(bufnr) then
        keymap_backup[bufnr] = false
      end

      local cache = {}

      vim.keymap.set("n", "T", function()
        --TODO: clear on dap exit
        local current_line = vim.api.nvim_win_get_cursor(0)[1]
        for key, value in pairs(cache) do
          if value.roslyn and value.roslyn.lineStart == current_line and curr_frame ~= nil then
            require("easy-dotnet.netcoredbg").resolve_by_var_name(curr_frame.id, key, function(res) require("easy-dotnet.netcoredbg.debugger-float").show(res.value, curr_frame.id) end)
          end
        end
      end, { silent = true, buffer = bufnr })

      client:initialize(function()
        client:roslyn_scope_variables(file, "", frame.line, function(variable_locations)
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
              append_redraw(cache, value, "netcoredbg", bufnr, value.evaluateName)
              if value.evaluateName == "$exception" then append_redraw(cache, { lineStart = orig_line }, "roslyn", bufnr, value.evaluateName) end

              require("easy-dotnet.netcoredbg").resolve_by_var_name(frame_id, value.evaluateName, function(res)
                cache[value.evaluateName].resolved = { pretty = res.formatted_value }
                redraw(cache, bufnr)
              end)
            end
          end)
        end
      end)
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
