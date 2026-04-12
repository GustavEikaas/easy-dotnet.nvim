local M = {}

M.pick = function(params, response, _throw, _validate)
  require("easy-dotnet.picker").server_picker(params, response)
end

M.live = function(_params, response, _throw, _validate) response(nil) end

return M
