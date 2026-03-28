local M = {}

M.restore = require("easy-dotnet.actions.restore").restore
M.test = require("easy-dotnet.actions.test").run_test_picker
M.test_solution = require("easy-dotnet.actions.test").test_solution
M.test_watcher = require("easy-dotnet.actions.test").test_watcher
M.watch = require("easy-dotnet.actions.watch").run_project_picker
M.pack = require("easy-dotnet.actions.pack").pack
M.pack_and_push = require("easy-dotnet.actions.pack").push

return M
