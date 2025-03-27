local M = {}

M.ensure_directory_exists = function(path)
  local uv = vim.loop

  local stat = uv.fs_stat(path)
  if not stat then
    -- Directory doesn't exist, create it
    local success, err = uv.fs_mkdir(path, 511) -- 511 is 0777 in octal
    if not success then print("Failed to create directory: " .. err) end
  elseif stat.type ~= "directory" then
    print(path .. " exists but is not a directory!")
  end
end

M.ensure_json_file_exists = function(filepath)
  local file = io.open(filepath, "r")
  if file then
    -- File exists, close the file
    file:close()
  else
    -- File doesn't exist, create it
    file = io.open(filepath, "w")
    if file == nil then
      print("Failed to create the file: " .. filepath)
      return
    end
    local content = "{}"
    if content then file:write(content) end

    file:close()
  end
end

M.overwrite_file = function(filepath, content)
  local file = io.open(filepath, "w")
  if file == nil then
    print("Failed to create the file: " .. filepath)
    return
  end
  if content then file:write(content) end

  file:close()
end

return M
