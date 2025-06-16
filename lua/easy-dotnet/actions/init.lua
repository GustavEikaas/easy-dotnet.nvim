---@class DotnetActionContext
---@field command string
---@field is_net_framework boolean

local M = {}

M.build = require("easy-dotnet.actions.build").build_project_picker
M.build_quickfix = require("easy-dotnet.actions.build").build_project_quickfix
M.build_solution = require("easy-dotnet.actions.build").build_solution
M.build_solution_quickfix = require("easy-dotnet.actions.build").build_solution_quickfix
M.restore = require("easy-dotnet.actions.restore").restore
M.test = require("easy-dotnet.actions.test").run_test_picker
M.test_solution = require("easy-dotnet.actions.test").test_solution
M.run = require("easy-dotnet.actions.run").run_project_picker
M.run_with_profile = require("easy-dotnet.actions.run").run_project_with_profile
M.test_watcher = require("easy-dotnet.actions.test").test_watcher
M.watch = require("easy-dotnet.actions.watch").run_project_picker
M.pack = require("easy-dotnet.actions.pack").pack
M.pack_and_push = require("easy-dotnet.actions.pack").push

return M
