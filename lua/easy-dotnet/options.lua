local function get_secret_path(secret_guid)
  local path = ""
  local home_dir = vim.fn.expand('~')
  if require("easy-dotnet.extensions").isWindows() then
    local secret_path = home_dir ..
        '\\AppData\\Roaming\\Microsoft\\UserSecrets\\' .. secret_guid .. "\\secrets.json"
    path = secret_path
  else
    local secret_path = home_dir .. "/.microsoft/usersecrets/" .. secret_guid .. "/secrets.json"
    path = secret_path
  end
  return path
end

return {
  ---@param path string
  ---@param action "test"|"restore"|"build"|"run"
  terminal = function(path, action)
    local commands = {
      run = function()
        return "dotnet run --project " .. path
      end,
      test = function()
        return "dotnet test " .. path
      end,
      restore = function()
        return "dotnet restore " .. path
      end,
      build = function()
        return "dotnet build " .. path
      end
    }
    local command = commands[action]() .. "\r"
    vim.cmd("vsplit")
    vim.cmd("term " .. command)
  end,
  secrets = {
    path = get_secret_path,
  },
  test_runner = {
    noBuild = true,
    noRestore = true,
  }
}
