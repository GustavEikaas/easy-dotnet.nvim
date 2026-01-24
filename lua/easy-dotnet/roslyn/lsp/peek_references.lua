---@class easy-dotnet.Roslyn.ReferenceRange
---@field start { line: number, character: number }
---@field end { line: number, character: number }

---@class easy-dotnet.Roslyn.ReferenceItem
---@field filename string The full path to the file
---@field line number The 1-indexed line number
---@field preview string The text preview of the line
---@field range easy-dotnet.Roslyn.ReferenceRange The start and end positions of the reference

---@param client vim.lsp.Client
---@param cb fun(res: easy-dotnet.Roslyn.ReferenceItem[]): nil
local function get_preview_references(client, file_uri, position, bufnr, cb)
  local params = {
    textDocument = { uri = file_uri },
    position = position,
    context = { includeDeclaration = false },
  }

  client:request("textDocument/references", params, function(err, result)
    if err then
      vim.notify("[easy-dotnet] peekReferences error: " .. err.message, vim.log.levels.ERROR)
      return
    end

    if not result or vim.tbl_isempty(result) then
      vim.notify("[easy-dotnet] No references found", vim.log.levels.INFO)
      return
    end

    ---@type easy-dotnet.Roslyn.ReferenceItem[]
    local items = vim
      .iter(result)
      :map(function(ref)
        local uri = ref.uri or ref.targetUri
        if not uri then return nil end

        local fname = vim.uri_to_fname(uri)
        local lnum = ref.range.start.line + 1

        local buf = vim.fn.bufadd(fname)
        vim.fn.bufload(buf)
        local line_text = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""

        return {
          filename = fname,
          line = lnum,
          preview = line_text,
          range = ref.range,
        }
      end)
      :totable()

    cb(items)
  end, bufnr)
end

---@param references easy-dotnet.Roslyn.ReferenceItem[]
local function open_references_float(references)
  local _ = references
  --TODO: render some beatiful UI
end

return function(command, ctx)
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if not client then
    vim.notify("[easy-dotnet] No LSP client for peekReferences", vim.log.levels.ERROR)
    return
  end

  local file_uri = command.arguments[1]
  local pos = command.arguments[2]
  get_preview_references(client, file_uri, pos, ctx.bufnr, open_references_float)
end
