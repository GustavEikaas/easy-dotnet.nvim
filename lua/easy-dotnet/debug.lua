local M = {}

M.write_to_log = function(message)
  --TODO: constants.get_data_dir
  local log_path = vim.fn.stdpath("data") .. "/easy-dotnet-log.txt"
  -- Open the file in append mode
  local file, err = vim.loop.fs_open(log_path, "a", 438) -- 438 is the octal value for file permissions 0666

  if err then
    print("Error opening file: " .. err)
    return
  end

  -- Write the message to the file
  if type(message) == "table" then
    vim.loop.fs_write(file, M.table_to_string(message) .. "\n", -1)
  elseif type(message) == "string" then
    vim.loop.fs_write(file, message .. "\n", -1)
  else
    error("Failed to write to log, datatype: " .. type(message) .. " not supported")
  end

  -- Close the file
  vim.loop.fs_close(file)
end

M.table_to_string = function(tbl, indent)
  if not indent then indent = 0 end
  local str = ""
  for k, v in pairs(tbl) do
    local key = tostring(k)
    if type(v) == "table" then
      str = str .. string.rep(" ", indent) .. key .. ":\n" .. M.table_to_string(v, indent + 2)
    else
      str = str .. string.rep(" ", indent) .. key .. ": " .. tostring(v) .. "\n"
    end
  end
  return str
end

return M
