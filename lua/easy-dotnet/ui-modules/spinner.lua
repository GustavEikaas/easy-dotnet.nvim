---@class easy-dotnet.Spinner
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
---@return easy-dotnet.Spinner
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
---@param text_provider function | string A function that returns the current text or a static string.
function M:update_spinner(text_provider)
  if self.spinner_timer then
    local current_text = type(text_provider) == "function" and text_provider() or text_provider

    self.notify_id = vim.notify(current_text .. " " .. self.spinner_symbols[self.spinner_index], vim.log.levels.INFO, {
      title = "Progress",
      id = "progress",
      replace = self.notify_id,
    })
    self.spinner_index = (self.spinner_index % #self.spinner_symbols) + 1
  end
end

---Starts the spinner
---@param text_provider function | string
---@param preset "dots"|"arrows"|nil
function M:start_spinner(text_provider, preset)
  self.spinner_symbols = M.spinner_presets[preset] or M.spinner_presets.default

  if not self.spinner_timer then
    self.spinner_timer = vim.loop.new_timer()
    self.spinner_timer:start(0, 300, vim.schedule_wrap(function() self:update_spinner(text_provider) end))
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
