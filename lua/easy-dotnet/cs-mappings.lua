local M = {}

local function find_csproj_for_cs_file(cs_file_path)
  local function get_directory(path)
    return vim.fn.fnamemodify(path, ":h")
  end

  local function find_csproj_in_directory(dir)
    local result = vim.fn.globpath(dir, "*.csproj", false, true)
    if #result > 0 then
      return result[1] -- Return the first found .csproj file
    end
    return nil
  end

  local cs_file_dir = get_directory(cs_file_path)

  while cs_file_dir ~= "/" and cs_file_dir ~= "" do
    local csproj_file = find_csproj_in_directory(cs_file_dir)
    if csproj_file then
      return csproj_file
    end
    cs_file_dir = get_directory(cs_file_dir)
  end

  return nil
end

local function generate_csharp_namespace(cs_file_path, csproj_path)
  local function get_directory(path)
    return vim.fn.fnamemodify(path, ":h")
  end

  local function get_basename(path)
    return vim.fn.fnamemodify(path, ":t:r")
  end

  local function join_path_parts(parts)
    return table.concat(parts, ".")
  end

  local cs_file_dir = get_directory(cs_file_path)
  local csproj_dir = get_directory(csproj_path)

  local csproj_basename = get_basename(csproj_path)

  local relative_path_parts = {}
  while cs_file_dir ~= csproj_dir and cs_file_dir ~= "/" and cs_file_dir ~= "" do
    table.insert(relative_path_parts, 1, vim.fn.fnamemodify(cs_file_dir, ":t"))
    cs_file_dir = get_directory(cs_file_dir)
  end

  if cs_file_dir ~= csproj_dir then
    return nil, "The .cs file is not located under the .csproj directory."
  end

  table.insert(relative_path_parts, 1, csproj_basename)
  return join_path_parts(relative_path_parts)
end

local function is_buffer_empty(buf)
  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Check if all lines are empty
  for _, line in ipairs(lines) do
    if line ~= "" then
      return false
    end
  end
  return true
end

local function auto_bootstrap_namespace(bufnr)
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  if not is_buffer_empty(bufnr) then
    return
  end

  local csproject_file_path = find_csproj_for_cs_file(curr_file)
  local namespace = generate_csharp_namespace(curr_file, csproject_file_path)
  local file_name = vim.fn.fnamemodify(curr_file, ":t:r")

  local bootstrap_lines = {
    string.format("namespace %s", namespace),
    "{",
    string.format("  public class %s", file_name),
    "  {",
    "",
    "  }",
    "}",
    " "
  }

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, bootstrap_lines)
  vim.cmd("w")
end

M.auto_bootstrap_namespace = function()
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = "*.cs",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      auto_bootstrap_namespace(bufnr)
    end
  })
end

return M
