local neotest = {}
local test_runner = require("easy-dotnet.test-runner.render")
local win = require("easy-dotnet.test-runner.render")
local icons = require("easy-dotnet.options").options.test_runner.icons
local nio = require("nio")

local function find_node_or_throw(id)
  local node = nil
  win.traverse(nil, function(i)
    if i.id == id then node = i end
  end)
  if not node then error("failed to find node with id " .. id) end
  return node
end

---@class neotest.Adapter
---@field name string
neotest.Adapter = {
  name = "neotest-easy-dotnet",
}

---Find the project root directory given a current directory to work from.
---Should no root be found, the adapter can still be used in a non-project context if a test file matches.
---@async
---@param dir string @Directory to treat as cwd
---@return string | nil @Absolute root dir of test suite
function neotest.Adapter.root(dir)
  print(dir)
  return dir
  -- local solution_path = "C:/Users/Gustav/repo/neotest/neotest.sln"
  --
  -- if not solution_path then
  --   return nil -- No solution file path available
  -- end
  --
  -- local path = Path:new(dir):joinpath(solution_path):absolute()
  -- local root_dir = Path:new(path):parent():absolute()
  -- return root_dir
end

---Filter directories when searching for test files
---@async
---@param name string Name of directory
---@param rel_path string Path to directory, relative to root
---@param root string Root directory of project
---@return boolean
function neotest.Adapter.filter_dir(name, rel_path, root) return name ~= "bin" and name ~= "obj" end

---@async
---@param file_path string
---@return boolean
function neotest.Adapter.is_test_file(file_path)
  local is_test_file = false
  test_runner.traverse(nil, function(i)
    if is_test_file == true then return end
    if i.file_path == vim.fs.normalize(file_path) and i.type == "test" then is_test_file = true end
  end)
  return is_test_file
end

---Given a file path, parse all the tests within it.
---@async
---@param file_path string Absolute file path
---@return neotest.Tree | nil
function neotest.Adapter.discover_positions(file_path)
  print("Discover positions in file: " .. file_path)

  local ns_id = file_path

  local result = {
    {
      type = "file",
      id = ns_id,
      name = vim.fn.fnamemodify(file_path, ":t"),
      path = file_path,
      range = { 0, -1, 0, -1 },
      context = {},
    },
  }

  ---@param i TestNode
  test_runner.traverse(nil, function(i)
    if i.file_path == vim.fs.normalize(file_path) and vim.iter(vim.tbl_values(i.children)):any(function(r) return r.type == "test" or r.type == "test_group" end) then
      local group = {
        {
          type = "namespace",
          id = i.id,
          name = i.name,
          path = file_path,
          range = { 0, -1, 0, -1 },
          running_id = i.id,
          context = {
            get_node = function() return find_node_or_throw(i.id) end,
          },
        },
      }

      for _, value in pairs(i.children) do
        table.insert(group, {
          type = "test",
          id = value.id,
          name = value.name,
          path = file_path,
          range = { value.line_number - 2, value.line_number, 0, 1 },
          running_id = value.id,
          context = {
            get_node = function() return find_node_or_throw(value.id) end,
          },
        })
      end

      table.insert(result, group)
    end
  end)

  if #result == 1 then
    print("No tests found in file: " .. file_path)
    return nil
  end

  print(file_path .. " " .. #result)

  local trees = require("neotest.types.tree").from_list(result, function(item) return item.name end)
  return trees
end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec | neotest.RunSpec[]
function neotest.Adapter.build_spec(args)
  return {
    command = "echo",
    cwd = args.tree:data().path,
    context = {
      node = args.tree:data(),
    },
  }
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function neotest.Adapter.results(spec, result, tree)
  local node = spec.context.node.context.get_node()
  local future = nio.control.future()
  require("easy-dotnet.test-runner.keymaps").VsTest_Run(node, win, function() future.set(spec.context.node.context.get_node()) end)

  local final_node = future.wait()
  local res = {}

  win.traverse(final_node, function(i)
    local status = "failed"
    if i and i.icon then
      if i.icon == icons.passed then
        status = "passed"
      elseif i.icon == icons.skipped then
        status = "skipped"
      end
    end

    res[i.id] = {
      status = status,
    }
  end)

  return res
end

return neotest
