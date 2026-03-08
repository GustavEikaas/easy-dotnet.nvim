local state = require("easy-dotnet.test-runner.state")
local render = require("easy-dotnet.test-runner.render")
local logger = require("easy-dotnet.logger")

local M = {}

--- Register all keymaps on the test runner buffer.
---@param buf integer
---@param client easy-dotnet.RPC.Client.Dotnet  the rpc client (has .testrunner)
---@param options table  easy-dotnet options
function M.register(buf, client, options)
  local km = options.mappings or {}

  local function map(lhs, desc, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc, noremap = true, silent = true }) end

  local function with_node(fn)
    return function()
      local node = render.node_at_cursor()
      if not node then return end
      fn(node)
    end
  end

  local function cancel()
    state.cancel()
    render.refresh()
  end

  map(
    km.expand and km.expand.lhs or "o",
    "Toggle expand",
    with_node(function(node)
      node.expanded = not node.expanded
      render.refresh()
    end)
  )

  map(
    km.expand_node and km.expand_node.lhs or "O",
    "Expand all children",
    with_node(function(node)
      state.traverse_all(function(n, _)
        local id = n.id
        local cur = id
        while cur do
          if cur == node.id then
            n.expanded = true
            break
          end
          cur = state.nodes[cur] and state.nodes[cur].parentId or nil
        end
      end)
      render.refresh()
    end)
  )

  map(
    km.collapse_all and km.collapse_all.lhs or "W",
    "Collapse all children",
    with_node(function(node)
      state.traverse_all(function(n, _)
        local cur = n.id
        while cur do
          if cur == node.id then
            n.expanded = false
            break
          end
          cur = state.nodes[cur] and state.nodes[cur].parentId or nil
        end
      end)
      render.refresh()
    end)
  )

  map(
    km.run and km.run.lhs or "r",
    "Run tests",
    with_node(function(node)
      if not state.has_action(node, "Run") then
        logger.warn("Run not available for this node")
        return
      end
      state.active_handle = client.testrunner:run(node.id)
    end)
  )

  map(
    km.debug_test and km.debug_test.lhs or "d",
    "Debug tests",
    with_node(function(node)
      if not state.has_action(node, "Debug") then
        logger.warn("Debug not available for this node")
        return
      end
      render.hide()
      state.active_handle = client.testrunner:debug(node.id)
    end)
  )

  map(km.run_all and km.run_all.lhs or "R", "Run all tests", function()
    if not state.root_id then return end
    local root = state.nodes[state.root_id]
    if root and state.has_action(root, "Run") then state.active_handle = client.testrunner:run(state.root_id) end
  end)

  map(
    km.refresh_testrunner and km.refresh_testrunner.lhs or "i",
    "Invalidate node",
    with_node(function(node)
      if not state.has_action(node, "Invalidate") then
        logger.warn("Invalidate not available for this node")
        return
      end
      state.active_handle = client.testrunner:invalidate(node.id)
    end)
  )

  map("<C-c>", "Cancel active operation", cancel)

  map(
    km.go_to_file and km.go_to_file.lhs or "gf",
    "Go to source",
    with_node(function(node)
      if not state.has_action(node, "GoToSource") then
        logger.warn("No source location for this node")
        return
      end
      if not node.filePath then return end
      render.hide()
      vim.cmd("edit " .. vim.fn.fnameescape(node.filePath))
      if node.bodyStartLine then vim.api.nvim_win_set_cursor(0, { node.bodyStartLine + 1, 0 }) end
    end)
  )

  map(
    km.peek_stacktrace and km.peek_stacktrace.lhs or "p",
    "Peek results",
    with_node(function(node)
      if not state.has_action(node, "PeekResults") then
        logger.warn("No results available for this node")
        return
      end
      client.testrunner:get_results(node.id, function(result)
        if not result or not result.found then
          logger.warn("No results found for this node")
          return
        end
        vim.schedule(function() require("easy-dotnet.test-runner.results-float").open(node, result) end)
      end)
    end)
  )

  map(
    km.get_build_errors and km.get_build_errors.lhs or "e",
    "Show build errors",
    with_node(function(node)
      if not state.has_action(node, "GetBuildErrors") then
        logger.warn("No build errors available for this node")
        return
      end
      client.testrunner:get_build_errors(node.id)
    end)
  )

  map(km.close and km.close.lhs or "q", "Close test runner", function() render.hide() end)
  map("<Esc>", "Close test runner", function() render.hide() end)
end

return M
