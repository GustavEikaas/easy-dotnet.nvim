local E = {}

E.isWindows = function()
  local platform = vim.loop.os_uname().sysname
  return platform == "Windows_NT"
end

return E
