local M = {}

local function find_csproj_for_cs_file(cs_file_path, maxdepth)
  local curr_depth = 0

  local function get_directory(path)
    return vim.fn.fnamemodify(path, ":h")
  end

  local function find_csproj_in_directory(dir)
    local result = vim.fn.globpath(dir, "*.csproj", false, true)
    if #result > 0 then
      return result[1]
    end
    return nil
  end

  local cs_file_dir = vim.fs.dirname(cs_file_path)

  while cs_file_dir ~= "/" and cs_file_dir ~= "~" and cs_file_dir ~= "" and curr_depth < maxdepth do
    curr_depth = curr_depth + 1
    local csproj_file = find_csproj_in_directory(cs_file_dir)
    if csproj_file then
      return csproj_file
    end
    cs_file_dir = get_directory(cs_file_dir)
  end

  return nil
end

local function generate_csharp_namespace(cs_file_path, csproj_path, maxdepth)
  local curr_depth = 0

  local function get_parent_directory(path)
    return vim.fn.fnamemodify(path, ":h")
  end

  local function get_basename_without_ext(path)
    return vim.fn.fnamemodify(path, ":t:r")
  end

  local cs_file_dir = vim.fs.dirname(cs_file_path)
  local csproj_dir = vim.fs.dirname(csproj_path)

  local csproj_basename = get_basename_without_ext(csproj_path)

  local relative_path_parts = {}
  while
    cs_file_dir ~= csproj_dir
    and cs_file_dir ~= "/"
    and cs_file_dir ~= "~"
    and cs_file_dir ~= ""
    and curr_depth < maxdepth
  do
    table.insert(relative_path_parts, 1, vim.fn.fnamemodify(cs_file_dir, ":t"))
    cs_file_dir = get_parent_directory(cs_file_dir)
    curr_depth = curr_depth + 1
  end

  if cs_file_dir ~= csproj_dir then
    return nil, "The .cs file is not located under the .csproj directory."
  end

  table.insert(relative_path_parts, 1, csproj_basename)
  return table.concat(relative_path_parts, ".")
end

local function is_buffer_empty(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for _, line in ipairs(lines) do
    if line ~= "" then
      return false
    end
  end
  return true
end

---@alias BootstrapNamespaceMode "file_scoped" | "block_scoped"

---@param mode BootstrapNamespaceMode
local bootstrap = function(namespace, type_keyword, file_name, mode)
  if mode == "file_scoped" then
    return {
      string.format("namespace %s;", namespace),
      "",
      string.format("public %s %s", type_keyword, file_name),
      "{",
      "",
      "}",
    }
  else
    return {
      string.format("namespace %s", namespace),
      "{",
      string.format("  public %s %s", type_keyword, file_name),
      "  {",
      "",
      "  }",
      "}",
      " ",
    }
  end
end

---@param mode BootstrapNamespaceMode
local function auto_bootstrap_namespace(bufnr, mode)
  local max_depth = 50
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  if not is_buffer_empty(bufnr) then
    return
  end

  local csproject_file_path = find_csproj_for_cs_file(curr_file, max_depth)
  if not csproject_file_path then
    vim.notify("Failed to bootstrap namespace, csproject file not found", vim.log.levels.WARN)
    return
  end
  local namespace = generate_csharp_namespace(curr_file, csproject_file_path, max_depth)
  local file_name = vim.fn.fnamemodify(curr_file, ":t:r")

  local is_interface = file_name:sub(1, 1) == "I" and file_name:sub(2, 2):match("%u")
  local type_keyword = is_interface and "interface" or "class"

  local bootstrap_lines = bootstrap(namespace, type_keyword, file_name, mode)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, bootstrap_lines)
  vim.cmd("w")
end

---@param mode BootstrapNamespaceMode
M.auto_bootstrap_namespace = function(mode)
  vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    pattern = "*.cs",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      auto_bootstrap_namespace(bufnr, mode)
    end,
  })
end

M.add_test_signs = function()
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = "*.cs",
    callback = function()
      require("easy-dotnet.test-signs").add_gutter_test_signs()
    end,
  })
end

return M
