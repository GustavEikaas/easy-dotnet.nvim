local Window = {}
Window.__index = Window

local function get_default_win_opts()
  local width = math.floor(vim.o.columns / 2) - 2
  local height = 20
  return {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  }
end

local function update_win_opts(win, opts)
  if win == nil then return end
  vim.api.nvim_win_set_config(win, opts)
end

function Window.new_float()
  local self = setmetatable({}, Window)
  self.buf = vim.api.nvim_create_buf(false, true)
  self.opts = get_default_win_opts()
  self.buf_opts = {
    modifiable = false,
    filetype = nil,
  }
  self.callbacks = {}
  return self
end

function Window:buf_set_filetype(filetype)
  if self.buf ~= nil then vim.api.nvim_set_option_value("filetype", filetype, { buf = self.buf }) end

  self.buf_opts.filetype = filetype
  return self
end

function Window:on_win_close(callback)
  if self.win == nil then
    table.insert(self.callbacks, callback)
    return self
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(event)
      if tonumber(event.match) == self.win then callback() end
    end,
  })

  return self
end

local function set_buf_opts(buf, opts)
  vim.api.nvim_set_option_value("filetype", opts.filetype, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", opts.modifiable, { buf = buf })
end

function Window:write_buf(lines)
  vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf })
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  set_buf_opts(self.buf, self.buf_opts)
  return self
end

function Window:close() vim.api.nvim_win_close(self.win, true) end

function Window:pos_left()
  self.opts.col = 1
  update_win_opts(self.win, self.opts)
  return self
end

function Window:pos_right()
  self.opts.col = self.opts.width + 2
  update_win_opts(self.win, self.opts)
  return self
end

function Window:pos_center()
  self.opts.col = math.floor((vim.o.columns - self.opts.width) / 2)
  update_win_opts(self.win, self.opts)
  return self
end

function Window:link_close(float)
  self:on_win_close(function() float:close() end)
  float:on_win_close(function() self:close() end)
  return self
end

function Window:create()
  local win = vim.api.nvim_open_win(self.buf, true, self.opts)
  self.win = win

  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(self.win, true) end, { buffer = self.buf, noremap = true, silent = true })

  set_buf_opts(self.buf, self.buf_opts)

  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(event)
      if tonumber(event.match) == win then
        for _, cb in ipairs(self.callbacks) do
          cb()
        end
      end
    end,
  })
  return self
end

return Window
