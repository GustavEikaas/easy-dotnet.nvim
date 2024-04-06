local M = {}
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser

---@param term function
M.restore = function(term)
  local project = sln_parse.find_solution_file() or csproj_parse.find_csproj_file()
  require("easy-dotnet.debug").write_to_log(project)
  if project == nil then
    error("Failed to find sln file or csproj file")
  end

  term(project, "restore")
end


return M
