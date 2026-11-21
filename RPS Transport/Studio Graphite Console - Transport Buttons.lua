-- @noindex
local r = reaper
local mode = ...
local title = "Studio Graphite Console - Transport Buttons"
local settings = "StudioGraphiteConsole.Transport"
local themeName = "studio graphite console"
local footerFilename = "Studio Graphite Console - Mixer Folder Footer.lua"
local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptFolder = scriptPath:match("^(.*[/\\])") or ""

local buttons = {
  {key = "Browse", label = "ReaBrowse", app = true, file = "ReaBrowse.lua", native = 50124, nativeLabel = "Media Explorer"},
  {key = "Drum", label = "ReaDrumXT", app = true, file = "ReaDrum.lua"},
  {key = "Spect", label = "ReaSpect", app = true, file = "ReaSpect.lua"},
  {key = "Roll", label = "ReaRoll", app = true, file = "ReaRoll.lua", native = 40153, nativeLabel = "MIDI editor (selected MIDI item)"},
  {key = "Annex", label = "Folder Annex"},
  {key = "Mixer", label = "Mixer", command = 40078},
  {key = "TcpAnnex", label = "TCP Folder Annex", filename = "Studio Graphite Console - Toggle TCP Folder Annex.lua"},
}

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

local function footerCommand(filename)
  filename = filename or footerFilename
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

