local polyfills = require("easy-dotnet.polyfills")
local logger    = require("easy-dotnet.logger")
local M = {}

---@param file file*
---@param filepath string
local function check_and_upgrade_script(file, filepath, script_template, script_name)
  local v = file:read("l"):match("//v(%d+)")
  file:close()
  local new_v = script_template:match("//v(%d+)")
  if v ~= new_v then
    local overwrite_file = io.open(filepath, "w+")
    if overwrite_file == nil then error("Failed to create the file: " .. filepath) end
    logger.info("Updating " .. script_name)
    overwrite_file:write(script_template)
    overwrite_file:close()
  end
end

---@return string
M.ensure_and_get_fsx_path = function(script_template, script_name)
  local dir = require("easy-dotnet.constants").get_data_directory()
  local filepath = polyfills.fs.joinpath(dir, script_name)
  local file = io.open(filepath, "r")
  if file then
    check_and_upgrade_script(file, filepath, script_template, script_name)
  else
    file = io.open(filepath, "w")
    if file == nil then error("Failed to create the file: " .. filepath) end
    file:write(script_template)

    file:close()
  end

  return filepath
end

return M
