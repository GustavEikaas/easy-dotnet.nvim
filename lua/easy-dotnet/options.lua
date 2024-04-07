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
    vim.cmd('term')
    vim.cmd('startinsert!')
    vim.api.nvim_feedkeys(string.format("%s", command), 'n', true)
  end,
  secrets = {
    on_select = function(selectedItem)
      local home_dir = vim.fn.expand('~')
      if require("easy-dotnet.extensions").isWindows() then
        local secret_path = home_dir ..
            '\\AppData\\Roaming\\Microsoft\\UserSecrets\\' .. selectedItem.secrets .. "\\secrets.json"
        vim.cmd("edit " .. vim.fn.fnameescape(secret_path))
      else
        local secret_path = home_dir .. "/.microsoft/usersecrets/" .. selectedItem.secrets .. "/secrets.json"
        vim.cmd("edit " .. vim.fn.fnameescape(secret_path))
      end
    end
  },
}
