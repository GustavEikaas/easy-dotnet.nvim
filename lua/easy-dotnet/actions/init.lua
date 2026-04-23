local M = {}

M.pack = require("easy-dotnet.actions.pack").pack
M.pack_and_push = require("easy-dotnet.actions.pack").push
M.generate_test = require("easy-dotnet.actions.generate-test").generate_test

return M
