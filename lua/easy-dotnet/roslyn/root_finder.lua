local fs = require("easy-dotnet.fs")
local uv = vim.uv or vim.loop

local M = {}

local function absolute(path) return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")) end

---@param file_path string
---@param cb fun(path: string?)
function M.find_csproj_from_file(file_path, cb)
  local dir = vim.fs.dirname(file_path)
  if not dir or not uv.fs_stat(dir) then error("Invalid file path: " .. file_path) end

  fs.find_upward_first_async(absolute(dir), {
    patterns = { "%.csproj$" },
    on_done = cb,
  })
end

---@param file_path string
---@param cb fun(paths: string[])
function M.find_solutions_from_file(file_path, cb)
  local dir = vim.fs.dirname(file_path)
  if not dir or not uv.fs_stat(dir) then error("Invalid file path: " .. file_path) end

  fs.find_upward_collect_async(absolute(dir), {
    patterns = { "%.sln$", "%.slnx$" },
    stop_at = absolute(vim.fn.getcwd()),
    on_done = cb,
  })
end

return M
