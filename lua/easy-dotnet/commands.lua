local M = {}

---@class Command
---@field subcommands table<string,Command> | nil
---@field handle function<string,nil>
---@field passtrough boolean | nil

local function slice(array, start_index, end_index)
  local result = {}
  table.move(array, start_index, end_index, 1, result)
  return result
end

---@param arguments table<string>|nil
local function passthrough_args_handler(arguments)
  if not arguments or #arguments == 0 then
    return ""
  end
  local loweredArgument = arguments[1]:lower()
  if loweredArgument == "release" then
    return string.format("-c release %s", passthrough_args_handler(slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "debug" then
    return string.format("-c debug %s", passthrough_args_handler(slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "-c" then
    local flag = string.format("-c %s", #arguments >= 2 and arguments[2] or "")
    return string.format("%s %s", flag, passthrough_args_handler(slice(arguments, 3, #arguments) or ""))
  elseif loweredArgument == "--no-build" then
    return string.format("--no-build %s", passthrough_args_handler(slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "--no-restore" then
    return string.format("--no-restore %s", passthrough_args_handler(slice(arguments, 2, #arguments) or ""))
  else
    vim.notify("Unknown argument to dotnet build " .. loweredArgument, vim.log.levels.WARN)
  end
end

local actions = require("easy-dotnet.actions")


---@type Command
M.run = {
  handle = function(args, options)
    actions.run(options.terminal, false, passthrough_args_handler(args))
  end,
  passtrough = true
}

M.secrets = {
  handle = function(args, options)
    local secrets = require("easy-dotnet.secrets")
    secrets.edit_secrets_picker(options.secrets.path)
  end,
}

M.test = {
  handle = function(args, options)
    actions.test(options.terminal, false, passthrough_args_handler(args))
  end,
  passtrough = true
}



return M
