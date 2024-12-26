local M = {}

---@param command  string | table<string>
---@param advice  string | nil
local function ensure_dep_installed(command, advice)
  local exec = type(command) == "string" and { command } or command
  advice = advice or ""
  vim.fn.system(exec)
  if vim.v.shell_error == 0 then
    vim.health.ok(exec[1] .. " is installed")
  else
    print("" .. vim.v.shell_error)
    vim.health.error(exec[1] .. " is not installed", { advice })
  end
end


local function ensure_nvim_dep_installed(pkg, advice)
  local advice_lines = type(advice) == "string" and { advice } or advice
  local success = pcall(function() require(pkg) end)
  if not success then
    vim.health.error(pkg .. " not installed", advice_lines)
  else
    vim.health.ok(pkg .. " installed")
  end
end

local function measure_function(cb)
  local start_time = os.clock()
  cb()
  local end_time = os.clock()
  local elapsed_time = end_time - start_time
  return elapsed_time
end

M.check = function()
  vim.health.start("easy-dotnet CLI dependencies")
  ensure_dep_installed({ "dotnet", "-h" })
  ensure_dep_installed("jq")
  ensure_dep_installed({ "dotnet-outdated", "-h" }, "dotnet tool install --global dotnet-outdated-tool")
  ensure_dep_installed("dotnet-ef", "dotnet tool install --global dotnet-ef")

  vim.health.start("easy-dotnet lua dependencies")
  ensure_nvim_dep_installed("plenary", "https://github.com/nvim-lua/plenary.nvim")
  ensure_nvim_dep_installed("dap", "https://github.com/mfussenegger/nvim-dap")
  ensure_nvim_dep_installed("telescope", "https://github.com/nvim-telescope/telescope.nvim")
  ensure_nvim_dep_installed("roslyn",
    { "If you are using another LSP you can safely ignore this warning", "https://github.com/seblj/roslyn.nvim" })

  vim.health.start("easy-dotnet configuration")
  local config = require("easy-dotnet.options").options
  local sdk_path_time = measure_function(config.get_sdk_path)

  if sdk_path_time > 1 then
    vim.health.warn(string.format("options.get_sdk_path took %d seconds", sdk_path_time),
      "You should add get_sdk_path to your options for a performance improvement🚀. Check readme")
  end
end

return M
