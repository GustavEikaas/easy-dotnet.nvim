local View = require("easy-dotnet.test-runner.view")
local Header = require("easy-dotnet.test-runner.header")
local Tree = require("easy-dotnet.test-runner.v2")
local Constants = require("easy-dotnet.constants")
local WindowModule = require("easy-dotnet.test-runner.window")
local Client = require("easy-dotnet.rpc.rpc").global_rpc_client

local M = {}

-- --- STATE ---
local State = {
  buf = nil,
  win = nil,
  options = {},
  active_node_id = nil,
  header_status = nil,
  filter_failed_only = false,
}

-- --- ACTIONS (RPC Wrappers) ---
local Actions = {
  run_node = function(node)
    Client:initialize(function()
      -- If the node is a container (Folder/Project), the server should handle recursion
      -- based on the ID passed.
      Client.test:run_tests({ node.id })
    end)
  end,

  debug_node = function(node)
    Client:initialize(function()
      Client.test:debug_test(node.id, function(dap_config)
        if dap_config then
          local ok, dap = pcall(require, "dap")
          if ok then
            dap.run(dap_config)
            -- Optional: Close runner window when debugging starts
            -- M.toggle()
          else
            vim.notify("nvim-dap is not installed.", vim.log.levels.ERROR)
          end
        else
          vim.notify("Server could not generate debug config.", vim.log.levels.WARN)
        end
      end)
    end)
  end,

  go_to_file = function(node)
    Client:initialize(function()
      Client.test:get_source_location(node.id, function(loc)
        if loc and loc.file then
          -- Switch to the file buffer
          vim.cmd("edit " .. loc.file)
          if loc.line then
            vim.api.nvim_win_set_cursor(0, { loc.line, 0 })
            -- Flash the line
            local ns = Constants.ns_id
            vim.api.nvim_buf_add_highlight(0, ns, "Visual", loc.line - 1, 0, -1)
            vim.defer_fn(function() vim.api.nvim_buf_clear_namespace(0, ns, 0, -1) end, 300)
          end
        end
      end)
    end)
  end,

  peek_stacktrace = function(node)
    Client:initialize(function()
      Client.test:get_failure_info(node.id, function(info)
        if not info then return end

        local content = {}
        if info.message then table.insert(content, info.message) end
        if info.stackTrace then
          local trace_lines = vim.split(info.stackTrace, "\n")
          vim.list_extend(content, trace_lines)
        end
        if #content == 0 then table.insert(content, "No failure details available.") end

        -- Create a floating window for the stacktrace
        local win = WindowModule.new_float()
        win:write_buf(content):pos_center():create()

        -- Set filetype for syntax highlighting if possible
        vim.api.nvim_buf_set_option(win.buf, "filetype", "cs")
      end)
    end)
  end,

  expand_node = function(node)
    Tree.set_expanded(node.id, not node.expanded)
    M.refresh()
  end,

  toggle_filter = function()
    State.filter_failed_only = not State.filter_failed_only
    M.refresh()
  end,
}

local function on_cursor_moved()
  if not State.win or not vim.api.nvim_win_is_valid(State.win) then return end

  local line = vim.api.nvim_win_get_cursor(State.win)[1]
  local node = View.get_node_at_line(Tree, line)

  -- Optimization: Update if node changed OR if status changed (handled by status update event)
  if node and node.id ~= State.active_node_id then
    State.active_node_id = node.id
    local node_status = Tree.get_status(node.id)

    -- PASS NODE HERE
    Header.render(State.header_status, node, node_status)
  end
end

-- Also update the status handler to trigger a redraw with the node
M.handle_status_update = function(node_id, status_payload)
  if State.active_node_id == node_id then
    local node = Tree.nodes_by_id[node_id]
    Header.render(State.header_status, node, status_payload)
  end

  vim.schedule(M.refresh)
end

local function register_autocmds()
  if not State.buf then return end

  local group = vim.api.nvim_create_augroup("EasyDotnetTestRunner", { clear = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = State.buf,
    callback = on_cursor_moved,
    group = group,
  })
end
-- --- RENDERING ---

