local M = {}

local BOOTSTRAP_DELAY_MS = 250

local function is_buffer_empty(buf)
  for i = 0, vim.api.nvim_buf_line_count(buf) - 1 do
    local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
    if line ~= nil and line ~= "" then return false end
  end
  return true
end

---@alias easy-dotnet.BootstrapNamespaceMode "file_scoped" | "block_scoped"

local function is_key_value_table(tbl)
  if type(tbl) ~= "table" then return false end

  local i = 0
  for k, _ in pairs(tbl) do
    i = i + 1
    if type(k) ~= "number" or k ~= i then return true end
  end

  return false
end

local function is_cs_file(file_path)
  return vim.endswith(file_path, ".cs")
    and not vim.endswith(file_path, ".razor.cs")
    and not vim.endswith(file_path, ".cshtml.cs")
end

---@param mode easy-dotnet.BootstrapNamespaceMode
local function auto_bootstrap_namespace(bufnr, mode)
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  if not vim.startswith(vim.fs.normalize(curr_file), vim.fs.normalize(vim.fn.getcwd())) then return end
  local lsp_created_files = require("easy-dotnet.roslyn.lsp-created-files")
  if lsp_created_files.is_marked_fname(curr_file) then
    -- Roslyn create edits can trigger multiple file events before text edits land.
    if not is_buffer_empty(bufnr) then lsp_created_files.clear_fname(curr_file) end
    return
  end
  if not is_buffer_empty(bufnr) then return end

  local file_name = vim.fn.fnamemodify(curr_file, ":t:r")

  -- Interface detection only applies to plain .cs files
  local is_interface = is_cs_file(curr_file) and file_name:sub(1, 1) == "I" and file_name:sub(2, 2):match("%u")
  local type_keyword = is_interface and "Interface" or "Class"

  local ns = require("easy-dotnet.constants").ns_id

  vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
    virt_text = { { "⏳ Bootstrapping... (do not modify file)", "Comment" } },
    virt_text_pos = "eol",
  })

  local client = require("easy-dotnet.rpc.rpc").global_rpc_client

  local clear_virtual_text = function() vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1) end

  local opts = { on_crash = function(_) clear_virtual_text() end }

  local from_json = function(clipboard) client.roslyn:roslyn_bootstrap_file_json_v2(curr_file, clipboard, mode == "file_scoped", clear_virtual_text, opts) end
  local default = function() client.roslyn:roslyn_bootstrap_file_v2(curr_file, type_keyword, mode == "file_scoped", clear_virtual_text, opts) end

  client:initialize(function()
    -- JSON clipboard bootstrap is only meaningful for plain .cs files
    if not is_cs_file(curr_file) then
      default()
      return
    end

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

---@param mode easy-dotnet.BootstrapNamespaceMode
M.auto_bootstrap_namespace = function(mode)
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    pattern = { "*.cs", "*.razor", "*.cshtml" },
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if vim.b[bufnr].easy_dotnet_bootstrap_namespace_pending then return end

      vim.b[bufnr].easy_dotnet_bootstrap_namespace_pending = true
      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end

        vim.b[bufnr].easy_dotnet_bootstrap_namespace_pending = false
        auto_bootstrap_namespace(bufnr, mode)
      end, BOOTSTRAP_DELAY_MS)
    end,
  })
end

return M
