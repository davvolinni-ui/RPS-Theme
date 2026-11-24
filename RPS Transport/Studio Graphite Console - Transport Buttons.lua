-- @noindex
local r = reaper
local mode = ...
local title = "Studio Graphite Console - Transport Buttons"
local settings = "StudioGraphiteConsole.Transport"
local themeName = "studio graphite console"
local footerFilename = "Studio Graphite Console - Mixer Folder Footer.lua"
local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptFolder = scriptPath:match("^(.*[/\\])") or ""

local mixerAnnex = {key = "Annex", label = "Folder Annex", renderer = footerFilename, parameter = "mcpFolderFooter"}
local tcpAnnex = {
  key = "TcpAnnex", label = "TCP Folder Annex",
  action = "Studio Graphite Console - Toggle TCP Folder Annex.lua",
  renderer = "Studio Graphite Console - TCP Folder Annex Renderer.lua", parameter = "tcpFolderAnnex",
}
local buttons = {
  {key = "Browse", label = "ReaBrowse", app = true, file = "ReaBrowse.lua", native = 50124, nativeLabel = "Media Explorer"},
  {key = "Drum", label = "ReaDrumXT", app = true, file = "ReaDrum.lua"},
  {key = "Spect", label = "ReaSpect", app = true, file = "ReaSpect.lua"},
  {key = "Roll", label = "ReaRoll", app = true, file = "ReaRoll.lua", native = 40153, nativeLabel = "MIDI editor (selected MIDI item)"},
  mixerAnnex,
  {key = "Mixer", label = "Mixer", command = 40078},
  tcpAnnex,
}

local dockerButtons = {
  {key = "DockerLeft", label = "Left docker", file = "Toggle show left docker.lua"},
  {key = "DockerBottom", label = "Bottom docker", file = "Toggle show bottom docker.lua"},
  {key = "DockerRight", label = "Right docker", file = "Toggle show right docker.lua"},
}
local quantizeButton = {key = "Quantize", label = "Input Quantize", filename = "Studio Graphite Console - Input Quantize.lua"}
local optionalButtons = {quantizeButton, table.unpack(dockerButtons)}

local function usingTheme()
  local filename = (r.GetLastColorThemeFile() or ""):match("[^/\\]+$")
  if not filename then return false end
  filename = filename:lower()
  return filename == themeName .. ".reapertheme" or filename == themeName .. ".reaperthemezip"
end

local function parameters()
  local indices = {}
  local index = 0
  while true do
    local key = r.ThemeLayout_GetParameter(index)
    if not key or key == "" then return indices end
    indices[key] = index
    index = index + 1
  end
end

local function resolve(text)
  if text:match("^%d+$") then
    local n = tonumber(text)
    if n and n > 0 and n <= 2147483647 then return n end
  elseif text:match("^_[%w_]+$") then
    return r.NamedCommandLookup(text)
  end
  return 0
end

local function override(button)
  return r.GetExtState(settings, "command_" .. button.key)
end

local function checkedOverride(text)
  local command = resolve(text)
  local description = command > 0 and r.kbd_getTextFromCmd(command, 0)
  if not description or description == "" then
    return nil, "Enter a valid command ID from the main Actions list."
  end
  return command
end

local launcher = assert(loadfile(scriptFolder .. "lib/app_launcher.lua"))()

local function defaultBinding(button)
  if button.file and not button.app then
    local found, problem = launcher.discover(r, button)
    if found then return found.id end
    return nil, problem or ("Install FeedTheCat's " .. button.file ..
      " or enter a Custom command."), not problem
  end
  local names = {Browse = "Open ReaBrowse", Drum = "Open ReaDrumXT", Spect = "Open ReaSpect",
    Roll = "Open ReaRoll", Annex = "Toggle Folder Annex", TcpAnnex = "Toggle TCP Folder Annex",
    Mixer = "Toggle Mixer", Settings = "Transport Buttons"}
  local path = scriptFolder .. (button == quantizeButton and button.filename or
    "Studio Graphite Console - " .. names[button.key] .. ".lua")
  local command = r.AddRemoveReaScript(true, 0, path, true)
  if not command or command == 0 then return nil, "Could not register " .. path end
  local named = r.ReverseNamedCommandLookup(command)
  if not named or named == "" then return nil, "Could not resolve the default action." end
  return named:sub(1, 1) == "_" and named or "_" .. named
