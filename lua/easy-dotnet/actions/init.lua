local M = {}

M.watch = require("easy-dotnet.actions.watch").run_project_picker
M.pack = require("easy-dotnet.actions.pack").pack
M.pack_and_push = require("easy-dotnet.actions.pack").push

return M
