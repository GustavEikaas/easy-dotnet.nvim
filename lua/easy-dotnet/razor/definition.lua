local M = {}

local component_cache = {}

local function uri_to_bufnr(uri)
  if type(uri) ~= "string" then return nil end
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) and vim.uri_from_bufnr(bufnr) == uri then return bufnr end
  end
  return nil
end

local function lsp_character_to_byte(line, character)
  if vim.str_byteindex then
    local ok, byte = pcall(vim.str_byteindex, line, "utf-16", character, false)
    if ok and byte then return byte + 1 end
  end
  return character + 1
end

local function component_name_at_position(bufnr, position)
  if not (bufnr and position and position.line and position.character) then return nil end

  local line = vim.api.nvim_buf_get_lines(bufnr, position.line, position.line + 1, false)[1]
  if not line then return nil end

  local cursor = lsp_character_to_byte(line, position.character)
  local prefix = line:sub(1, cursor)
  local tag_start = prefix:match("^.*()<")
  if not tag_start then return nil end

  local tag = line:sub(tag_start)
  local slash, name_start, name = tag:match("^<(/?)()([%a_][%w_%.]*)")
  if not name then return nil end
  if slash ~= "" and slash ~= "/" then return nil end

  local start_col = tag_start + name_start - 2
  local end_col = start_col + #name
  if cursor < start_col or cursor > end_col + 1 then return nil end
  if not name:match("^[A-Z]") then return nil end

  return name:match("([%w_]+)$")
end

local function find_component_file(root_dir, component_name)
  if not (root_dir and component_name) then return nil end
  component_cache[root_dir] = component_cache[root_dir] or {}
  local by_name = component_cache[root_dir]
  if by_name[component_name] ~= nil then return by_name[component_name] or nil end

  local files = vim.fs.find(component_name .. ".razor", {
    path = root_dir,
    upward = false,
    limit = 1,
  })

  by_name[component_name] = files[1] or false
  return files[1]
end

local function location_for_file(file)
  return {
    uri = vim.uri_from_fname(file),
    range = {
      start = { line = 0, character = 0 },
      ["end"] = { line = 0, character = 0 },
    },
  }
end

function M.resolve(root_dir, params)
  local uri = vim.tbl_get(params or {}, "textDocument", "uri")
  local bufnr = uri_to_bufnr(uri)
  if not bufnr then return nil end

  local component_name = component_name_at_position(bufnr, params.position)
  if not component_name then return nil end

  local file = find_component_file(root_dir, component_name)
  if not file then return {} end

  return { location_for_file(file) }
end

function M.clear_cache(root_dir)
  if root_dir then
    component_cache[root_dir] = nil
  else
    component_cache = {}
  end
end

return M