end

local function validateBinding(button, text, choice)
  local normalized = text:match("^%s*(.-)%s*$")
  local command, message = checkedOverride(normalized)
  if not command then return nil, button.label .. ". " .. message end
  -- Persist named IDs for scripts and custom actions, which can have different numeric IDs.
  local named = r.ReverseNamedCommandLookup(command)
  if named and named ~= "" then normalized = named:sub(1, 1) == "_" and named or "_" .. named end
  return {key = button.key, id = normalized, choice = choice}
end

local function recoverBinding(button)
  local key = button.key
  local saved = r.GetExtState(settings, "binding_" .. key)
  local choice = r.GetExtState(settings, "choice_" .. key)
  if checkedOverride(saved) then
    return validateBinding(button, saved, choice == "Custom" and "Custom" or "Default")
  end
  if choice == "Custom" then
    return nil, button.label .. ". Reassign its Custom action under Advanced."
  end
  local id, problem = defaultBinding(button)
  if not id then return nil, problem end
  return validateBinding(button, id, "Default")
end

local function rememberBinding(entry)
  local key = entry.key
  r.SetExtState(settings, "choice_" .. key, entry.choice, true)
  r.DeleteExtState(settings, "command_" .. key, true)
  r.SetExtState(settings, "binding_" .. key, entry.id, true)
end

local function parameterValue(index)
  local _, _, current = r.ThemeLayout_GetParameter(index)
  return current
end

local function requestGridboxAlignment(indices, onReapplied)
  local ok, message = pcall(function()
    local placement = dofile(scriptFolder .. "lib/gridbox_placement.lua")
    return placement.apply(r, function(key) return parameterValue(indices[key]) end, onReapplied)
  end)
  if ok then return message end
  return "Gridbox alignment failed. " .. tostring(message)
end

local function alignVisibleGridbox(indices)
  if indices.sgcIQGridbox and indices.sgcInputQuantizeVisible and parameterValue(indices.sgcIQGridbox) == 1
      and parameterValue(indices.sgcInputQuantizeVisible) == 1 then
    return requestGridboxAlignment(indices)
  end
end

