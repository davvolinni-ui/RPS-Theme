-- @noindex
--[=[
Gridbox transport scaling is adapted from Gridbox.lua by Ilias-Timon Poulakis (FeedTheCat).
https://github.com/iliaspoulakis/Reaper-Tools/blob/master/Adaptive%20grid/Gridbox.lua

MIT License

Copyright (c) 2020 iliaspoulakis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]=]

local folder = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local launcher = dofile(folder .. "app_launcher.lua")
local M = {}
local namespace = "FTC.GridBox"
local apps = {"Browse", "Drum", "Spect", "Roll", "Annex", "TcpAnnex", "Mixer"}
local gridWidth, gridHeight = 88, 28

-- Transport geometry in logical pixels. REAPER's status edge is Gridbox's anchor.
function M.offset(value, width, height, flags, centered, native)
  local status, margin = value("transStatusWidth"), value("transMargin")
  local dockers = value("sgcDockerLeftVisible") + value("sgcDockerBottomVisible") + value("sgcDockerRightVisible")
  local dockerWidth = dockers > 0 and width > 570 + 8 * dockers and 8 + 36 * dockers or 0
  local panelLeft = value("sgcDockerPlacement") == 1 and dockerWidth or 0
  local panelRight = width - (dockerWidth - panelLeft)
  local rpsWidth = 17
  for _, key in ipairs(apps) do rpsWidth = rpsWidth + 29 * value("rpsTrans" .. key) end

  local rpsPlacement = value("rpsTransPlacement")
  local farWidth = rpsWidth + 12
  local farFits = panelRight - panelLeft >= farWidth + 244 + status + 24
  local left = panelLeft + (farFits and rpsPlacement == 3 and farWidth or 0)
  local right = panelRight - (farFits and rpsPlacement == 4 and farWidth or 0)
  local available = right - left
  local showRate, showSignature = flags & 1 == 0, flags & 4 == 0
  local rate = value("transRateFaderWidth")
  local rateWidth = rate == 100 and 98 or rate
  local readouts = value("transSelectionWidth") + 58 + (showSignature and 118 or 78)
  if showRate then readouts = readouts + rateWidth end
  readouts = readouts + (showRate and 4 or 3) * margin / (native or 1)
  local where = value("sgcIQPlacement")
  if not centered then
    local start = left + margin
    local nativeEnd = start + status + margin + 244
    local limit = right - 4
    if height > 40 or limit < nativeEnd then return nil end
    local rpsLeftInset = 0
    if rpsPlacement == 1 then
      local inset = rpsWidth + 16
      if nativeEnd + inset <= limit then rpsLeftInset = inset end
    elseif rpsPlacement == 0 or rpsPlacement == 2 then
      local rpsStart = math.min(nativeEnd + readouts + 10, right - rpsWidth - 6)
      if rpsStart >= nativeEnd + 10 then limit = rpsStart - 10 end
    end
    local room = limit - nativeEnd - rpsLeftInset
    if where == 1 or where == 2 then
      -- The left group is measured from the leading edge of the time readout.
      return room >= 132 and -128 or nil
    end
    if room < 128 then return nil end
    if where == 0 then return status + margin + 278 end
    if where == 3 then return nativeEnd + math.min(readouts, room - 128) + 40 - start end
    return nil
  end
  local base = status + margin + 244 + readouts
  if height > 40 or available <= base + 24 then return nil end
  if available > base + 24 + 430 then base = base + 46 end

  local start = left + (centered and (available - base) / 2 or margin)
  local leftRps = start - 10 - rpsWidth
  local rightRps = start + base + 10
  local nearLeft = (rpsPlacement == 0 or rpsPlacement == 1) and leftRps >= left + 6
  local nearRight = not nearLeft and (rpsPlacement == 0 or rpsPlacement == 2)
    and rightRps + rpsWidth + 6 <= right
  if where == 0 then
    local coreLeft = nearLeft and leftRps + rpsWidth + 10 or left
    local coreRight = nearRight and rightRps - 10 or right
    if coreRight - coreLeft - base < 128 then return nil end
    return status + margin + 278
  elseif where == 3 then
    local x = (nearRight and rightRps + rpsWidth or start + base) + 40
    if x + gridWidth > right - 4 then return nil end
    return x - start
  else
    local x = (nearLeft and leftRps or start) - 128
    if x < left + 4 then return nil end
    return x - start
  end
end

