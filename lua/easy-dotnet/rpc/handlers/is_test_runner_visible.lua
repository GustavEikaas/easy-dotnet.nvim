return function(_, response)
  local render = require("easy-dotnet.test-runner.render")
  local buf = render.buf

  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    response(false)
    return
  end

  local tabpage = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      response(true)
      return
    end
  end

  response(false)
end
