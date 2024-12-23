local M = {}

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
    if coroutine.status(co) ~= "running" then
      coroutine.resume(co)
    end
  end, title or "", autopick)
  if not selected then
    coroutine.yield()
  end
  return selected
end

M.picker = function(bufnr, options, on_select_cb, title, autopick)
  if autopick == nil then
    autopick = true
  end
  if #options == 0 then
    error("No options provided, minimum 1 is required")
  end

  -- Auto pick if only one option present
  if #options == 1 and autopick == true then
    on_select_cb(options[1])
    return
  end

  -- Prepare the list for fzf-lua
  local fzf_options = {}
  for _, option in ipairs(options) do
    table.insert(fzf_options, option.display) -- Only the display text will be shown
  end

  -- Use fzf-lua to show the picker
  require("fzf-lua").fzf_exec(fzf_options, {
    prompt = title or "Select an option: ", -- The title prompt
    on_select = function(selected_entry)
      -- Find the selected entry based on the display text
      local selected_value = nil
      for _, option in ipairs(options) do
        if option.display == selected_entry then
          selected_value = option
          break
        end
      end
      -- Call the callback with the selected value
      if selected_value then
        on_select_cb(selected_value)
      end
    end,
    fzf_opts = {
      ["--preview"] = "echo {1}", -- Optional preview, can be adjusted as needed
    },
  })
end

return M