local function enabledOptionalButtons(indices)
  local enabled = {}
  for _, button in ipairs(optionalButtons) do
    local name = button == quantizeButton and "sgcInputQuantizeVisible" or "sgc" .. button.key .. "Visible"
    if indices[name] and parameterValue(indices[name]) == 1 then enabled[#enabled + 1] = button end
  end
  return enabled
end

local function reloadTransportTheme(path, indices)
  local saved = {}
  for key, index in pairs(indices) do saved[key] = parameterValue(index) end
  if r.OpenColorThemeFile(path) == false then return end
  local updated = parameters()
  local refresh = false
  for key, current in pairs(saved) do
    local index = updated[key]
    if index and parameterValue(index) ~= current then
      -- Preserve live overrides without turning them into theme defaults.
      r.ThemeLayout_SetParameter(index, current, false)
      refresh = true
    end
  end
  if refresh then r.ThemeLayout_RefreshAll() end
  return updated
end

local function initializeOptionalButtons()
  if not usingTheme() or r.GetPlayState() & 5 ~= 0 then return end
  local indices = parameters()
  local enabled = enabledOptionalButtons(indices)
  if #enabled == 0 then return end

  local theme = r.GetLastColorThemeFile()
  if not r.file_exists(theme) and r.file_exists(theme .. "Zip") then theme = theme .. "Zip" end
  local bindings = dofile(scriptFolder .. "lib/theme_bindings.lua")
  local keys = {}
  for _, button in ipairs(enabled) do keys[#keys + 1] = button.key end
  local assigned = bindings.readAll(theme, keys)
  local commands, recovered = {}, {}
  local needsReload = false
  for _, button in ipairs(enabled) do
    if checkedOverride(assigned[button.key] or "") then
      needsReload = true
    else
      local entry = recoverBinding(button)
      if entry then
        commands[entry.key] = entry.id
        recovered[#recovered + 1] = entry
      end
    end
  end
  if #recovered > 0 then
    local path = bindings.applyAll(theme, commands)
    if path then
      for _, entry in ipairs(recovered) do rememberBinding(entry) end
      theme, needsReload = path, true
    end
  end
  -- Re-read the transport's custom actions after REAPER has loaded the local Action List.
  if needsReload then
    local updated = reloadTransportTheme(theme, indices)
    if updated then alignVisibleGridbox(updated) end
  end
end

local function openApp(button)
  local ok, message = launcher.open(r, button, settings)
  if not ok then r.MB(message, title, 0) end
end

local function openMixer(button)
  local window = usingTheme() and r.BR_Win32_GetMixerHwnd and r.BR_Win32_GetMixerHwnd()
  if window and r.DockIsChildOfDock and r.DockWindowActivate then
    local dock = r.DockIsChildOfDock(window)
    if dock and dock >= 0 then
      r.DockWindowActivate(window)
      return
    end
  end
  r.Main_OnCommand(button.command, 0)
end

local function registeredCommand(filename)
  local resource = r.GetResourcePath()
  local registrations = io.open(resource .. "/reaper-kb.ini", "r")
  if not registrations then return 0 end

  local ignoreCase = r.GetOS():match("^Win")
  local function normalize(path)
    path = path:gsub("\\", "/")
    return ignoreCase and path:lower() or path
  end

  -- ReaPack puts the footer beside these scripts. In the development tree it is one level up.
  local folder = normalize(scriptPath):match("^(.*)/[^/]+$")
  local sibling = folder and normalize(folder .. "/" .. filename)
  local parent = folder and folder:match("^(.*)/[^/]+$")
  local development = parent and normalize(parent .. "/" .. filename)
  local command = 0
  for line in registrations:lines() do
    local id, path = line:match('^SCR%s+%d+%s+0%s+(RS%x+)%s+"[^"]+"%s+(.+)$')
    if id then
      path = normalize(path:gsub("%s+$", ""):gsub('^"(.*)"$', "%1"))
      if not path:match("^%a:/") and not path:match("^/") then
        path = normalize(resource .. "/Scripts/" .. path)
      end
      if path == sibling or path == development then
        local registered = r.NamedCommandLookup("_" .. id)
        if registered > 0 then
          command = registered
          if path == sibling then break end
        end
      end
    end
  end
  registrations:close()
  return command
end

local function annexCommand(button)
  local command = registeredCommand(button.renderer)
  if command > 0 then return command end
  local path = scriptFolder .. button.renderer
  if button == mixerAnnex and not r.file_exists(path) then path = scriptFolder .. "../" .. button.renderer end
  if not r.file_exists(path) then return 0 end
  return r.AddRemoveReaScript(true, 0, path, true)
end

local function annexRunning(command)
  return r.GetToggleCommandStateEx(0, command) == 1
end

local function toggleAnnex(button)
  local command = annexCommand(button)
  if command == 0 then
    r.MB("Reinstall the companion scripts for " .. button.label .. ".", title, 0)
    return
  end
  local wasRunning = annexRunning(command)
  r.Main_OnCommand(command, 0)
  local running = annexRunning(command)
  if running ~= wasRunning then
    r.SetExtState(settings, "annex_" .. button.key, running and "1" or "0", true)
  end
end

local function restoreAnnexes()
  if not usingTheme() or not (r.JS_Composite and r.JS_LICE_CreateBitmap and r.JS_Window_InvalidateRect) then return end
  local indices
  for _, button in ipairs({mixerAnnex, tcpAnnex}) do
    if r.GetExtState(settings, "annex_" .. button.key) == "1" and (button == tcpAnnex or r.BR_Win32_GetMixerHwnd) then
      indices = indices or parameters()
      if indices[button.parameter] then
        local command = annexCommand(button)
        if command > 0 and not annexRunning(command) then r.Main_OnCommand(command, 0) end
      end
    end
  end
end

local function renderTcpAnnex()
  local render = loadfile(scriptFolder .. footerFilename)
  if not render then render = assert(loadfile(scriptFolder .. "../" .. footerFilename)) end
  render("tcp", registeredCommand(tcpAnnex.action))
end

local function runButton(button)
  local custom = override(button)
  if custom ~= "" then
    local command, message = checkedOverride(custom)
    if command then r.Main_OnCommand(command, 0) else r.MB(message, title, 0) end
  elseif button.app then
    openApp(button)
  elseif button.key == "Mixer" then
    openMixer(button)
  elseif button.renderer then
    toggleAnnex(button)
  end
end

local function openSettings()
  if not r.ImGui_GetBuiltinPath then
    r.MB("The transport settings require ReaImGui.", title, 0)
    return
  end
  local indices = parameters()
  if not (usingTheme() and indices.rpsTransPlacement and indices.rpsTransTooltips) then
    r.MB("Select the updated Studio Graphite Console theme first.", title, 0)
    return
  end

  package.path = r.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
  local I = require("imgui")("0.10")
  local ctx = I.CreateContext(title)
  local bindings = assert(loadfile(scriptFolder .. "lib/theme_bindings.lua"))()
  local appearance = assert(loadfile(scriptFolder .. "lib/theme_appearance.lua"))()
  local configurable = {}
  for _, button in ipairs(buttons) do
    if button.key ~= "TcpAnnex" or indices.rpsTransTcpAnnex then configurable[#configurable + 1] = button end
  end
  configurable[#configurable + 1] = {key = "Settings", label = "Settings"}
  for _, button in ipairs(dockerButtons) do
    if indices["sgc" .. button.key .. "Visible"] then configurable[#configurable + 1] = button end
  end
  if r.set_action_options then r.set_action_options(1) end
  local keys = {}
  for _, button in ipairs(configurable) do keys[#keys + 1] = button.key end
  if indices.sgcInputQuantizeVisible then keys[#keys + 1] = quantizeButton.key end
  local assigned = bindings.readAll(r.GetLastColorThemeFile(), keys)
  local drafts = {}
  local choices = {}
  for _, button in ipairs(configurable) do
    local key = button.key
    drafts[key] = assigned[key] or ""
    if drafts[key] == "0" then drafts[key] = "" end
    local saved = r.GetExtState(settings, "choice_" .. key)
    local command = resolve(drafts[key])
    local description = command > 0 and r.kbd_getTextFromCmd(command, 0) or ""
    local savedBinding = r.GetExtState(settings, "binding_" .. key)
    if command > 0 and drafts[key] == savedBinding and
        (saved == "Default" or saved == "Custom" or (saved == "Native" and button.native)) then
      choices[key] = saved
    elseif button.native and command == button.native then
      choices[key] = "Native"
    elseif description == "" or description:find("Studio Graphite Console - ", 1, true) or command == button.command then
      choices[key] = "Default"
    else
      choices[key] = "Custom"
    end
  end

  local pendingReload, failedReload, bindingNote, optionalNote
  local function queueReload(path, notify)
    pendingReload = {path = path, notify = notify}
  end

  local function saveBindings(entries, message, showStatus)
    local commands = {}
    for _, entry in ipairs(entries) do commands[entry.key] = entry.id end
    local path, changed = bindings.applyAll(r.GetLastColorThemeFile(), commands)
    if not path then return false, changed end
    for _, entry in ipairs(entries) do
      local key = entry.key
      choices[key], drafts[key], assigned[key] = entry.choice, entry.id, entry.id
      rememberBinding(entry)
    end
    if changed or failedReload == path then
      queueReload(path, function(success)
        if success then showStatus(message)
        else showStatus("Saved. REAPER could not reload the theme. Apply again to retry.") end
      end)
    else
      showStatus(message)
    end
    return true
  end

  local function applyOptional(button)
    if checkedOverride(assigned[button.key] or "") then return true end
    local entry, errorText = recoverBinding(button)
    if not entry then return false, errorText end
    return saveBindings({entry}, nil, function(note) optionalNote = note or optionalNote end)
  end

  local function applyChoices(selected, all)
    local entries, unavailable = {}, 0
    for _, button in ipairs(selected) do
      local choice = choices[button.key]
      local id, problem, missing
      if choice == "Custom" then id = drafts[button.key]
      elseif choice == "Native" then id = tostring(button.native)
      else id, problem, missing = defaultBinding(button) end
      if id then
        local entry, errorText = validateBinding(button, id, choice)
        if not entry then bindingNote = errorText; return end
        entries[#entries + 1] = entry
      elseif all and missing then
        unavailable = unavailable + 1
      else
        bindingNote = problem
        return
      end
    end
    local message = all and ("Applied " .. #entries .. " bindings.") or ("Applied " .. selected[1].label .. ".")
    if unavailable > 0 then message = message .. " Unavailable docker actions: " .. unavailable .. "." end
    local ok, problem = saveBindings(entries, message, function(note) bindingNote = note end)
    if not ok then bindingNote = problem end
  end

  local function value(key)
    return parameterValue(indices[key])
  end

  local function alignGridbox()
    optionalNote = requestGridboxAlignment(indices, function(message) optionalNote = message end)
  end

  local function updateGridboxAlignment()
    optionalNote = alignVisibleGridbox(indices) or optionalNote
  end

  local function reloadTheme()
    local request = pendingReload
    pendingReload = nil
    local updated = reloadTransportTheme(request.path, indices)
    if not updated then
      failedReload = request.path
      request.notify(false)
      return
    end
    failedReload = nil
    indices = updated
    request.notify(true)
    updateGridboxAlignment()
  end

  local appearanceLoaded, appearanceError, appearanceNote
  local grid, meter, interlaced
  local savedGrid, savedMeter, savedInterlaced
  local function drawAppearance()
    if not appearanceLoaded then
      appearanceLoaded = true
      local ok, brightness, color, useInterlacing = appearance.read(r.GetLastColorThemeFile())
      if ok then
        grid, meter, savedGrid, savedMeter = brightness, color, brightness, color
        interlaced, savedInterlaced = useInterlacing, useInterlacing
      else
        appearanceError = brightness
      end
    end
    if appearanceError then
      I.TextWrapped(ctx, appearanceError)
      return
    end

    I.SetNextItemWidth(ctx, 175)
    local _, brightness = I.SliderInt(ctx, "Arrange grid brightness", grid,
      appearance.minGrid, appearance.maxGrid, "%d%%", I.SliderFlags_AlwaysClamp)
    if I.IsItemClicked(ctx, I.MouseButton_Right) then brightness = appearance.defaultGrid end
    I.SetItemTooltip(ctx, "Right-click to reset grid brightness.")

    I.SetNextItemWidth(ctx, 175)
    local _, color = I.ColorEdit3(ctx, "Base meter color", meter, I.ColorEditFlags_DisplayHex | I.ColorEditFlags_NoOptions)
    if I.IsItemClicked(ctx, I.MouseButton_Right) then color = appearance.defaultMeter end
    I.SetItemTooltip(ctx, "Right-click to reset the base meter color.")

    local _, useInterlacing = I.Checkbox(ctx, "Interlaced meters", interlaced)
    if brightness ~= grid or color ~= meter or useInterlacing ~= interlaced then
      grid, meter, interlaced, appearanceNote = brightness, color, useInterlacing, nil
    end
    I.TextWrapped(ctx, "Amber and clip colors are fixed. Apply saves your changes and refreshes the theme.")

    I.BeginDisabled(ctx, grid == savedGrid and meter == savedMeter and interlaced == savedInterlaced and not failedReload)
    if I.Button(ctx, "Apply") then
      local path, changed = appearance.apply(r.GetLastColorThemeFile(), grid, meter, interlaced)
      if not path then
        appearanceNote = changed
      else
        savedGrid, savedMeter, savedInterlaced = grid, meter, interlaced
        appearanceNote = "Appearance saved."
        if changed or failedReload == path then
          queueReload(path, function(success)
            appearanceNote = success and "Appearance applied." or
              "Saved, but REAPER could not reload the theme. Apply again to retry."
          end)
        end
      end
    end
    I.EndDisabled(ctx)
    I.SameLine(ctx)
    if I.Button(ctx, "Restore defaults") then
      grid, meter, interlaced = appearance.defaultGrid, appearance.defaultMeter, appearance.defaultInterlaced
      appearanceNote = nil
    end
    if appearanceNote then I.TextWrapped(ctx, appearanceNote) end
  end

  local function drawTransport()
    local changedAny = false
    local function save(key, nextValue)
      r.ThemeLayout_SetParameter(indices[key], nextValue, true)
      changedAny = true
    end
    I.SetNextItemWidth(ctx, 140)
    local changed, placement = I.Combo(ctx, "RPS button placement", value("rpsTransPlacement"),
      "Auto\0Left\0Right\0Far Left\0Far Right\0")
    if changed then save("rpsTransPlacement", placement) end
    local tipsChanged, tips = I.Checkbox(ctx, "Show transport button tooltips", value("rpsTransTooltips") == 1)
    if tipsChanged then save("rpsTransTooltips", tips and 1 or 0) end

    I.Separator(ctx)
    I.Text(ctx, "Show on transport")
    for _, button in ipairs(buttons) do
      local key = "rpsTrans" .. button.key
      if indices[key] then
        local changedButton, shown = I.Checkbox(ctx, button.label, value(key) == 1)
        if changedButton then save(key, shown and 1 or 0) end
      end
    end

    if indices.sgcInputQuantizeVisible then
      local changedQuantize, shown = I.Checkbox(ctx, "Input Quantize (iQ)", value("sgcInputQuantizeVisible") == 1)
      if changedQuantize then
        optionalNote = nil
        local ready, message = true
        if shown then ready, message = applyOptional(quantizeButton) end
        if ready then
          save("sgcInputQuantizeVisible", shown and 1 or 0)
        else
          optionalNote = message
        end
      end
      local _, quantizeActive = r.GetProjExtState(0, "StudioGraphiteConsole.InputQuantize", "active")
      if quantizeActive == "1" then
        I.SameLine(ctx)
        if I.Button(ctx, "Turn iQ off") then
          local action, problem = loadfile(scriptFolder .. quantizeButton.filename)
          if action then action("off") else optionalNote = problem end
        end
      end
    end
    if indices.sgcIQPlacement then
      local current = value("sgcIQPlacement")
      local side = current == 0 and 0 or current == 3 and 2 or 1
      I.SetNextItemWidth(ctx, 140)
      local moved, placement = I.Combo(ctx, "iQ placement", side, "Transport\0Left\0Right\0")
      if moved then save("sgcIQPlacement", placement == 0 and 0 or placement + 1) end
    end
    if indices.sgcIQGridbox then
      local changedAlignment, aligned = I.Checkbox(ctx, "Align Gridbox with iQ", value("sgcIQGridbox") == 1)
      if changedAlignment then save("sgcIQGridbox", aligned and 1 or 0) end
      if aligned and value("sgcInputQuantizeVisible") == 1 then
        I.SameLine(ctx)
        if I.Button(ctx, "Realign") then alignGridbox() end
      end
    end
    for _, button in ipairs(dockerButtons) do
      local key = "sgc" .. button.key .. "Visible"
      if indices[key] then
        local changedDocker, shown = I.Checkbox(ctx, button.label, value(key) == 1)
        if changedDocker then
          optionalNote = nil
          local ready, message = true
          if shown then ready, message = applyOptional(button) end
          if ready then
            save(key, shown and 1 or 0)
          else
            optionalNote = message
          end
        end
      end
    end
    if indices.sgcDockerPlacement then
      I.SetNextItemWidth(ctx, 140)
      local dockerSide = value("sgcDockerPlacement") == 1 and 0 or 1
      local placementChanged, dockerPlacement = I.Combo(ctx, "Docker button placement", dockerSide, "Far Left\0Far Right\0")
      if placementChanged then save("sgcDockerPlacement", dockerPlacement + 1) end
    end
    if optionalNote then I.TextWrapped(ctx, optionalNote) end

    if I.CollapsingHeader(ctx, "Advanced") then
      if I.BeginTable(ctx, "Button bindings", 4, I.TableFlags_SizingStretchProp) then
        I.TableSetupColumn(ctx, "Button", I.TableColumnFlags_WidthStretch, 1.15)
        I.TableSetupColumn(ctx, "Action", I.TableColumnFlags_WidthFixed, 86)
        I.TableSetupColumn(ctx, "Command ID", I.TableColumnFlags_WidthStretch, 1)
        I.TableSetupColumn(ctx, "", I.TableColumnFlags_WidthFixed, 45)
        I.TableHeadersRow(ctx)
        for _, button in ipairs(configurable) do
          local key = button.key
          I.PushID(ctx, key)
          I.TableNextRow(ctx)
          I.TableSetColumnIndex(ctx, 0)
          I.AlignTextToFramePadding(ctx)
          I.Text(ctx, button.label)
          I.TableSetColumnIndex(ctx, 1)
          local options = button.native and {"Default", "Native", "Custom"} or {"Default", "Custom"}
          local selected = 0
          for i, option in ipairs(options) do if option == choices[key] then selected = i - 1 end end
          I.SetNextItemWidth(ctx, -1)
          local changedChoice, nextChoice = I.Combo(ctx, "##Action", selected, table.concat(options, "\0") .. "\0")
          if changedChoice then choices[key], bindingNote = options[nextChoice + 1], nil end
          if choices[key] == "Native" then I.SetItemTooltip(ctx, button.nativeLabel) end
          I.TableSetColumnIndex(ctx, 2)
          if choices[key] == "Custom" then
            I.SetNextItemWidth(ctx, -1)
            local edited, text = I.InputText(ctx, "##Command ID", drafts[key])
            if edited then drafts[key], bindingNote = text, nil end
          end
          I.TableSetColumnIndex(ctx, 3)
          if I.Button(ctx, "Apply", -1) then applyChoices({button}, false) end
          I.PopID(ctx)
        end
        I.EndTable(ctx)
      end
      if I.Button(ctx, "Apply All") then applyChoices(configurable, true) end
      if bindingNote then I.TextWrapped(ctx, bindingNote) end
    end
    if changedAny then
      r.ThemeLayout_RefreshAll()
      if not pendingReload then updateGridboxAlignment() end
    end
  end

  local function frame()
    if not usingTheme() then return end
    if pendingReload then
      reloadTheme()
      r.defer(frame)
      return
    end
    I.SetNextWindowSize(ctx, 420, 440, I.Cond_FirstUseEver)
    local visible, open = I.Begin(ctx, title, true)
    if visible then
      if I.BeginTabBar(ctx, "Settings tabs") then
        if I.BeginTabItem(ctx, "Transport") then
          drawTransport()
          I.EndTabItem(ctx)
        end
        if I.BeginTabItem(ctx, "Appearance") then
          drawAppearance()
          I.EndTabItem(ctx)
        end
        I.EndTabBar(ctx)
      end
      I.End(ctx)
    end
    if open then r.defer(frame)
    elseif pendingReload then r.defer(function() if usingTheme() then reloadTheme() end end) end
  end
  local recovered, problems = {}, {}
  for _, button in ipairs(enabledOptionalButtons(indices)) do
    if not checkedOverride(assigned[button.key] or "") then
      local entry, problem = recoverBinding(button)
      if entry then recovered[#recovered + 1] = entry
      elseif problem then problems[#problems + 1] = problem end
    end
  end
  if #problems > 0 then optionalNote = table.concat(problems, "\n") end
  if #recovered > 0 then
    local ok, problem = saveBindings(recovered, nil, function(note) optionalNote = note or optionalNote end)
    if not ok then optionalNote = problem end
  end
  if not pendingReload then updateGridboxAlignment() end
  r.defer(frame)
end

-- Retire a highlight worker still running from an older version.
r.DeleteExtState(settings, "stateMonitorOwner", false)

if mode == "startup" then
  -- Called once from REAPER's Scripts/__startup.lua, without opening Settings.
  r.defer(function()
    initializeOptionalButtons()
    restoreAnnexes()
  end)
elseif mode == "renderTcpAnnex" then
  renderTcpAnnex()
elseif type(mode) == "string" then
  for _, button in ipairs(buttons) do
    if button.label == mode then
      runButton(button)
      break
    end
  end
else
  openSettings()
end
