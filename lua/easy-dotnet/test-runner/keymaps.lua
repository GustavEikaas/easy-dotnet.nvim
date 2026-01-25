local M = {}

---@param buf integer Buffer ID
---@param user_keys table Configuration table from options
---@param actions table The Actions table from render.lua
---@param resolver fun(line: number): TestNode Function to resolve cursor line to Node
M.attach = function(buf, user_keys, actions, resolver)
  user_keys = user_keys or {}

  local function map(key_name, callback)
    local def = user_keys[key_name]
    if not def then return end

    vim.keymap.set("n", def.lhs, function()
      local cursor = vim.api.nvim_win_get_cursor(0)[1]
      local node = resolver(cursor)

      if node then
        callback(node)
      else
        callback(nil)
      end
    end, { buffer = buf, desc = def.desc, noremap = true, silent = true })
  end

  map("run", actions.run_node)
  map("debug_test", actions.debug_node)
  map("run_all", function() actions.run_node({ id = "root" }) end)

  -- Navigation
  map("go_to_file", actions.go_to_file)
  map("peek_stacktrace", actions.peek_stacktrace)

  -- Tree Manipulation
  map("expand_node", actions.expand_node)
  map("expand", actions.expand_node) -- Alias
  map("filter_failed_tests", actions.toggle_filter)

  -- Global
  map("refresh_testrunner", function()
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client.test:test_runner_discover() -- Trigger server refresh
  end)

  map("close", function() require("easy-dotnet.test-runner.render").toggle() end)
end

return M
