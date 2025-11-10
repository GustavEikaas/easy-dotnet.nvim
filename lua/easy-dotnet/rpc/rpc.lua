local extensions = require("easy-dotnet.extensions")

local M = {}

M.global_rpc_client = require("easy-dotnet.rpc.dotnet-client"):new()

--- Returns the full platform-specific path for a named pipe.
---
--- On Windows, returns a named pipe path like `\\.\pipe\<pipe_name>`.
--- On macOS, returns a path under `$TMPDIR/CoreFxPipe_<pipe_name>`.
--- On Linux/other Unix, returns a path under `/tmp/CoreFxPipe_<pipe_name>`.
---
--- @param pipe_name string The name of the pipe.
--- @return string The full path to the pipe on the current platform.
function M.get_pipe_path(pipe_name)
  if extensions.isWindows() then
    return [[\\.\pipe\]] .. pipe_name
  elseif extensions.isDarwin() then
    return os.getenv("TMPDIR") .. "CoreFxPipe_" .. pipe_name
  else
    return "/tmp/CoreFxPipe_" .. pipe_name
  end
end

return M
