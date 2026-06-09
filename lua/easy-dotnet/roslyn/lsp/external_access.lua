local M = {}

local state = {
  extension_info = nil,
  activated = {},
  activating = {},
  missing_document_handler_warnings = {},
}

local default_document_message_handlers = {
  "EasyDotnet.RoslynLanguageServices.Rename.ShouldRenameFileMessageHandler",
  "EasyDotnet.RoslynLanguageServices.CreateType.CreateTypeFromUsageMessageHandler",
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

local function document_handler_available(activation, message_name) return contains(activation and activation.document_message_handlers, message_name) end

local function extension_path(info) return info and (info.easyDotnetRoslynLanguageServicesPath or info.EasyDotnetRoslynLanguageServicesPath) end

local function is_already_registered_error(err) return format_error(err):lower():find("already registered", 1, true) ~= nil end

local function registered_activation()
  return {
    workspace_message_handlers = {},
    document_message_handlers = default_document_message_handlers,
  }
end

local function complete_activation(client_id, err, activation)
  if activation then state.activated[client_id] = activation end

  local callbacks = state.activating[client_id] or {}
  state.activating[client_id] = nil

  for _, callback in ipairs(callbacks) do
    callback(err, activation)
  end
end

local function warn_missing_document_handler_once(client, message_name)
  local warning_key = string.format("%d:%s", client.id, message_name)
  if state.missing_document_handler_warnings[warning_key] then return end

  state.missing_document_handler_warnings[warning_key] = true

  local path = extension_path(state.extension_info) or "<unknown>"
  local message = string.format("[easy-dotnet] Roslyn extension did not advertise document handler '%s'. Related enhanced LSP feature will be disabled. Extension: %s", message_name, path)

  logger.warn(message)
end

local function get_extension_info(cb)
  if state.extension_info then
    cb(nil, state.extension_info)
    return
  end

  vim.system({ "dotnet-easydotnet", "roslyn", "extension-info" }, { text = true }, function(result)
    if result.code ~= 0 then
      local stderr = result.stderr or ""
      logger.warn("[easy-dotnet] Failed to resolve Roslyn extension info: " .. (stderr ~= "" and stderr or "exit code " .. tostring(result.code)))
      schedule(cb, stderr ~= "" and stderr or "Failed to resolve EasyDotnet Roslyn extension info")
      return
    end

    local ok, decoded = pcall(vim.json.decode, result.stdout or "")
    if not ok then
      logger.warn("[easy-dotnet] Failed to decode Roslyn extension info: " .. format_error(decoded))
      schedule(cb, decoded)
      return
    end

    local path = extension_path(decoded)
    if type(path) ~= "string" or path == "" then
      logger.warn("[easy-dotnet] Roslyn extension info did not include a language-services path")
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

  if state.activating[client.id] then
    table.insert(state.activating[client.id], cb)
    return
  end

  state.activating[client.id] = { cb }

  get_extension_info(function(info_err, info)
    if info_err then
      complete_activation(client.id, info_err)
      return
    end

    client:request("server/_vs_activateExtension", {
      assemblyFilePath = extension_path(info),
    }, function(err, result)
      if err then
        if is_already_registered_error(err) then
          local activation = registered_activation()
          complete_activation(client.id, nil, activation)
          return
        end

        logger.warn("[easy-dotnet] Roslyn extension activation failed: " .. format_error(err))
        complete_activation(client.id, err)
        return
      end

      if result and result.extensionException then
        if is_already_registered_error(result.extensionException) then
          local activation = registered_activation()
          complete_activation(client.id, nil, activation)
          return
        end

        complete_activation(client.id, result.extensionException)
        return
      end

      local activation = {
        workspace_message_handlers = result and result.workspaceMessageHandlers or {},
        document_message_handlers = result and result.documentMessageHandlers or {},
      }

      complete_activation(client.id, nil, activation)
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

      if not document_handler_available(activation, message_name) then
        warn_missing_document_handler_once(client, message_name)
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
          cb(err)
          return
        end

        if result and result.extensionWasUnloaded and not retried then
          state.activated[client.id] = nil
          dispatch(true)
          return
        end

        if result and result.extensionException then
          cb(result.extensionException)
          return
        end

        if not result or result.response == nil then
          cb(nil, nil)
          return
        end

        local ok, decoded = pcall(vim.json.decode, result.response)
        if not ok then
          cb(decoded)
          return
        end

        cb(nil, decoded)
      end, bufnr)
    end)
  end

  dispatch(false)
end

function M.verify_document_handler(client, message_name)
  activate(client, function(err, activation)
    if err then return end

    if not document_handler_available(activation, message_name) then warn_missing_document_handler_once(client, message_name) end
  end)
end

return M
