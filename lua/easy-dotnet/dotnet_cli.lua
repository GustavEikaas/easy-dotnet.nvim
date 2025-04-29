local M = {}

---@param source string source project file path
---@param target string target project file path
---@return string
function M.add_project(source, target) return string.format("dotnet add %s reference %s", source, target) end

--- `dotnet package search <QUERY> [--take <NUMBER>] [--format <FORMAT>] [--exact-match]`
--- Search for nuget packages meeting the search term.
---@param query string search term
---@param is_json boolean | nil
---@param exact boolean | nil
---@param take number | nil
function M.package_search(query, is_json, exact, take)
  local take_query = take ~= nil and string.format("--take %s", take) or ""
  local json_query = is_json and "--format json" or ""
  local exact_query = exact and "--exact-match" or ""
  return string.format("dotnet package search %s %s %s %s", query, take_query, json_query, exact_query)
end

function M.list_projects(sln_file_path) return string.format("dotnet sln %s list", sln_file_path) end

return M
