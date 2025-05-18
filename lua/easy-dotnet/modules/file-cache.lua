local M = {}

--- @class FileCacheEntry
--- @field mtime integer # Last known modification time (in seconds)
--- @field value any     # Cached value

--- @type table<string, FileCacheEntry>
local cache = {}

--- Get a cached value for a file, recomputing it if the file has changed.
--- @param path string # Absolute or relative path to the file
--- @param value_factory fun(lines: string[]): any # Function that accepts file lines and returns a computed value
--- @return any # The cached or newly computed value
function M.get(path, value_factory)
  local stat = vim.loop.fs_stat(path)
  if not stat then
    vim.notify("File not found: " .. path, vim.log.levels.WARN)
    return nil
  end

  local mtime = stat.mtime.sec
  local entry = cache[path]

  if entry and entry.mtime == mtime then return entry.value end

  local lines = vim.fn.readfile(path)
  local value = value_factory(lines)

  cache[path] = {
    mtime = mtime,
    value = value,
  }

  return value
end

return M
