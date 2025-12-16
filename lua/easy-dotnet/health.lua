local options = require("easy-dotnet.options")
--checkhealth easy-dotnet
local M = {}

---@param command  table<string>
---@param advice  string | nil
local function ensure_dep_installed(command, advice)
  local exec = command
  advice = advice or ""
  local success = pcall(function() vim.fn.system(exec) end)
  local cmd_name = table.concat(vim.tbl_filter(function(item) return type(item) == "string" and not item:match("^%-") end, exec), " ")
  if success and vim.v.shell_error == 0 then
    vim.health.ok(cmd_name .. " is installed")
  else
    print("" .. vim.v.shell_error)
    vim.health.error(cmd_name .. " is not installed", { advice })
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

local function check_debugger_configured()
  local success, s = pcall(function() return require("dap") end)
  if not success or not s then
    --verifying nvim-dap is done in another check
    return
  end
  for key, _ in pairs(s.adapters) do
    if key == "easy-dotnet" then
      vim.health.ok("debugger is configured")
      return
    end
  end
  if options.get_option("debugger").bin_path == nil then
    vim.health.error(
      "debugger is not configured because `options.debugger.bin_path` was not supplied",
      { "https://github.com/GustavEikaas/easy-dotnet.nvim?tab=readme-ov-file#nvim-dap-configuration" }
    )
  else
    vim.health.error("debugger not configured, is your debug config overwriting dap config?", { "https://github.com/GustavEikaas/easy-dotnet.nvim?tab=readme-ov-file#nvim-dap-configuration" })
  end
end

local function check_cmp()
  -- nvim-cmp
  if pcall(require, "cmp") then
    local cmp = require("cmp")
    if type(cmp.get_registered_sources) == "function" then
      for _, value in ipairs(cmp.get_registered_sources()) do
        if value.name == "easy-dotnet" then
          vim.health.ok("cmp source configured correctly")
          return
        end
      end
    end
  end
  -- blink.cmp
  if pcall(require, "blink.cmp.config") then
    local blink_config = require("blink.cmp.config")
    if blink_config.sources.providers["easy-dotnet"] then
      vim.health.ok("cmp source configured correctly")
      return
    end
  end

  vim.health.warn("cmp source not configured", { "https://github.com/GustavEikaas/easy-dotnet.nvim?tab=readme-ov-file#package-autocomplete" })
end

local function os_info()
  local platform = vim.loop.os_uname()
  local sysname = platform.sysname
  local release = platform.release

  if release:lower():match("arch") then release = release .. " btw" end

  vim.health.info(string.format("%s (%s)", sysname, release))
end

local function print_dotnet_info()
  local version = vim.fn.system("dotnet --version"):gsub("\n", "")
  local sdks = vim.fn.systemlist("dotnet --list-sdks")

  if version == "" then
    vim.health.warn("dotnet is not installed or not in PATH")
    return
  end

  vim.health.info("dotnet version: " .. version)

  if #sdks == 0 then
    vim.health.warn("No .NET SDKs found")
  else
    vim.health.info("Installed SDKs:")
    for _, sdk in ipairs(sdks) do
      vim.health.info("  " .. sdk)
    end
  end
end

local function print_nvim_version()
  local v = vim.version()
  local version_str = string.format("Neovim version: %d.%d.%d", v.major, v.minor, v.patch)
  vim.health.info(version_str)
end

local function get_shell_info()
  local shell = vim.o.shell
  vim.health.info("Shell: " .. shell)
end
local function get_commit_info()
  local source = debug.getinfo(1, "S").source:sub(2)
  local dir = vim.fn.fnamemodify(source, ":h")
  local sha = vim.fn.system({ "git", "-C", dir, "rev-parse", "HEAD" })
  vim.health.info("Commit: " .. vim.trim(sha or ""))
end

M.check = function()
  vim.health.start("General information")
  os_info()
  print_nvim_version()
  get_shell_info()
  pcall(get_commit_info)
  vim.health.start("Dotnet information")
  print_dotnet_info()
  vim.health.start("easy-dotnet CLI dependencies")
  ensure_dep_installed({ "dotnet", "-h" })
  ensure_dep_installed({ "dotnet", "easydotnet", "-v" }, "dotnet tool install --global EasyDotnet")
  ensure_dep_installed({ "dotnet", "ef" }, "dotnet tool install --global dotnet-ef")

  vim.health.start("easy-dotnet lua dependencies")
  ensure_nvim_dep_installed("plenary", "https://github.com/nvim-lua/plenary.nvim")
  ensure_nvim_dep_installed("dap", { "Some functionality will be disabled", "https://github.com/mfussenegger/nvim-dap" }, false)

  vim.health.start("easy-dotnet dap configuration (optional)")
  check_debugger_configured()

  vim.health.start("easy-dotnet configuration")
  local selected_picker = require("easy-dotnet.options").get_option("picker")
  if selected_picker == "telescope" then
    ensure_nvim_dep_installed("telescope", { "This is selected in your config but is not installed", "A fallback will be used instead", "https://github.com/nvim-telescope/telescope.nvim" }, true)
  elseif selected_picker == "fzf" then
    ensure_nvim_dep_installed("fzf-lua", { "This is selected in your config but is not installed", "A fallback will be used instead", "https://github.com/ibhagwan/fzf-lua" }, true)
  elseif selected_picker == "snacks" then
    ensure_nvim_dep_installed("snacks", { "This is selected in your config but is not installed", "A fallback will be used instead", "https://github.com/folke/snacks.nvim" }, true)
  end

  check_cmp()
  vim.health.start("User config")
  vim.health.info(vim.inspect(require("easy-dotnet.options").orig_config))
end

return M
