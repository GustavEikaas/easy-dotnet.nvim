local M = {}

local files = {}

local function normalize(fname) return vim.fs.normalize(fname) end

function M.mark_uri(uri)
  if type(uri) ~= "string" then return end
  files[normalize(vim.uri_to_fname(uri))] = true
end

function M.is_marked_fname(fname)
  if type(fname) ~= "string" or fname == "" then return false end
  return files[normalize(fname)] == true
end

function M.clear_fname(fname)
  if type(fname) ~= "string" or fname == "" then return end
  files[normalize(fname)] = nil
end

return M
