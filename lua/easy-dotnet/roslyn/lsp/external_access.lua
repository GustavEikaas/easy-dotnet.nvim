local logger = require("easy-dotnet.logger")

local M = {}

local state = {
  extension_info = nil,
  activated = {},
}

local function contains(values, value)
  for _, candidate in ipairs(values or {}) do
    if candidate == value then return true end
  end
  return false
end

local function schedule(cb, ...)
  local args = { ... }
  vim.schedule(function() cb(unpack(args)) end)
end

local function format_error(err)
  if type(err) == "table" then return err.message or vim.inspect(err) end
  return tostring(err)
end

local function get_extension_info(cb)
  if state.extension_info then
    cb(nil, state.extension_info)
    return
  end

  vim.system({ "dotnet-easydotnet", "roslyn", "extension-info" }, { text = true }, function(result)
    if result.code ~= 0 then
      local stderr = result.stderr or ""
      logger.debug("[easy-dotnet] Failed to resolve Roslyn extension info: " .. (stderr ~= "" and stderr or "exit code " .. tostring(result.code)))
      schedule(cb, stderr ~= "" and stderr or "Failed to resolve EasyDotnet Roslyn extension info")
      return
    end

    local ok, decoded = pcall(vim.json.decode, result.stdout or "")
    if not ok then
      logger.debug("[easy-dotnet] Failed to decode Roslyn extension info: " .. format_error(decoded))
      schedule(cb, decoded)
      return
    end

    local path = decoded.EasyDotnetRoslynLanguageServicesPath
    if type(path) ~= "string" or path == "" then
      logger.debug("[easy-dotnet] Roslyn extension info did not include a language-services path")
      schedule(cb, "EasyDotnet Roslyn extension info did not include a language-services path")
      return
    end

    state.extension_info = decoded
    schedule(cb, nil, decoded)
  end)
end

local function activate(client, cb)
  if state.activated[client.id] then
    cb(nil, state.activated[client.id])
    return
  end

  get_extension_info(function(info_err, info)
    if info_err then
      cb(info_err)
      return
    end

    client:request("server/_vs_activateExtension", {
      assemblyFilePath = info.EasyDotnetRoslynLanguageServicesPath,
    }, function(err, result)
      if err then
        logger.debug("[easy-dotnet] Roslyn extension activation failed: " .. format_error(err))
        cb(err)
        return
      end

      if result and result.extensionException then
        logger.debug("[easy-dotnet] Roslyn extension activation threw: " .. format_error(result.extensionException))
        cb(result.extensionException)
        return
      end

      local activation = {
        workspace_message_handlers = result and result.workspaceMessageHandlers or {},
        document_message_handlers = result and result.documentMessageHandlers or {},
      }

      state.activated[client.id] = activation
      cb(nil, activation)
    end)
  end)
end

function M.dispatch_document(client, bufnr, message_name, message, cb)
  local function dispatch(retried)
    activate(client, function(activation_err, activation)
      if activation_err then
        cb(activation_err)
        return
      end

      if not contains(activation and activation.document_message_handlers, message_name) then
        logger.debug("[easy-dotnet] Roslyn extension document handler unavailable: " .. message_name)
        cb(nil, nil)
        return
      end

      client:request("textDocument/_vs_dipatchExtensionMessage", {
        textDocument = {
          uri = vim.uri_from_bufnr(bufnr),
        },
        messageName = message_name,
        message = vim.json.encode(message),
      }, function(err, result)
        if err then
          logger.debug("[easy-dotnet] Roslyn document extension dispatch failed: " .. format_error(err))
          cb(err)
          return
        end

        if result and result.extensionWasUnloaded and not retried then
          logger.debug("[easy-dotnet] Roslyn extension was unloaded; reactivating and retrying message: " .. message_name)
          state.activated[client.id] = nil
          dispatch(true)
          return
        end

        if result and result.extensionException then
          logger.debug("[easy-dotnet] Roslyn document extension handler threw: " .. format_error(result.extensionException))
          cb(result.extensionException)
          return
        end

        if not result or result.response == nil then
          logger.debug("[easy-dotnet] Roslyn document extension message returned no response: " .. message_name)
          cb(nil, nil)
          return
        end

        local ok, decoded = pcall(vim.json.decode, result.response)
        if not ok then
          logger.debug("[easy-dotnet] Failed to decode Roslyn document extension response: " .. format_error(decoded))
          cb(decoded)
          return
        end

        cb(nil, decoded)
      end, bufnr)
    end)
  end

  dispatch(false)
end

return M
