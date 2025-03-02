local polyfills = require("easy-dotnet.polyfills")
local M = {}

M.ns_id = vim.api.nvim_create_namespace("easy-dotnet")
M.sign_namespace = "EasyDotnetTestSignGroup"

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
}

M.signs = {
  EasyDotnetTestSign = "EasyDotnetTestSign",
  EasyDotnetTestPassed = "EasyDotnetTestPassed",
  EasyDotnetTestFailed = "EasyDotnetTestFailed",
  EasyDotnetTestSkipped = "EasyDotnetTestSkipped",
  EasyDotnetTestError = "EasyDotnetTestError",
}

return M
