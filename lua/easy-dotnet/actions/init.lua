local M = {}

M.build = require("easy-dotnet.actions.build").build_project_picker
M.build_solution = require("easy-dotnet.actions.build").build_solution
M.restore = require("easy-dotnet.actions.restore").restore
M.test = require("easy-dotnet.actions.test").run_test_picker
M.test_solution = require("easy-dotnet.actions.test").test_solution
M.run = require("easy-dotnet.actions.run").run_project_picker
M.test_watcher = require("easy-dotnet.actions.test").test_watcher

return M
