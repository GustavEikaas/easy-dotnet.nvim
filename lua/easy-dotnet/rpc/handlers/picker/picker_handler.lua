local M = {}

M.pick = function(params, response, _throw, _validate)
  require("easy-dotnet.picker").server_picker(params, response)
end

M.live = function(params, response, _throw, _validate)
  require("easy-dotnet.picker").server_live(params, response)
end

return M