local function themeKey(r, path)
  local normalized = path:gsub("\\", "/")
  local resource = r.GetResourcePath():gsub("\\", "/"):gsub("/+$", "") .. "/"
  local prefix = normalized:sub(1, #resource)
  if prefix == resource or (r.GetOS():match("^Win") and prefix:lower() == resource:lower()) then
    normalized = normalized:sub(#resource + 1)
  end
  local escapes = { [","] = "\\,", [":"] = "\\:", ["{"] = "\\[", ["}"] = "\\]" }
  return (normalized:gsub("%.[^./]+$", ""):gsub("[,:{}]", escapes))
end

local function round(value)
  return math.floor(value + 0.5)
end

-- Match FTC's coordinate scaling so it will reuse these dimensions on restart.
local function measureScale(r)
  local _, dpi = r.ThemeLayout_GetLayout("trans", -3)
  local _, layout = r.ThemeLayout_GetLayout("trans", -1)
  local scale = (tonumber(dpi) or 256) / 256
  local mac = r.GetOS():match("^OSX") or r.GetOS():match("^macOS")
  local _, configScale = r.get_config_var_string("ui_scale")
  local uiScale = mac and (tonumber(configScale) or 1) or 1
  local pixel = scale / uiScale + 0.005
  local layoutScale = tonumber((layout or ""):match("^(%d+)%%"))
  local point = pixel
  if pixel > 1.74 then
    if layoutScale == 50 then point = 1 elseif layoutScale == 75 then point = 1.5 end
  elseif pixel > 1.34 then
    if layoutScale == 50 or layoutScale == 75 then point = 1
    elseif layoutScale == 150 or layoutScale == 200 then point = 2 end
  elseif layoutScale == 150 or layoutScale == 200 then
    point = layoutScale / 100
  end
  return mac and point / pixel * uiScale or point
end

function M.apply(r, value, onReapplied)
  local manual = onReapplied ~= nil
  local action, problem = launcher.discover(r, {file = "Gridbox.lua"})
  if not action then
    if manual then return problem or "Load FTC Gridbox to align it with iQ." end
    return
  end
  local running = r.GetToggleCommandState(action.command) == 1
  if not running then
    if manual then return "Open FTC Gridbox before aligning it with iQ." end
    return
  end
  if r.GetExtState(namespace, "attach_title") ~= "" then
    return "Move FTC Gridbox to the transport before aligning it with iQ."
  end
  if r.GetPlayState() & 5 ~= 0 then
    if manual then return "Stop playback or recording before aligning Gridbox." end
    return
  end
  if not (r.JS_Window_ListFind and r.JS_Window_FindChildByID and r.get_config_var_string) then
    return "Gridbox alignment requires the REAPER and js_ReaScriptAPI transport APIs."
  end
  local title = r.JS_Localize and r.JS_Localize("Transport", "common") or "Transport"
  local count, windows = r.JS_Window_ListFind(title, true)
  if count ~= 1 then return "Open a single transport window to align Gridbox." end
  local transport = r.JS_Window_HandleFromAddress(windows:match("^[^,]+"))
  if not transport then return "The transport window is unavailable." end
  local status = r.JS_Window_FindChildByID(transport, 1010)
  if not status then return "The transport time readout is unavailable." end
  local ok, width, height = r.JS_Window_GetClientSize(transport)
  local readoutOK, statusWidth = r.JS_Window_GetClientSize(status)
  if not ok or not readoutOK or statusWidth <= 0 then return "The transport layout is unavailable." end
  local native = statusWidth / value("transStatusWidth")
  local logicalHeight = height / native
  if math.abs(logicalHeight - 40) < 1e-6 then logicalHeight = 40 end
  local _, flagString = r.get_config_var_string("transflags")
  local flags = tonumber(flagString)
  if not flags and r.SNM_GetIntConfigVar then flags = r.SNM_GetIntConfigVar("transflags", -1) end
  if not flags or flags < 0 then return "Could not read the transport display options." end
  local centered = r.GetToggleCommandState(40533) == 1
  local offset = M.offset(value, width / native, logicalHeight, flags, centered, native)
  if not offset then return "Widen the transport to fit Gridbox beside iQ." end
  local otherOffset = M.offset(value, width / native, logicalHeight, flags, not centered, native) or offset
  local plainX, centeredX = offset, otherOffset
  if centered then plainX, centeredX = otherOffset, offset end

  local key = themeKey(r, r.GetLastColorThemeFile())
  local original = r.GetExtState(namespace, "theme_settings")
  local data = original == "" and "t:{}" or original
  assert(data:sub(1, 3) == "t:{" and data:sub(-1) == "}", "Could not read Gridbox settings.")
  local _, recordStart = data:find(key .. ":t:{", 1, true)
  local recordEnd = recordStart and data:find("}", recordStart, true)
  assert(not recordStart or recordEnd, "Incomplete Gridbox theme settings.")
  local record = recordStart and data:sub(recordStart, recordEnd) or "{}"
  local function addField(tableText, field)
    local opening = tableText:sub(-2, -2)
    local separator = (opening == "{" or opening == ",") and "" or ","
    return tableText:sub(1, -2) .. separator .. field .. "}"
  end
  local measure = measureScale(r)
  for field, value in pairs({
    box_x = 0, box_y = round(4 * native), box_w = round(gridWidth * native), box_h = round(gridHeight * native),
    attach_mode = 3, attach_x = round(plainX * native),
    attach_center_mode = 3, attach_center_x = round(centeredX * native), measure_scale = measure,
  }) do
    local replacement = field .. ":n:" .. tostring(value)
    local count
    record, count = record:gsub("([{,])" .. field .. ":n:[^,}]+([,}])", function(start, finish)
      return start .. replacement .. finish
    end)
    if count == 0 then record = addField(record, replacement) end
  end
  if recordStart then data = data:sub(1, recordStart - 1) .. record .. data:sub(recordEnd + 1)
  else data = addField(data, key .. ":t:" .. record) end
  -- The saved offset can be correct while the running Gridbox is out of place.
  if not manual and data == original and value("sgcGridboxActive") == 1 then return end
  r.Main_OnCommand(action.command, 0)
  r.defer(function()
    if r.GetToggleCommandState(action.command) == 1 then
      if manual then onReapplied("Gridbox stayed open. Click Realign to retry.") end
      return
    end
    if data ~= original then r.SetExtState(namespace, "theme_settings", data, true) end
    r.Main_OnCommand(action.command, 0)
    if manual then
      if r.GetToggleCommandState(action.command) == 1 then
        onReapplied("Gridbox alignment reapplied.")
      else
        onReapplied("Gridbox did not reopen. Open Gridbox to use the saved alignment.")
      end
    end
  end)
  if manual then return "Reapplying Gridbox alignment." end
end

return M