local function render_buffer()
  if not State.buf or not vim.api.nvim_buf_is_valid(State.buf) then return end

  -- 1. Pure Functional Build
  -- We pass the filter state to the View builder
  local lines, highlights = View.build(Tree, Tree.status_by_id, {
    options = State.options,
    filter_failed = State.filter_failed_only,
  })

  -- 2. Imperative DOM Update
  vim.api.nvim_buf_set_option(State.buf, "modifiable", true)
  vim.api.nvim_buf_clear_namespace(State.buf, Constants.ns_id, 0, -1)
  vim.api.nvim_buf_set_lines(State.buf, 0, -1, true, lines)

  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(State.buf, Constants.ns_id, hl.group, hl.index - 1, 0, -1)
  end

  vim.api.nvim_buf_set_option(State.buf, "modifiable", false)
end

local function register_keymaps()
  if not State.buf then return end
  local maps = State.options.mappings or {}

  local function map(config_key, action_fn)
    local def = maps[config_key]
    if not def then return end

    vim.keymap.set("n", def.lhs, function()
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local node = View.get_node_at_line(Tree, line)

      -- Some actions (like global refresh) don't need a specific node
      -- Wrapper logic to handle nil nodes inside the action if necessary,
      -- or check here.
      action_fn(node)
    end, { buffer = State.buf, desc = def.desc, noremap = true, silent = true })
  end

  -- Wire up actions to configuration keys
  map("run", function(node)
    if node then Actions.run_node(node) end
  end)
  map("debug_test", function(node)
    if node then Actions.debug_node(node) end
  end)
  map("go_to_file", function(node)
    if node then Actions.go_to_file(node) end
  end)
  map("peek_stacktrace", function(node)
    if node then Actions.peek_stacktrace(node) end
  end)

  -- Tree/View Actions
  map("expand_node", function(node)
    if node then Actions.expand_node(node) end
  end)
  map("expand", function(node)
    if node then Actions.expand_node(node) end
  end) -- Alias
  map("filter_failed_tests", function() Actions.toggle_filter() end)

  -- Global Actions
  map("refresh_testrunner", function()
    Client:initialize(function() Client.test:test_runner_discover() end)
  end)
  map("close", function() M.toggle() end)
end

-- --- PUBLIC API ---

M.setup = function(opts) State.options = opts or {} end

M.handle_summary_update = function(summary)
  State.header_status = summary
  Header.render(summary)
end

M.refresh = function() render_buffer() end

M.open = function(mode)
  -- Default to float if not specified
  mode = mode or State.options.viewmode or "float"

  -- 1. Ensure Buffer Exists
  if not State.buf or not vim.api.nvim_buf_is_valid(State.buf) then
    State.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(State.buf, "Test Manager")
    vim.api.nvim_buf_set_option(State.buf, "filetype", "easy-dotnet")
  end

  -- 2. Create Window based on Mode
  if mode == "float" then
    if State.win and vim.api.nvim_win_is_valid(State.win) then
      -- Already open, just focus
      vim.api.nvim_set_current_win(State.win)
    else
      local width = math.floor(vim.o.columns * 0.8)
      local height = math.floor(vim.o.lines * 0.8)

      local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 2),
        style = "minimal",
        border = "rounded",
      }

      State.win = vim.api.nvim_open_win(State.buf, true, win_opts)
      vim.wo[State.win].winfixbuf = true

      -- 3. Create/Attach Header
      -- Header.create returns the wrapped window object
      local header_win = Header.create(win_opts)

      -- Link closing: If main window closes, header should close
      -- We assume Header.create handles its own autocmds or we can add one here
      vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(State.win),
        callback = function()
          Header.close()
          State.win = nil
        end,
        once = true,
      })

      -- Initial Render of Header
      Header.render(State.header_status)
      vim.api.nvim_set_current_win(State.win)
    end
  elseif mode == "split" or mode == "vsplit" then
    vim.cmd(mode)
    State.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(State.win, State.buf)
  elseif mode == "buf" then
    State.win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(State.buf)
  end
  register_autocmds()

  vim.schedule(on_cursor_moved)
  register_keymaps()
  M.refresh()
end

M.toggle = function(mode)
  if State.win and vim.api.nvim_win_is_valid(State.win) then
    M.close()
  else
    M.open(mode)
  end
end

M.close = function()
  if State.win and vim.api.nvim_win_is_valid(State.win) then
    vim.api.nvim_win_close(State.win, true)
    State.win = nil
    Header.close()
  end
end

return M
