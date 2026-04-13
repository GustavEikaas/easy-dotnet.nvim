local M = {}

local icons = {
  [1] = { char = "●", hl = "QfIconError" },
  [2] = { char = "", hl = "QfIconWarn" },
  [3] = { char = "", hl = "QfIconInfo" },
  [4] = { char = "", hl = "QfIconInfo" },
}

local function get_icon(t) return icons[t] or icons[tostring(t) == "W" and 2 or tostring(t) == "I" and 3 or 1] or { char = "·", hl = "QfIconInfo" } end

local function parse_msg(raw)
  local msg = raw:match("%[.-%]%s*(.-)\n") or raw:match("%[.-%]%s*(.+)") or raw
  return msg:gsub("^%s+", ""):gsub("%s+$", "")
end

function M.fmt(info)
  local items = info.quickfix == 1 and vim.fn.getqflist({ id = info.id, items = 0 }).items or vim.fn.getloclist(info.winid, { id = info.id, items = 0 }).items

  if vim.tbl_isempty(items) then return {} end

  local rows = {}
  local w = { path = 0, loc = 0 }

  for i = info.start_idx, info.end_idx do
    local it = items[i]
    local path = vim.fn.fnamemodify(vim.fn.bufname(it.bufnr), ":t")
    local loc = it.col > 0 and (it.lnum .. ":" .. it.col) or tostring(it.lnum)
    local row = {
      icon = get_icon(it.type),
      path = path,
      loc = loc,
      msg = parse_msg(it.text or ""),
    }
    if #path > w.path then w.path = #path end
    if #loc > w.loc then w.loc = #loc end
    rows[#rows + 1] = row
  end

  local fmt = ("%%s  %%-%ds  %%-%ds  %%s"):format(w.path, w.loc)

  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = fmt:format(r.icon.char, r.path, r.loc, r.msg)
  end
  return out
end

function M.get_formatter()
  _G.EasyDotnetMsBuildDiagQfFormatter = M.fmt
  return "v:lua.EasyDotnetMsBuildDiagQfFormatter"
end

return M
