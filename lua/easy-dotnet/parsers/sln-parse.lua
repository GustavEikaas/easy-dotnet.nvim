local current_solution = require("easy-dotnet.current_solution")
local M = {}

---@param cb fun(paths: string[])
M.find_project_files = function(cb)
  require("easy-dotnet.fs").find_async(".", {
    match = "%.[cf]sproj$",
    depth = 3,
    on_done = function(paths)
      local normalized = {}
      for _, value in ipairs(paths) do
        table.insert(normalized, vim.fs.normalize(value))
      end
      cb(normalized)
    end,
  })
end

---@param cb fun(paths: string[])
function M.get_solutions(cb)
  require("easy-dotnet.fs").find_async(".", {
    match = "%.slnx?$",
    depth = 2,
    on_done = cb,
  })
end

M.try_get_selected_solution_file = function() return current_solution.try_get_selected_solution() end

return M
