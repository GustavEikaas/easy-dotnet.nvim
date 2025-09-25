local M = {}

local function is_buffer_empty(buf)
  for i = 1, vim.api.nvim_buf_line_count(buf), 1 do
    local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
    if line ~= "" and line ~= nil then return false end
  end

  return true
end

---@alias BootstrapNamespaceMode "file_scoped" | "block_scoped"

local function is_key_value_table(tbl)
  if type(tbl) ~= "table" then return false end

  local i = 0
  for k, _ in pairs(tbl) do
    i = i + 1
    if type(k) ~= "number" or k ~= i then return true end
  end

  return false
end

---@param mode BootstrapNamespaceMode
local function auto_bootstrap_namespace(bufnr, mode)
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  if not vim.startswith(vim.fs.normalize(curr_file), vim.fs.normalize(vim.fn.getcwd())) then return end
  if not is_buffer_empty(bufnr) then return end

  local file_name = vim.fn.fnamemodify(curr_file, ":t:r")

  local is_interface = file_name:sub(1, 1) == "I" and file_name:sub(2, 2):match("%u")
  local type_keyword = is_interface and "Interface" or "Class"

  local ns = require("easy-dotnet.constants").ns_id

  vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
    virt_text = { { "⏳ Bootstrapping... (do not modify file)", "Comment" } },
    virt_text_pos = "eol",
  })

  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  local on_finished = function()
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    vim.cmd("checktime")
  end

  local from_json = function(clipboard) client.roslyn:roslyn_bootstrap_file_json(curr_file, clipboard, mode == "file_scoped", on_finished) end
  local default = function() client.roslyn:roslyn_bootstrap_file(curr_file, type_keyword, mode == "file_scoped", on_finished) end

  client:initialize(function()
    local opt = require("easy-dotnet.options").get_option("auto_bootstrap_namespace")
    local clipboard = vim.fn.getreg(opt.use_clipboard_json.register)
    local is_valid_json, res = pcall(vim.fn.json_decode, clipboard)
    local is_table = is_valid_json and (type(res) == "table" and is_key_value_table(res))

    if is_table and opt.use_clipboard_json.behavior == "auto" then
      from_json(clipboard)
    elseif is_table and opt.use_clipboard_json.behavior == "prompt" then
      require("easy-dotnet.picker").picker(nil, { { display = "Yes", value = true }, { display = "No", value = false } }, function(choice)
        if choice.value == true then
          from_json(clipboard)
        else
          default()
        end
      end, "Bootstrap file from json in clipboard?", false, true)
    else
      default()
    end
  end)
end

---@param mode BootstrapNamespaceMode
M.auto_bootstrap_namespace = function(mode)
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
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
    callback = function() require("easy-dotnet.test-signs").add_gutter_test_signs() end,
  })
end

return M
