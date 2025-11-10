local polyfills = require("easy-dotnet.polyfills")
local M = {}

M.ns_id = vim.api.nvim_create_namespace("easy-dotnet")
M.sign_namespace = "EasyDotnetTestSignGroup"
M.lsp_client_name = "easy_dotnet"
M.debug_adapter_name = "easy-dotnet"

M.get_data_directory = function()
  local dir = polyfills.fs.joinpath(vim.fs.normalize(vim.fn.stdpath("data")), "easy-dotnet")
  local file_utils = require("easy-dotnet.file-utils")
  file_utils.ensure_directory_exists(dir)
  return dir
end

M.highlights = {
  EasyDotnetTestRunnerSolution = "EasyDotnetTestRunnerSolution",
  EasyDotnetTestRunnerProject = "EasyDotnetTestRunnerProject",
  EasyDotnetTestRunnerTest = "EasyDotnetTestRunnerTest",
  EasyDotnetTestRunnerSubcase = "EasyDotnetTestRunnerSubcase",
  EasyDotnetTestRunnerDir = "EasyDotnetTestRunnerDir",
  EasyDotnetTestRunnerPackage = "EasyDotnetTestRunnerPackage",
  EasyDotnetTestRunnerPassed = "EasyDotnetTestRunnerPassed",
  EasyDotnetTestRunnerFailed = "EasyDotnetTestRunnerFailed",
  EasyDotnetTestRunnerRunning = "EasyDotnetTestRunnerRunning",
  --
  EasyDotnetDebuggerFloatVariable = "EasyDotnetDebuggerFloatVariable",
  EasyDotnetDebuggerVirtualException = "EasyDotnetDebuggerVirtualException",
  EasyDotnetDebuggerVirtualVariable = "EasyDotnetDebuggerVirtualVariable",
}

M.signs = {
  EasyDotnetTestSign = "EasyDotnetTestSign",
  EasyDotnetTestPassed = "EasyDotnetTestPassed",
  EasyDotnetTestFailed = "EasyDotnetTestFailed",
  EasyDotnetTestSkipped = "EasyDotnetTestSkipped",
  EasyDotnetTestError = "EasyDotnetTestError",
  EasyDotnetTestInProgress = "EasyDotnetTestInProgress",
}

M.dotnet_files = {
  --- Checks if a path points to any .NET project file (*.csproj, *.fsproj, etc.)
  --- @param path string
  --- @return boolean
  is_any_project = function(path) return path:match("[^/\\]+%.%a+proj") ~= nil end,
  --- Checks if a path points specifically to a C# project file (*.csproj)
  --- @param path string
  --- @return boolean
  is_csharp_project = function(path) return path:match("%.csproj$") ~= nil end,
  directory_packages_props = "directory.packages.props",
  directory_build_props = "directory.build.props",
  packages_props = "packages.props",
}

return M
