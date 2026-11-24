-- @noindex
local r = reaper
local mode = ...
local project = r.EnumProjects(-1, "")
local savedKey = "P_EXT:SGC_OneShotInputQuantize"
local section = "StudioGraphiteConsole.InputQuantize"
local defaults = "0 0 0 0.5 100 0 0 100"

local function notify(message)
  local x, y = r.GetMousePosition()
  r.TrackCtl_SetToolTip(message, x + 12, y + 14, true)
end

local function fields(values)
  local result = {}
  for value in values:gmatch("%S+") do result[#result + 1] = value end
  assert(#result >= 8 and tonumber(result[1]) and tonumber(result[4]), "Unexpected Input Quantize settings.")
  return result
end

local function readTrack(track)
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  assert(ok and chunk:match("^<TRACK%s"), "Could not read a track's recording settings.")
  -- INQ belongs to the track header. Keep nested FX and item state intact.
  local nested = chunk:find("\n[ \t]*<", 2)
  local header = nested and chunk:sub(1, nested - 1) or chunk
  local tail = nested and chunk:sub(nested) or ""
  return header, tail, header:match("\n[ \t]*INQ ([^\r\n]+)")
end

local function writeTrack(track, enabled, division)
  local header, tail, current = readTrack(track)
  local updated = fields(current or defaults)
  updated[1], updated[4] = enabled, division
  local replacement = table.concat(updated, " ")
  if current == replacement then return end

  local changed, count
  if current then
    changed, count = header:gsub("(\n[ \t]*)INQ [^\r\n]+", function(indent)
      return indent .. "INQ " .. replacement
    end, 1)
  else
    changed, count = header:gsub("(\n[ \t]*REC [^\r\n]+)", function(line)
      return line .. "\n  INQ " .. replacement
    end, 1)
  end
  assert(count == 1 and r.SetTrackStateChunk(track, changed .. tail, false), "Could not update a track's Input Quantize.")
end

local function saveRestorePoint(track, values)
  r.GetSetMediaTrackInfo_String(track, savedKey, values, true)
  local _, saved = r.GetSetMediaTrackInfo_String(track, savedKey, "", false)
  assert((saved or "") == values, "Could not save the track settings.")
end

local function showState(active)
  for index = 0, math.huge do
    local key, _, current = r.ThemeLayout_GetParameter(index)
    if not key or key == "" then return end
    if key == "sgcInputQuantizeActive" then
      local state = active and 1 or 0
      if current ~= state then
        r.ThemeLayout_SetParameter(index, state, false)
        r.ThemeLayout_RefreshAll()
      end
      return
    end
  end
end

local function gridDivision()
  local _, grid, mode = r.GetSetProjectGrid(project, false)
  if grid and grid > 0 and grid < math.huge and mode ~= 3 and r.GetToggleCommandState(40904) ~= 1 then
    return string.format("%.10g", grid * 4)
  end
end

local function update(restoring, division, wasActive)
  local changes = {}
  -- Every track has a MIDI recording setting. Preparing it here also covers tracks
  -- that are assigned a MIDI input after iQ is enabled.
  for index = 0, r.CountTracks(project) - 1 do
    local track = r.GetTrack(project, index)
    local _, saved = r.GetSetMediaTrackInfo_String(track, savedKey, "", false)
    saved = saved or ""
    if not restoring or saved ~= "" then
      local _, _, current = readTrack(track)
      local before = fields(current or defaults)
      if restoring or saved == "" or tonumber(before[1]) ~= 1 or
          math.abs(tonumber(before[4]) - tonumber(division)) > 1e-8 then
        changes[#changes + 1] = {
          track = track,
          saved = saved,
          before = before,
          after = restoring and fields(saved) or {"1", nil, nil, division},
        }
      end
    end
  end
  local active = not restoring
  if active == wasActive and #changes == 0 then return end

  local description = restoring and "Restore track Input Quantize" or "Apply project grid to all track Input Quantize settings"
  r.Undo_BeginBlock2(project)
  r.PreventUIRefresh(1)
  local applied = 0
  local ok, message = pcall(function()
    for i, entry in ipairs(changes) do
      applied = i
      if not restoring and entry.saved == "" then
        saveRestorePoint(entry.track, table.concat(entry.before, " "))
      end
      writeTrack(entry.track, entry.after[1], entry.after[4])
      if restoring then saveRestorePoint(entry.track, "") end
    end
    if active ~= wasActive then
      r.SetProjExtState(project, section, "active", active and "1" or "")
    end
  end)
  if not ok then
    for i = applied, 1, -1 do
      local entry = changes[i]
      local recovered = pcall(function()
        writeTrack(entry.track, entry.before[1], entry.before[4])
        saveRestorePoint(entry.track, entry.saved)
      end)
      if not recovered then r.ShowConsoleMsg("Input Quantize could not roll back one track. Use Undo to restore the operation.\n") end
    end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(project, description, -1)
  assert(ok, message)
end

local function run()
  if not project then return end
  if r.GetPlayStateEx(project) & 5 ~= 0 then
    notify("Stop playback or recording before changing iQ.")
    return
  end

  local _, state = r.GetProjExtState(project, section, "active")
  local wasActive = state == "1"
  local modifiers = mode == nil and r.JS_Mouse_GetState and r.JS_Mouse_GetState(8) or 0
  local restoring = mode == "off" or modifiers & 8 ~= 0
  local division
  if not restoring then
    division = gridDivision()
    if not division then
      notify("Choose a musical grid division to apply Input Quantize.")
      return
    end
  end
  update(restoring, division, wasActive)
  showState(not restoring)
  if restoring then
    notify("iQ off. Restored prior track settings.")
  elseif wasActive then
    notify("iQ refreshed. Applied the current grid to all tracks.")
  else
    notify("iQ on. Applied the current grid to all tracks.")
  end
end

local ok, message = pcall(run)
if not ok then r.MB(message, "Studio Graphite Console Input Quantize", 0) end
