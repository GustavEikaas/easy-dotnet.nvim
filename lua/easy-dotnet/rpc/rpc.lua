local extensions = require("easy-dotnet.extensions")

local M = {}

M.global_rpc_client = require("easy-dotnet.rpc.dotnet-client"):new()

-- returns a temp dir path with a trailing slash
local function get_tmpdir()
  local tmp = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
  -- ensure trailing slash
  if not tmp:match("/$") then tmp = tmp .. "/" end
  return tmp
end

--- Returns the full platform-specific path for a named pipe.
---
--- On Windows, returns a named pipe path like `\\.\pipe\<pipe_name>`.
--- On macOS/Linux/Unix, returns a path under `$TMPDIR/CoreFxPipe_<pipe_name>`,
--- falling back to `/tmp/CoreFxPipe_<pipe_name>` if TMPDIR is not set.
---
--- @param pipe_name string The name of the pipe.
--- @return string The full path to the pipe on the current platform.
function M.get_pipe_path(pipe_name)
  if extensions.isWindows() then
    return [[\\.\pipe\]] .. pipe_name
  else
    return get_tmpdir() .. "CoreFxPipe_" .. pipe_name
  end
end

return M
