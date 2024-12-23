local has_fzf = pcall(require, "fzf-lua")
local has_telescope = pcall(require, "telescope")

if has_fzf then
  vim.notify("Using fzf-lua")
  return require("easy-dotnet.pickers._fzf")
elseif has_telescope then
  -- if has_telescope then
  return require("easy-dotnet.pickers._telescope")
else
  error("This plugin requires nvim-telescope/telescope.nvim or ibhagwan/fzf-lua")
end

