local M = {}

M.name = "easy-dotnet"

local function get_client() return require("easy-dotnet.rpc.rpc").global_rpc_client end

local function is_initialized()
  local ok, state = pcall(require, "easy-dotnet.test-runner.state")
  return ok and state.initialized == true
end

-- Shared future: first caller triggers init, all concurrent callers suspend on the
-- same future and resume together once the server finishes initialization.
-- neotest always calls is_test_file / discover_positions inside nio coroutines,
-- so .wait() correctly yields without blocking the Neovim event loop.
local _init_future = nil

local function await_initialization()
  if is_initialized() then return true end

  if not _init_future then
    _init_future = require("nio").control.future()
    local sln = require("easy-dotnet.current_solution").try_get_selected_solution()
    if not sln then
      _init_future.set()
    else
      local client = get_client()
      client:initialize(function()
        client.testrunner:initialize(sln, function(result)
          if result and result.success then
            local ok, state = pcall(require, "easy-dotnet.test-runner.state")
            if ok then state.initialized = true end
          end
          _init_future.set()
        end)
      end)
    end
  end

  _init_future.wait()
  return is_initialized()
end

---@param _dir string
---@return string|nil
function M.root(_dir)
  local sln = require("easy-dotnet.current_solution").try_get_selected_solution()
  if not sln then return nil end
  return vim.fn.fnamemodify(sln, ":h")
end

---@param name string
---@return boolean
function M.filter_dir(name, _rel_path, _root) return not vim.tbl_contains({ "bin", "obj", ".git", ".vs", ".idea", "node_modules", "packages" }, name) end

---@param file_path string
---@return boolean
function M.is_test_file(file_path)
  if not vim.endswith(file_path, ".cs") then return false end
  if not await_initialization() then return false end
  local state = require("easy-dotnet.test-runner.state")
  local norm = vim.fn.resolve(file_path)
  for _, node in pairs(state.nodes) do
    if node.filePath and vim.fn.resolve(node.filePath) == norm then return true end
  end
  return false
end

---@param file_path string
---@return neotest.Tree|nil
function M.discover_positions(file_path)
  if not await_initialization() then return nil end

  local nio = require("nio")
  local positions = nil
  local done = nio.control.future()

  get_client().testrunner:neotest_positions(file_path, function(result)
    positions = result
    done.set()
  end)
  done.wait()

  if not positions or #positions == 0 then return nil end

  local node_map = {}
  for _, pos in ipairs(positions) do
    node_map[pos.id] = pos
  end

  local function build_list(node_id)
    local node = node_map[node_id]
    if not node then return nil end
    local list = {
      {
        id = node.id,
        name = node.name,
        type = node.type,
        path = file_path,
        range = { node.startLine or 0, 0, node.endLine or (node.startLine or 0), 0 },
      },
    }
    for _, child in ipairs(positions) do
      if child.parentId == node_id then
        local child_list = build_list(child.id)
        if child_list then table.insert(list, child_list) end
      end
    end
    return list
  end

  local file_root = {
    {
      id = file_path,
      name = vim.fn.fnamemodify(file_path, ":t"),
      type = "file",
      path = file_path,
      range = { 0, 0, 0, 0 },
    },
  }
  for _, pos in ipairs(positions) do
    if pos.parentId == file_path then
      local child_list = build_list(pos.id)
      if child_list then table.insert(file_root, child_list) end
    end
  end

  local Tree = require("neotest.types").Tree
  return Tree.from_list(file_root, function(pos) return pos.id end)
end

---@param args neotest.RunArgs
---@return neotest.RunSpec|nil
function M.build_spec(args)
  local root = args.tree:data()

  local result_ids = {}
  for _, pos in args.tree:iter() do
    if pos.type == "test" then table.insert(result_ids, pos.id) end
  end

  if #result_ids == 0 then result_ids = { root.id } end

  local node_id = root.id
  if root.type == "file" then
    local first_child = args.tree:children()[1]
    node_id = first_child and first_child:data().id or root.id
  elseif root.type == "dir" then
    local state = require("easy-dotnet.test-runner.state")
    local dir = vim.fn.resolve(root.id)
    for _, node in pairs(state.nodes) do
      if node.type and node.type.type == "Project" and node.filePath then
        if vim.fn.resolve(vim.fn.fnamemodify(node.filePath, ":h")) == dir then
          node_id = node.id
          break
        end
      end
    end
  end

  return {
    command = {},
    context = {
      node_id = node_id,
      result_ids = result_ids,
      debug = args.strategy == "dap",
    },
    strategy = require("easy-dotnet.neotest.strategy"),
    stream = require("easy-dotnet.neotest.stream"),
  }
end

---@type fun(spec: neotest.RunSpec, result: neotest.StrategyResult, tree: neotest.Tree): table<string, neotest.Result>
M.results = require("easy-dotnet.neotest.results")

return M
