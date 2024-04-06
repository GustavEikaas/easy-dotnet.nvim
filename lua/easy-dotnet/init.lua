local M = {}

local options = require("easy-dotnet.options")
local run_project = require("easy-dotnet.run_project")
local secrets = require("easy-dotnet.secrets")
local debug = require("easy-dotnet.debugger")

local function merge_tables(table1, table2)
  local merged = {}
  for k, v in pairs(table1) do
    merged[k] = v
  end
  for k, v in pairs(table2) do
    merged[k] = v
  end
  return merged
end

M.setup = function(opts)
  local merged_opts = merge_tables(options, opts or {})
  local commands = {
    secrets = function()
      secrets.edit_secrets_picker(merged_opts.secrets.on_select)
    end,
    run = function()
      run_project.run_project_picker(merged_opts.run_project.on_select)
    end
  }

  _G.handle_dotnet_command = function(...)
    local args = { ... }
    local subcommand = table.remove(args, 1)
    local func = commands[subcommand]
    if func then
      func()
    else
      print("Invalid subcommand:", subcommand)
    end
  end

  vim.api.nvim_command('command! -nargs=* Dotnet lua handle_dotnet_command(<f-args>)')

  M.run_project = function()
    run_project.run_project_picker(merged_opts.run_project.on_select)
  end
  M.secrets = function()
    secrets.edit_secrets_picker(merged_opts.secrets.on_select)
  end
end

M.get_debug_dll = debug.get_debug_dll

return M
