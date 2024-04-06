local M = {}

M.build = require("easy-dotnet.actions.build").build_project_picker
M.restore = require("easy-dotnet.actions.restore").restore
M.test = require("easy-dotnet.actions.test").run_test_picker
M.run = require("easy-dotnet.actions.run").run_project_picker

return M