local function defaultCommand(button)
  return button.command or footerCommand(button.filename)
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
  else
    local command = defaultCommand(button)
    if command > 0 then
      r.Main_OnCommand(command, 0)
    else
      r.MB("Load " .. (button.filename or footerFilename) .. " into REAPER's Main Action List first.", title, 0)
    end
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
  if r.set_action_options then r.set_action_options(1) end
  local keys = {}
  for _, button in ipairs(configurable) do keys[#keys + 1] = button.key end
  local drafts = bindings.readAll(r.GetLastColorThemeFile(), keys)
  local notes, choices, detected, descriptions = {}, {}, {}, {}
  for _, button in ipairs(configurable) do
    local key = button.key
    drafts[key] = drafts[key] or ""
    local saved = r.GetExtState(settings, "choice_" .. key)
    local command = resolve(drafts[key])
    local description = command > 0 and r.kbd_getTextFromCmd(command, 0) or ""
    descriptions[key] = description
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
    if button.app then
      local found, problem = launcher.discover(r, button)
      detected[key] = found and ("Found: " .. found.path) or problem or (button.label .. " not found in the Main Action List.")
    end
  end

  local function defaultBinding(button)
    local names = {Browse = "Open ReaBrowse", Drum = "Open ReaDrumXT", Spect = "Open ReaSpect",
      Roll = "Open ReaRoll", Annex = "Toggle Folder Annex", TcpAnnex = "Toggle TCP Folder Annex",
      Mixer = "Toggle Mixer", Settings = "Transport Buttons"}
    local path = scriptFolder .. "Studio Graphite Console - " .. names[button.key] .. ".lua"
    local command = r.AddRemoveReaScript(true, 0, path, true)
    if not command or command == 0 then return nil, "Could not register " .. path end
    local named = r.ReverseNamedCommandLookup(command)
    if not named or named == "" then return nil, "Could not resolve the default action." end
    return named:sub(1, 1) == "_" and named or "_" .. named
  end
  local pendingReload, failedReload
  local function queueReload(path, notify)
    pendingReload = {path = path, notify = notify}
  end

  local function apply(button, text, choice)
    local normalized = text:match("^%s*(.-)%s*$")
    local command, message = checkedOverride(normalized)
    if not command then notes[button.key] = message; return end
    -- Persist named IDs for scripts/custom actions, not installation-specific numeric IDs.
    local named = r.ReverseNamedCommandLookup(command)
    if named and named ~= "" then normalized = named:sub(1, 1) == "_" and named or "_" .. named end
    local activePath = r.GetLastColorThemeFile()
    local path, changed = bindings.apply(activePath, button.key, normalized)
    if not path then notes[button.key] = changed; return end
    r.SetExtState(settings, "choice_" .. button.key, choice, true)
    choices[button.key] = choice
    r.DeleteExtState(settings, "command_" .. button.key, true)
    r.SetExtState(settings, "binding_" .. button.key, normalized, true)
    local description = r.kbd_getTextFromCmd(command, 0)
    drafts[button.key], descriptions[button.key] = normalized, description
    if changed or failedReload == path then
      notes[button.key] = "Saved: " .. description
      queueReload(path, function(success)
        notes[button.key] = success and ("Applied: " .. description) or
          "Saved, but REAPER could not reload the theme. Apply again to retry."
      end)
    else
      notes[button.key] = "Already assigned: " .. description
    end
  end

  local function value(key)
    local _, _, current = r.ThemeLayout_GetParameter(indices[key])
    return current
  end

  local function reloadTheme()
    local request = pendingReload
    pendingReload = nil
    local saved = {}
    for key, index in pairs(indices) do
      local _, _, current = r.ThemeLayout_GetParameter(index)
      saved[key] = current
    end
    if r.OpenColorThemeFile(request.path) == false then
      failedReload = request.path
      request.notify(false)
      return
    end
    failedReload = nil
    indices = parameters()
    local refresh = false
    for key, current in pairs(saved) do
      local index = indices[key]
      if index and value(key) ~= current then
        -- This restores live overrides without turning them into theme defaults.
        r.ThemeLayout_SetParameter(index, current, false)
        refresh = true
      end
    end
    if refresh then r.ThemeLayout_RefreshAll() end
    request.notify(true)
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
    local changed, placement = I.Combo(ctx, "Placement", value("rpsTransPlacement"), "Auto\0Left\0Right\0")
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

    if I.CollapsingHeader(ctx, "Button actions") then
      I.TextWrapped(ctx, "Default uses the bundled launcher for your installed app. Native uses REAPER. Custom accepts a Main Action List command ID. Apply saves your choice into the theme; Reset applies Default.")
      for _, button in ipairs(configurable) do
        local key = button.key
        I.PushID(ctx, key)
        I.Text(ctx, button.label)
        local options = button.native and {"Default", "Native", "Custom"} or {"Default", "Custom"}
        local selected = 0
        for i, option in ipairs(options) do if option == choices[key] then selected = i - 1 end end
        I.SetNextItemWidth(ctx, 205)
        local changedChoice, nextChoice = I.Combo(ctx, "##ActionType", selected, table.concat(options, "\0") .. "\0")
        if changedChoice then choices[key], notes[key] = options[nextChoice + 1], nil end
        if choices[key] == "Custom" then
          I.SetNextItemWidth(ctx, 205)
          local edited, text = I.InputText(ctx, "Command ID", drafts[key])
          if edited and text ~= drafts[key] then
            local command = resolve(text:match("^%s*(.-)%s*$"))
            drafts[key], notes[key] = text, nil
            descriptions[key] = command > 0 and r.kbd_getTextFromCmd(command, 0) or ""
          end
        elseif choices[key] == "Native" then
          I.TextWrapped(ctx, button.nativeLabel)
        elseif button.app then
          I.TextWrapped(ctx, detected[key])
        end
        if I.Button(ctx, "Apply") then
          local command, message
          if choices[key] == "Custom" then command = drafts[key]
          elseif choices[key] == "Native" then command = tostring(button.native)
          else command, message = defaultBinding(button) end
          if command then apply(button, command, choices[key]) else notes[key] = message end
        end
        I.SameLine(ctx)
        if I.Button(ctx, "Reset") then
          if button.app then
            local found, problem = launcher.discover(r, button)
            detected[key] = found and ("Found: " .. found.path) or problem or (button.label .. " not found in the Main Action List.")
          end
          local command, message = defaultBinding(button)
          if command then apply(button, command, "Default") else notes[key] = message end
        end
        if notes[key] then
          I.TextWrapped(ctx, notes[key])
        elseif descriptions[key] == "" then
          I.TextWrapped(ctx, "Not mapped—click Reset or assign an action.")
        else
          I.TextWrapped(ctx, "Action: " .. descriptions[key])
        end
        I.PopID(ctx)
      end
    end
    if changedAny then r.ThemeLayout_RefreshAll() end
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
  r.defer(frame)
end

-- Retire a highlight worker still running from an older version.
r.DeleteExtState(settings, "stateMonitorOwner", false)

if type(mode) == "string" then
  for _, button in ipairs(buttons) do
    if button.label == mode then
      runButton(button)
      break
    end
  end
else
  openSettings()
end
