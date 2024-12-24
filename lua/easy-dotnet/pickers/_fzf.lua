local M = {}

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

  local fzf = require("fzf-lua")
  fzf.fzf_exec(options, {
    prompt = title or "> ",
    actions = {
      ["default"] = function(selected)
        on_select_cb(selected[1])
      end,
      ["ctrl-q"] = function()
        -- Close action
      end,
    },
  })
end

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
return M
