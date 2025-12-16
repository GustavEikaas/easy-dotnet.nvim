local M = {}

function M.find_csproj_from_file(file_path)
  local matches = vim.fs.find(function(name)
    return name:match("%.csproj$")
  end, {
    path = vim.fs.dirname(file_path),
    upward = true,
    type = "file",
    limit = 1
  })

  if #matches > 0 then
    return matches[1]
  end
  return nil
end

function M.find_solutions_from_file(file_path)
  local dir_path = vim.fs.dirname(file_path)
  local matches = vim.fs.find(function(name)
    return name:match("%.sln$") or name:match("%.slnx$")
  end, {
    path = dir_path,
    upward = true,
    type = "file",
    stop = vim.fs.dirname(vim.fn.getcwd())
  })
  return matches
end

return M
