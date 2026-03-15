local M = {}
local logger = require("easy-dotnet.logger")
local parsers = require("easy-dotnet.parsers")
local sln_parse = parsers.sln_parser

function M.assert_ts_parser()
  local ok = pcall(vim.treesitter.get_parser, 0, "c_sharp")
  if not ok then
    logger.error("generate-test requires nvim-treesitter with the c_sharp parser. Run :TSInstall c_sharp")
    return false
  end
  return true
end

local restricted_modifiers = { private = true, protected = true }

---@return string | nil method_name
---@return string | nil class_name
---@return string | nil restricted_modifier e.g. "private" or "protected", nil if freely testable
function M.get_method_context_at_cursor()
  local parser = vim.treesitter.get_parser(0, "c_sharp")
  if parser == nil then return nil, nil, nil end

  local root = parser:parse()[1]:root()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local node = root:named_descendant_for_range(row - 1, col, row - 1, col)

  local method_name = nil
  local class_name = nil
  local restricted_modifier = nil

  local current = node
  while current do
    if current:type() == "method_declaration" then
      for child in current:iter_children() do
        if child:type() == "modifier" then
          local modifier = vim.treesitter.get_node_text(child, 0)
          if restricted_modifiers[modifier] then restricted_modifier = modifier end
        end
        if child:type() == "identifier" and method_name == nil then
          method_name = vim.treesitter.get_node_text(child, 0)
        end
      end
      break
    end
    current = current:parent()
  end

  if method_name == nil then return nil, nil, nil end

  current = node
  while current do
    if current:type() == "class_declaration" then
      for child in current:iter_children() do
        if child:type() == "identifier" then
          class_name = vim.treesitter.get_node_text(child, 0)
          break
        end
      end
      break
    end
    current = current:parent()
  end

  return method_name, class_name, restricted_modifier
end

---@param sln_path string
---@param source_file string
---@return easy-dotnet.Project.Project | nil
function M.get_source_project(sln_path, source_file)
  local source_file_norm = vim.fs.normalize(source_file)
  for _, p in ipairs(sln_parse.get_projects_from_sln(sln_path)) do
    local proj_dir = vim.fs.normalize(vim.fs.dirname(p.path))
    if source_file_norm:sub(1, #proj_dir) == proj_dir then
      return p
    end
  end
  return nil
end

---Returns test projects sorted by relevance to the source project name.
---@param sln_path string
---@param source_project_name string
---@return easy-dotnet.Project.Project[]
function M.get_test_projects(sln_path, source_project_name)
  local test_projects = sln_parse.get_projects_from_sln(sln_path, function(p) return p.isTestProject end)
  table.sort(test_projects, function(a, _)
    return a.name:lower():find(source_project_name:lower(), 1, true) ~= nil
  end)
  return test_projects
end

---@param csproj_path string
---@return string "xunit" | "nunit" | "mstest" | "unknown"
function M.detect_test_framework(csproj_path)
  local content = table.concat(vim.fn.readfile(csproj_path), "\n"):lower()
  if content:find("xunit") then return "xunit" end
  if content:find("nunit") then return "nunit" end
  if content:find("mstest") or content:find("microsoft.visualstudio.testtools") then return "mstest" end
  return "unknown"
end

---@param source_file string
---@param source_project_path string
---@param test_project_path string
---@param class_name string
---@return string
function M.derive_test_file_path(source_file, source_project_path, test_project_path, class_name)
  local source_dir = vim.fs.normalize(vim.fs.dirname(source_project_path))
  local test_dir = vim.fs.normalize(vim.fs.dirname(test_project_path))
  local relative = vim.fs.normalize(source_file):sub(#source_dir + 2)
  local subdir = vim.fs.dirname(relative)

  if subdir == nil or subdir == "." then
    return vim.fs.joinpath(test_dir, class_name .. "Tests.cs")
  end
  return vim.fs.joinpath(test_dir, subdir, class_name .. "Tests.cs")
end

---@param source_file string
---@param source_project_path string
---@param test_project_path string
---@return string
function M.derive_test_namespace(source_file, source_project_path, test_project_path)
  local test_project_name = vim.fn.fnamemodify(test_project_path, ":t:r")
  local source_dir = vim.fs.normalize(vim.fs.dirname(source_project_path))
  local relative = vim.fs.normalize(source_file):sub(#source_dir + 2)
  local subdir = vim.fs.dirname(relative)

  if subdir == nil or subdir == "." then return test_project_name end
  return test_project_name .. "." .. subdir:gsub("/", "."):gsub("\\", ".")
end

return M
