local M = {}

---@param cb function
M.nuget_search = function(cb)
  require("fzf-lua").fzf_live('dotnet package search <query> --format json | jq ".searchResult | .[] | .packages | .[] | .id"', {
    fn_transform = function(line) return line:gsub('"', ""):gsub("\r", ""):gsub("\n", "") end,
    actions = {
      ["default"] = function(selected)
        local package = selected[1]
        cb(package)
      end,
    },
  })
end

---@generic T
---@param bufnr number | nil
---@param options table<T>
---@param title string | nil
---@return T
M.pick_sync = function(bufnr, options, title, autopick)
  local co = coroutine.running()
  local selected = nil
  M.picker(bufnr, options, function(i)
    selected = i
    if coroutine.status(co) ~= "running" then coroutine.resume(co) end
  end, title or "", autopick)
  if not selected then coroutine.yield() end
  return selected
end

M.picker = function(bufnr, options, on_select_cb, title, autopick)
  if autopick == nil then autopick = true end
  if #options == 0 then error("No options provided, minimum 1 is required") end

  if #options == 1 and autopick == true then
    on_select_cb(options[1])
    return
  end

  local fzf_options = {}
  for _, option in ipairs(options) do
    table.insert(fzf_options, option.display)
  end

  require("fzf-lua").fzf_exec(fzf_options, {
    prompt = title or "Select an option: ",
    actions = {
      ["default"] = function(selected)
        local selected_value = nil
        for _, option in ipairs(options) do
          if option.display == selected[1] then
            selected_value = option
            break
          end
        end
        if selected_value then on_select_cb(selected_value) end
      end,
    },
  })
end

M.migration_picker = function(opts, migration)
  local entry_maker = opts.entry_maker
    or function(entry)
      return {
        display = entry.display or tostring(entry),
        value = entry,
        ordinal = entry.display or tostring(entry),
      }
    end

  local fzf_options = {}
  local fzf_entries = {}
  for _, entry in ipairs(migration) do
    local item = entry_maker(entry)
    table.insert(fzf_options, item.display)
    table.insert(fzf_entries, item)
  end

  require("fzf-lua").fzf_exec(fzf_options, {
    prompt = "Migrations",
    on_select = function(selected_entry)
      local selected_value = nil
      for _, item in ipairs(fzf_entries) do
        if item.display == selected_entry then
          selected_value = item
          break
        end
      end
      if selected_value then opts.on_select(selected_value.value) end
    end,
  })
end

return M
