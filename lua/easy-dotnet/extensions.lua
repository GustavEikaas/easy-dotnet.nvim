local E = {}

E.isWindows = function()
  local platform = vim.uv.os_uname().sysname
  return platform == "Windows_NT"
end

E.isDarwin = function()
  local platform = vim.uv.os_uname().sysname
  return platform == "Darwin"
end

E.isLinux = function()
  local platform = vim.uv.os_uname().sysname
  return platform == "Linux"
end

return E
