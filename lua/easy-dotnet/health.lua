--checkhealth easy-dotnet
local M = {}

---@param command  string | table<string>
---@param advice  string | nil
local function ensure_dep_installed(command, advice)
  local exec = type(command) == "string" and { command } or command
  advice = advice or ""
  local success = pcall(function() vim.fn.system(exec) end)
  if success and vim.v.shell_error == 0 then
    vim.health.ok(exec[1] .. " is installed")
  else
    print("" .. vim.v.shell_error)
    vim.health.error(exec[1] .. " is not installed", { advice })
  end
end

---@param required boolean | nil
local function ensure_nvim_dep_installed(pkg, advice, required)
  if required == nil then required = true end

  local advice_lines = type(advice) == "string" and { advice } or advice
  local success = pcall(function() require(pkg) end)
  if not success then
    if not required then
      vim.health.warn(pkg .. " not installed", advice_lines)
    else
      vim.health.error(pkg .. " not installed", advice_lines)
    end
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

local function check_coreclr_configured()
  local success, s = pcall(function() return require("dap") end)
  if not success or not s then
    --verifying nvim-dap is done in another check
    return
  end
  for key, _ in pairs(s.adapters) do
    if key == "coreclr" then
      vim.health.ok("coreclr is configured")
      return
    end
  end
  vim.health.error("coreclr is not configured", { "https://github.com/GustavEikaas/easy-dotnet.nvim?tab=readme-ov-file#nvim-dap-configuration" })
end

local function check_cmp()
  local success, cmp = pcall(require, "cmp")
  if success then
    -- nvim-cmp
    if type(cmp.get_registered_sources) == "function" then
      for _, value in ipairs(cmp.get_registered_sources()) do
        if value.name == "easy-dotnet" then
          vim.health.ok("cmp source configured correctly")
          return
        end
      end
    else
      -- blink.compat
      local value = cmp.config.get_source_config("easy-dotnet")
      if value ~= nil and value.name == "easy-dotnet" then
        vim.health.ok("cmp source configured correctly")
        return
      end
    end
  else
    -- blink.cmp
    local blink_success, blink_cmp = pcall(require, "blink.cmp.config")
    if blink_success then
      if blink_cmp.sources.providers["easy-dotnet"] then
        vim.health.ok("cmp source configured correctly")
        return
      end
    end
  end

  vim.health.warn("cmp source not configured", { "https://github.com/GustavEikaas/easy-dotnet.nvim?tab=readme-ov-file#package-autocomplete" })
end

M.check = function()
  vim.health.start("easy-dotnet CLI dependencies")
  ensure_dep_installed({ "dotnet", "-h" })
  ensure_dep_installed("jq")
  ensure_dep_installed({ "dotnet-outdated", "-h" }, "dotnet tool install --global dotnet-outdated-tool")
  ensure_dep_installed("dotnet-ef", "dotnet tool install --global dotnet-ef")
  ensure_dep_installed({ "netcoredbg", "--version" }, "https://github.com/samsung/netcoredbg")

  vim.health.start("easy-dotnet lua dependencies")
  ensure_nvim_dep_installed("plenary", "https://github.com/nvim-lua/plenary.nvim")
  ensure_nvim_dep_installed("dap", { "Some functionality will be disabled", "https://github.com/mfussenegger/nvim-dap" }, false)
  ensure_nvim_dep_installed("roslyn", {
    "This is not required for this plugin but is a nice addition to the .Net developer experience",
    "If you are using another LSP you can safely ignore this warning",
    "https://github.com/seblj/roslyn.nvim",
  }, false)

  vim.health.start("easy-dotnet dap configuration (optional)")
  check_coreclr_configured()

  vim.health.start("easy-dotnet configuration")
  local config = require("easy-dotnet.options").options
  local selected_picker = require("easy-dotnet.options").get_option("picker")
  if selected_picker == "telescope" then
    ensure_nvim_dep_installed("telescope", { "This is selected in your config but is not installed", "A fallback will be used instead", "https://github.com/nvim-telescope/telescope.nvim" }, true)
  elseif selected_picker == "fzf" then
    ensure_nvim_dep_installed("fzf-lua", { "This is selected in your config but is not installed", "A fallback will be used instead", "https://github.com/ibhagwan/fzf-lua" }, true)
  elseif selected_picker == "snacks" then
    ensure_nvim_dep_installed("snacks", { "This is selected in your config but is not installed", "A fallback will be used instead", "https://github.com/folke/snacks.nvim" }, true)
  end

  local sdk_path_time = measure_function(config.get_sdk_path)
  if sdk_path_time > 1 then
    vim.health.warn(string.format("options.get_sdk_path took %d seconds", sdk_path_time), "You should add get_sdk_path to your options for a performance improvement🚀. Check readme")
  end
  check_cmp()
end

return M
