local neotest = {}
local tree = require("neotest.types.tree")
local test_runner = require("easy-dotnet.test-runner.render")
local Path = require("plenary.path")

---@class neotest.Adapter
---@field name string
neotest.Adapter = {}

---Find the project root directory given a current directory to work from.
---Should no root be found, the adapter can still be used in a non-project context if a test file matches.
---@async
---@param dir string @Directory to treat as cwd
---@return string | nil @Absolute root dir of test suite
function neotest.Adapter.root(dir)
  local solution_path = test_runner.tree.solution_file_path -- e.g. "./src/NeovimDebugProject.sln"

  if not solution_path then
    return nil -- No solution file path available
  end

  local path = Path:new(dir):joinpath(solution_path):absolute()
  local root_dir = Path:new(path):parent():absolute()
  return root_dir
end

---Filter directories when searching for test files
---@async
---@param name string Name of directory
---@param rel_path string Path to directory, relative to root
---@param root string Root directory of project
---@return boolean
function neotest.Adapter.filter_dir(name, rel_path, root)
  print("filter called")
  return true
end

---@async
---@param file_path string
---@return boolean
function neotest.Adapter.is_test_file(file_path)
  local is_test_file = false
  test_runner.traverse(nil, function(i)
    if is_test_file == true then return end
    if i.file_path == file_path then is_test_file = true end
  end)
  return is_test_file
end

---Given a file path, parse all the tests within it.
---@async
---@param file_path string Absolute file path
---@return neotest.Tree | nil
function neotest.Adapter.discover_positions(file_path)
  print("Discover positions in file: " .. file_path)

  local items = {}

  test_runner.traverse(nil, function(i)
    if i and i.file_path == file_path then
      table.insert(items, {
        name = i.name or "UnnamedTest",
        path = file_path,
        row = i.line_number or 0, -- line_number is expected to be 0-indexed
        type = "test", -- required by neotest
      })
    end
  end)

  if #items == 0 then
    print("No tests found in file: " .. file_path)
    return nil
  end

  return require("neotest.lib.treesitter.tree").from_list(items, function(i)
    return i.name
  end)
end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec | neotest.RunSpec[]
function neotest.Adapter.build_spec(args)
  -- TODO: dispatch run command to F# process that takes a list of test id's
  print("Build spec for: " .. args.tree:data().name)

  local tree = args.tree
  local node = tree:data()
  local file_path = node.path

  local position = node.type
  local test_name = node.name

  local command = ""

  if position == "file" then
    -- Run all tests in the file
    command = "dotnet test " .. vim.fn.fnameescape(file_path) .. " --filter " .. vim.fn.shellescape("FullyQualifiedName=" .. test_name)
    -- command = "dotnet test " .. vim.fn.fnameescape(file_path)
  elseif position == "test" then
    -- Run a specific test
    command = "dotnet test " .. vim.fn.fnameescape(file_path) .. " --filter " .. vim.fn.shellescape("FullyQualifiedName=" .. test_name)
  else
    return nil
  end

  command = 'dotnet test /home/gustav/repo/NeovimDebugProject/src/NeovimDebugProject.Specs --filter "UnitTest"'

  print(command)
  return {
    command = command,
    cwd = vim.fn.getcwd(),
    context = {
      file = file_path,
      test = test_name,
    },
  }
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function neotest.Adapter.results(spec, result, tree)
  --TODO: capture stdout from F# script and either parse stdout as result or file path. Investigate size limitations with respect to vim.fn.json_decode
  local results = {}

  for _, node in tree:iter_nodes() do
    print(vim.inspect(node:data()))
    if node:data().type == "file" then
      local t = node:data()
      t.status = 'failed'
      results[node:data().id] = t
    
      -- {
      --   status = "passed",
      --   short = "Test passed",
      --   output = "",
      -- }
    end
  end
   
  print(vim.inspect(results))

  return results
end

return neotest
