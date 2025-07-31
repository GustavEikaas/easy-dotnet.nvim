local M = {}

local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local ns = require("easy-dotnet.constants").ns_id

local function redraw(cache, bufnr)
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
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local curr = virt[identifier]
  curr = curr or {}
  curr[type] = payload
  virt[identifier] = curr

  redraw(virt, bufnr)
end

function M.register_listener()
  local curr_frame = nil
  require("dap").listeners.after.event_stopped["easy-dotnet-scopes"] = function(session, body)
    ---@diagnostic disable-next-line: undefined-field
    if session.adapter.command ~= "netcoredbg" then return end

    local bufnr = vim.api.nvim_get_current_buf()
    local cache = {}

    vim.keymap.set("n", "T", function()
      --TODO: clear on dap exit
      local current_line = vim.api.nvim_win_get_cursor(0)[1]
      for key, value in pairs(cache) do
        if value.roslyn.lineStart == current_line and curr_frame ~= nil then
          require("easy-dotnet.netcoredbg").resolve_by_var_name(curr_frame.id, key, function(res) require("easy-dotnet.netcoredbg.debugger-float").show(res.vars, curr_frame.id) end)
        end
      end
    end, { silent = true, buffer = bufnr })

    session:request("stackTrace", { threadId = body.threadId }, function(err1, response1)
      if err1 then return end

      local frame = response1.stackFrames[1]
      if not frame then return end
      curr_frame = frame

      local file = frame.source.path
      if not file then error("StackFrame file cannot be nil") end

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
end

return M
