---@class Spinner
local M = {}
M.__index = M

---Spinner symbol presets
M.spinner_presets = {
  default = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
  lines = { "-", "\\", "|", "/" },
  dots = { ".", "..", "...", "...." },
  arrows = { "→", "↘", "↓", "↙", "←", "↖", "↑", "↗" },
}

---Creates a new spinner instance.
---@return Spinner
function M.new()
  ---@class Spinner
  local self = setmetatable({}, M)
  self.spinner_symbols = M.spinner_presets.default ---@type string[] The current spinner symbols
  self.spinner_index = 1 ---@type integer Current index of the spinner symbol
  self.spinner_timer = nil
  self.notify_id = nil ---@type integer|nil Notification ID to replace in vim.notify
  return self
end

---Updates the spinner notification.
---@param pending_text string The text to display while the spinner is running.
function M:update_spinner(pending_text)
  if self.spinner_timer then
    self.notify_id = vim.notify(pending_text .. " " .. self.spinner_symbols[self.spinner_index], vim.log.levels.INFO, {
      title = "Progress",
      id = "progress",
      replace = self.notify_id,
    })
    self.spinner_index = (self.spinner_index % #self.spinner_symbols) + 1
  end
end

---Starts the spinner with a given pending message and optional symbol preset.
---@param pending_text string The message to display while the spinner is running.
---@param preset "dots"|"arrows"|nil Optional spinner symbol preset to use.
function M:start_spinner(pending_text, preset)
  if preset and M.spinner_presets[preset] then
    self.spinner_symbols = M.spinner_presets[preset]
  else
    self.spinner_symbols = M.spinner_presets.default
  end

  if not self.spinner_timer then
    self.spinner_timer = vim.loop.new_timer()
    self.spinner_timer:start(0, 300, vim.schedule_wrap(function() self:update_spinner(pending_text) end))
  end
end

---Stops the spinner and displays the finish message.
---@param finish_text string The message to display when the spinner stops.
---@param level integer | nil One of the values from |vim.log.levels|.
function M:stop_spinner(finish_text, level)
  if not level then level = vim.log.levels.INFO end
  if self.spinner_timer then
    self.spinner_timer:stop()
    self.spinner_timer:close()
    self.spinner_timer = nil
    vim.notify(finish_text, level, {
      title = "Progress",
      id = "progress",
      replace = self.notify_id,
    })
    self.notify_id = nil
  end
end

return M
