local nio = require("nio")
local logger = require("easy-dotnet.logger")

local M = {}

local queue = nio.control.queue()
local started = false

local function trigger_worker()
  if started then return end
  started = true

  nio.run(function()
    while true do
      local job = queue.get()
      local ok, err = pcall(job)
      if not ok then logger.error("Neotest queue error: " .. tostring(err)) end
    end
  end)
end

function M.add(job)
  trigger_worker()
  queue.put(job)
end

return M
