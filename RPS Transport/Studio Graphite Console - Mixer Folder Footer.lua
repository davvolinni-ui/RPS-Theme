-- @noindex
local r = reaper
local tcp = ... == "tcp"
local title = tcp and "Studio Graphite Console - TCP Folder Annex" or "Studio Graphite Console - Mixer Folder Footer"
local parameterName = tcp and "tcpFolderAnnex" or "mcpFolderFooter"
local themeName = "studio graphite console"
local foot, step, recess = 4, 8, 4
local sharedEndInset = 2

if not ((tcp or r.BR_Win32_GetMixerHwnd) and r.JS_Composite and r.JS_LICE_CreateBitmap and r.JS_Window_InvalidateRect) then
  r.MB("This footer uses the SWS and js_ReaScriptAPI extensions.", title, 0)
  return
end

local function activeTheme()
  -- REAPER can report the inner theme filename when restoring a packaged theme.
  local filename = (r.GetLastColorThemeFile() or ""):match("[^/\\]+$")
  if not filename then return false end
  filename = filename:lower()
  return filename == themeName .. ".reapertheme" or filename == themeName .. ".reaperthemezip"
end

local parameterIndex
local function getParameter()
  if parameterIndex then
    local name, _, value = r.ThemeLayout_GetParameter(parameterIndex)
    if name == parameterName then return parameterIndex, value end
    parameterIndex = nil
  end
  local index = 0
  while true do
    local name, _, value = r.ThemeLayout_GetParameter(index)
    if not name or name == "" then return end
    if name == parameterName then
      parameterIndex = index
      return index, value
    end
    index = index + 1
  end
end

local handle, attachedMixer, frontFrame, spareFrame
local viewportWidth, viewportHeight, resizeUntil = nil, nil, 0
local updateInterval = 1 / 30
local clipChildrenStyle = 0x02000000 -- WS_CLIPCHILDREN
local childRows, clipsChildren, ownsClipStyle, childWindowsFailed = {}, false, false, false
local canUseChildWindows = r.GetOS():match("^Win") and r.JS_Window_Create and r.JS_Window_Destroy
  and r.JS_Window_GetLong and r.JS_Window_SetLong and r.JS_Window_SetPosition and r.JS_Window_Update

local function destroyChildRow(row)
  if r.JS_Window_IsWindow(row.window) then
    if row.bitmap then r.JS_Composite_Unlink(row.window, row.bitmap, false) end
    r.JS_Window_Destroy(row.window)
  end
  if row.bitmap then r.JS_LICE_DestroyBitmap(row.bitmap) end
  if row.spare then r.JS_LICE_DestroyBitmap(row.spare) end
end

local function clearChildRows()
  for _, row in pairs(childRows) do destroyChildRow(row) end
  childRows = {}
  if ownsClipStyle and handle and r.JS_Window_IsWindow(handle) then
    local style = r.JS_Window_GetLong(handle, "STYLE")
    r.JS_Window_SetLong(handle, "STYLE", style & ~clipChildrenStyle)
  end
  clipsChildren, ownsClipStyle = false, false
end

local function clear()
  clearChildRows()
  childWindowsFailed = false
  local validHandle = handle and r.JS_Window_IsWindow(handle)
  if frontFrame then
    if validHandle then
      r.JS_Composite_Unlink(handle, frontFrame.bitmap, true)
    end
    r.JS_LICE_DestroyBitmap(frontFrame.bitmap)
    frontFrame = nil
  end
  if spareFrame then
    r.JS_LICE_DestroyBitmap(spareFrame.bitmap)
    spareFrame = nil
  end
end

local function resetViewport()
  viewportWidth, viewportHeight, resizeUntil = nil, nil, 0
end

local function findDisplay(mixer)
  local _, children = r.JS_Window_ListAllChild(mixer)
  for address in (children or ""):gmatch("[^,]+") do
    local child = r.JS_Window_HandleFromAddress(address)
    if r.JS_Window_GetClassName(child) == (tcp and "REAPERTCPDisplay" or "REAPERMCPDisplay")
        and (tcp or r.JS_Window_GetTitle(child) == "") then
      return child
    end
  end
end

local function setFooter(size)
  local index, old = getParameter()
  if not index then return false end
  if old ~= size then
    r.ThemeLayout_SetParameter(index, size, false)
    r.ThemeLayout_RefreshAll()
    return false
  end
  return true
end

local function pixel(red, green, blue)
  return 0xFF000000 | (red << 16) | (green << 8) | blue
end

local annexBackground = pixel(25, 27, 28)
local folderFill = pixel(43, 44, 46)

local function linearChannel(channel)
  local srgb = channel / 255
  if srgb <= 0.04045 then return srgb / 12.92 end
  return ((srgb + 0.055) / 1.055) ^ 2.4
end

local function luminance(red, green, blue)
  return 0.2126 * linearChannel(red) + 0.7152 * linearChannel(green) + 0.0722 * linearChannel(blue)
end

-- The fill is lighter than the surrounding annex, so use it as the contrast reference.
local minimumLuminance = 2.5 * (luminance(43, 44, 46) + 0.05) - 0.05

local function trackColor(track)
  local nativeColor = r.GetTrackColor(track)
  if nativeColor == 0 then return pixel(101, 110, 114) end
  local red, green, blue = r.ColorFromNative(nativeColor)
  if luminance(red, green, blue) >= minimumLuminance then return pixel(red, green, blue) end

  local low, high = 0, 256
  while high - low > 1 do
    local lift = (low + high) // 2
    local liftedRed = red + ((255 - red) * lift + 128) // 256
    local liftedGreen = green + ((255 - green) * lift + 128) // 256
    local liftedBlue = blue + ((255 - blue) * lift + 128) // 256
    if luminance(liftedRed, liftedGreen, liftedBlue) >= minimumLuminance then
      high = lift
    else
      low = lift
    end
  end
  return pixel(red + ((255 - red) * high + 128) // 256,
    green + ((255 - green) * high + 128) // 256,
    blue + ((255 - blue) * high + 128) // 256)
end

local function tcpTrackY(track, screenTop, flippedY)
  if flippedY then return r.GetMediaTrackInfo_Value(track, "I_TCPY") end
  return r.GetMediaTrackInfo_Value(track, "I_TCPSCREENY") - screenTop
end

local function collectRows(screenLeft, screenTop, flippedY)
  local rows, depth, hasVisibleTracks = {}, 0, false
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    if r.IsTrackVisible(track, not tcp) then
      hasVisibleTracks = true
      local height = r.GetMediaTrackInfo_Value(track, tcp and "I_TCPH" or "I_MCPH")
      local width = tcp and 1 or r.GetMediaTrackInfo_Value(track, "I_MCPW")
      if width > 0 and height > 0 then
        local x, bottom
        if tcp then
          x = tcpTrackY(track, screenTop, flippedY)
          width = math.max(height, r.GetMediaTrackInfo_Value(track, "I_WNDH"))
          bottom = 0
        else
          local screenX = r.GetMediaTrackInfo_Value(track, "I_MCPSCREENX")
          x = screenX - screenLeft
          bottom = r.GetMediaTrackInfo_Value(track, "I_MCPY") + height
        end
        local ancestors = {}
        if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") > 0 then ancestors[1] = track end
        local parent = r.GetParentTrack(track)
        while parent do
          -- REAPER can still show compressed child rows under a fully collapsed TCP folder.
          if tcp and r.GetMediaTrackInfo_Value(parent, "I_FOLDERCOMPACT") == 2 then ancestors = {} end
          table.insert(ancestors, 1, parent)
          parent = r.GetParentTrack(parent)
        end
        depth = math.max(depth, #ancestors)
        local row = rows[bottom]
        if not row then
          row = {}
          rows[bottom] = row
        end
        row[#row + 1] = { left = x, right = x + width, ancestors = ancestors }
      end
    end
  end
  return rows, depth, hasVisibleTracks
end

local function fillShape(fill, left, top, right, height, radius, color)
  local width = right - left
  if width < 1 or height < 1 then return end
  radius = math.min(radius, height, math.floor(width / 2))
  if height > radius then
    fill(left, top, width, height - radius, color)
  end
  for offset = 0, radius - 1 do
    local inset = math.floor(radius - math.sqrt(radius * radius - (offset + 0.5) ^ 2) + 0.5)
    fill(left + inset, top + height - radius + offset, width - 2 * inset, 1, color)
  end
end

local function makePlan(rows, viewportWidth, viewportHeight, height, depth, scale, fixedSurfaces)
  local plan = {}
  local endInset = math.floor(sharedEndInset * scale + 0.5)
  for bottom, tracks in pairs(rows) do
    -- TCP tracks share a synthetic row at key zero. Their viewport culling
    -- happens along the span axis below, before the row is rotated for painting.
    local top = tcp and 0 or bottom - height
    if tcp or (top < viewportHeight and bottom > 0) then
      table.sort(tracks, function(a,b) return a.left < b.left end)
      local spans = {}
      local parentEnds = {}
      for tier = 1, depth do
        local tierSpans = {}
        local previous
        for _, strip in ipairs(tracks) do
          local owner = strip.ancestors[tier]
          if owner and previous and previous.owner == owner and (tcp or strip.left <= previous.right + 1) then
            previous.right = math.max(previous.right, strip.right)
          elseif owner then
            previous = {owner = owner, left = strip.left, right = strip.right, tier = tier}
            tierSpans[#tierSpans + 1] = previous
          else
            previous = nil
          end
        end
        local tierEnds = {}
        for _, span in ipairs(tierSpans) do
          local sharedEnd = span.right
          local parentEnd = parentEnds[sharedEnd]
          if parentEnd then
            span.right = math.max(span.left + 1, parentEnd - endInset)
          end
          tierEnds[sharedEnd] = span.right
          spans[#spans + 1] = span
        end
        parentEnds = tierEnds
      end
      local visible, left, right = {}, viewportWidth, 0
      for _, span in ipairs(spans) do
        if span.right > 0 and span.left < viewportWidth then
          span.color = trackColor(span.owner)
          visible[#visible + 1] = span
          left = math.min(left, span.left)
          right = math.max(right, span.right)
        end
      end
      if fixedSurfaces then
        -- The native row owns a stationary surface, even when its spans scroll offscreen.
        plan[#plan + 1] = {left = 0, top = top, width = viewportWidth, height = height, spans = visible}
      elseif #visible > 0 then
        left, right = math.max(0, left), math.min(viewportWidth, right)
        plan[#plan + 1] = {left = left, top = top, width = right - left, height = height, spans = visible}
      end
    end
  end
  table.sort(plan, function(a,b) return a.top < b.top end)
  return plan
end

local function paintRow(frame, row, scale)
  local gap = math.max(1, math.floor(scale + 0.5))
  local top = tcp and 0 or row.top - frame.top
  local function fill(x, y, w, h, color)
    if tcp then x, y, w, h = row.width - y - h, x, h, w end
    r.JS_LICE_FillRect(frame.bitmap, x, y, w, h, color, 1, "COPY")
  end
  for _, span in ipairs(row.spans) do
    local offset = tcp and frame.top or frame.left
    local x1 = span.left - offset + gap
    local x2 = span.right - offset - gap
    local h = (tcp and row.width or row.height) - math.floor((span.tier - 1) * step * scale + 0.5)
    fillShape(fill, x1, top, x2, h, math.floor(6 * scale + 0.5), span.color)
    fillShape(fill, x1 + gap, top, x2 - gap, h - math.floor(foot * scale + 0.5),
      math.floor(5 * scale + 0.5), folderFill)
  end
end

local function buildFrame(plan, scale)
  if #plan == 0 then return end
  local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
  local parts = {scale}
  for _, row in ipairs(plan) do
    left = math.min(left, row.left)
    top = math.min(top, row.top)
    right = math.max(right, row.left + row.width)
    bottom = math.max(bottom, row.top + row.height)
    parts[#parts + 1] = table.concat({row.left, row.top, row.width, row.height}, ":")
    for _, span in ipairs(row.spans) do
      parts[#parts + 1] = table.concat({span.left, span.right, span.tier, span.color}, ":")
    end
  end
  return {left = left, top = top, width = right - left, height = bottom - top,
    signature = table.concat(parts, ";")}
end

local function repaintComposite(plan, scale)
  local frame, previous = buildFrame(plan, scale), frontFrame
  if not frame and not previous then return end
  if frame and previous and frame.signature == previous.signature then return end

  if frame then
    if spareFrame and (spareFrame.bitmapWidth < frame.width or spareFrame.bitmapHeight < frame.height) then
      r.JS_LICE_DestroyBitmap(spareFrame.bitmap)
      spareFrame = nil
    end
    -- Leave room in the backing bitmap for small size changes during a drag.
    frame.bitmapWidth = spareFrame and spareFrame.bitmapWidth or math.ceil(frame.width / 64) * 64
    frame.bitmapHeight = spareFrame and spareFrame.bitmapHeight or math.ceil(frame.height / 32) * 32
    frame.bitmap = spareFrame and spareFrame.bitmap
      or r.JS_LICE_CreateBitmap(true, frame.bitmapWidth, frame.bitmapHeight)
    if not frame.bitmap then return end
    spareFrame = nil
    r.JS_LICE_Clear(frame.bitmap, tcp and annexBackground or 0)
    for _, row in ipairs(plan) do paintRow(frame, row, scale) end
    local linked = r.JS_Composite(handle, frame.left, frame.top, frame.width, frame.height,
      frame.bitmap, 0, 0, frame.width, frame.height, false)
    if linked < 1 then
      spareFrame = frame
      return
    end
  end

  if previous then
    r.JS_Composite_Unlink(handle, previous.bitmap, false)
    if spareFrame then r.JS_LICE_DestroyBitmap(spareFrame.bitmap) end
    spareFrame = previous
  end
  frontFrame = frame

  local first, second = frame or previous, previous or frame
  r.JS_Window_InvalidateRect(handle,
    math.min(first.left, second.left), math.min(first.top, second.top),
    math.max(first.left + first.width, second.left + second.width),
    math.max(first.top + first.height, second.top + second.height), false)
end

local function enableChildClipping()
  if clipsChildren then return true end
  local style = r.JS_Window_GetLong(handle, "STYLE")
  if style & clipChildrenStyle ~= 0 then
    clipsChildren = true
  else
    r.JS_Window_SetLong(handle, "STYLE", style | clipChildrenStyle)
    local currentStyle = r.JS_Window_GetLong(handle, "STYLE")
    clipsChildren = currentStyle & clipChildrenStyle ~= 0
    ownsClipStyle = clipsChildren
  end
  return clipsChildren
end

local function repaintChildRow(surface, row, scale, clientHeight)
  local top = math.max(row.top, 0)
  local height = math.min(row.top + row.height, clientHeight) - top
  local parts = {scale, row.width, height, row.top - top, row.height}
  for _, span in ipairs(row.spans) do
    parts[#parts + 1] = table.concat({span.left - row.left, span.right - row.left, span.tier, span.color}, ":")
  end
  local signature = table.concat(parts, ";")
  local needsPaint = signature ~= surface.signature

  if needsPaint then
    local bitmap, width, capacity = surface.spare, surface.spareWidth, surface.spareHeight
    if bitmap and (width < row.width or capacity < height) then
      r.JS_LICE_DestroyBitmap(bitmap)
      bitmap = nil
      surface.spare = nil
    end
    if not bitmap then
      width, capacity = math.ceil(row.width / 64) * 64, math.ceil(height / 32) * 32
      bitmap = r.JS_LICE_CreateBitmap(true, width, capacity)
      if not bitmap then return false end
    end
    surface.spare = nil

    -- The dedicated child covers only the footer space reserved by the theme.
    r.JS_LICE_Clear(bitmap, annexBackground)
    paintRow({bitmap = bitmap, left = row.left, top = top}, row, scale)
    local linked = r.JS_Composite(surface.window, 0, 0, row.width, height,
      bitmap, 0, 0, row.width, height, false)
    if linked < 1 then
      r.JS_LICE_DestroyBitmap(bitmap)
      return false
    end
    if surface.bitmap then r.JS_Composite_Unlink(surface.window, surface.bitmap, false) end
    surface.spare, surface.spareWidth, surface.spareHeight = surface.bitmap, surface.bitmapWidth, surface.bitmapHeight
    surface.bitmap, surface.bitmapWidth, surface.bitmapHeight = bitmap, width, capacity
  end

  if surface.left ~= row.left or surface.top ~= top or surface.width ~= row.width or surface.height ~= height then
    if not r.JS_Window_SetPosition(surface.window, row.left, top, row.width, height) then return false end
    surface.left, surface.top, surface.width, surface.height = row.left, top, row.width, height
  end
  if needsPaint then
    r.JS_Window_InvalidateRect(surface.window, 0, 0, row.width, height, false)
    r.JS_Window_Update(surface.window)
    surface.signature = signature
  end
  return true
end

local function repaintChildRows(plan, scale, clientHeight)
  if #plan > 0 and not enableChildClipping() then return false end
  for index, row in ipairs(plan) do
    local surface = childRows[index]
    if not surface or not r.JS_Window_IsWindow(surface.window) then
      if surface then
        destroyChildRow(surface)
        childRows[index] = nil
      end
      -- Create outside the client area so the first visible position has content.
      local window = r.JS_Window_Create("", "StudioGraphiteMixerFooterRow", -1, -1, 1, 1,
        "CHILD,DISABLED", handle)
      if not window then return false end
      surface = {window = window}
      childRows[index] = surface
    end
    if not repaintChildRow(surface, row, scale, clientHeight) then return false end
  end
  for index = #childRows, #plan + 1, -1 do
    destroyChildRow(childRows[index])
    childRows[index] = nil
  end
  return true
end

local function readViewport(window)
  local ok, left, top, right, bottom = r.JS_Window_GetClientRect(window)
  if not ok or right <= left or bottom == top then return end
  -- SWELL reports screen Y from the bottom on macOS. Drawing uses client coordinates.
  return left, top, right - left, math.abs(bottom - top), bottom < top
end

local function draw(now)
  if not activeTheme() then clear(); resetViewport(); return end
  local mixer = tcp and r.GetMainHwnd() or r.BR_Win32_GetMixerHwnd()
  if not mixer or not r.JS_Window_IsVisible(mixer) then
    clear()
    resetViewport()
    setFooter(0)
    return
  end
  if mixer ~= attachedMixer or not handle or not r.JS_Window_IsWindow(handle) then
    clear()
    resetViewport()
    attachedMixer, handle = mixer, findDisplay(mixer)
  end
  if not handle or not r.JS_Window_IsVisible(handle) then clear(); resetViewport(); setFooter(0); return end
  if not tcp and childWindowsFailed then return end
  local left, top, width, clientHeight, flippedY = readViewport(handle)
  if not width then return end
  if viewportWidth and (width ~= viewportWidth or clientHeight ~= viewportHeight) then
    resizeUntil = now + 0.18
  end
  viewportWidth, viewportHeight = width, clientHeight

  local rows, depth, hasVisibleTracks = collectRows(left, top, flippedY)
  if now < resizeUntil and hasVisibleTracks and not next(rows) then return end
  local _, dpi = r.ThemeLayout_GetLayout(tcp and "tcp" or "mcp", -3)
  local dpiScale = (tonumber(dpi) or 256) / 256
  local scale = dpiScale > 1.74 and 2 or dpiScale > 1.34 and 1.5 or 1
  local logicalHeight = depth > 0 and math.min(tcp and math.max(0, width / scale - 24) or 128,
    foot + recess + (depth - 1) * step) or 0
  local height = math.floor(logicalHeight * scale + 0.5)
  if not setFooter(height) then return end

  local plan = {}
  if height > 0 then
    if tcp then
      local gutterTop = 0
      if r.GetMasterTrackVisibility() & 1 == 1 then
        local master = r.GetMasterTrack(0)
        gutterTop = math.max(0, tcpTrackY(master, top, flippedY)
          + r.GetMediaTrackInfo_Value(master, "I_WNDH"))
      end
      if gutterTop < clientHeight then
        local vertical = makePlan(rows, clientHeight, 1, height, depth, scale)[1]
        plan[1] = {left = 0, top = gutterTop, width = height, height = clientHeight - gutterTop,
          spans = vertical and vertical.spans or {}}
      end
    else
      plan = makePlan(rows, width, viewportHeight, height, depth, scale,
        canUseChildWindows and not childWindowsFailed)
    end
  end
  if canUseChildWindows and not childWindowsFailed then
    if repaintChildRows(plan, scale, clientHeight) then return end
    clearChildRows()
    childWindowsFailed = true
    if not tcp then setFooter(0); return end
  end
  repaintComposite(plan, scale)
end

if not activeTheme() then
  r.MB("Select Studio Graphite Console in Options > Themes before starting this annex.", title, 0)
  return
elseif not getParameter() then
  r.MB("The active Studio Graphite Console theme is missing the annex setting. Reinstall the updated theme package.", title, 0)
  return
end

if tcp then r.DeleteExtState("StudioGraphiteConsole.Transport", "stateMonitorOwner", false) end
if r.set_action_options then r.set_action_options(1 | 4) end
local _, _, actionSection, actionCommand = r.get_action_context()
local function publishToggle(state)
  if actionCommand and actionCommand > 0 then
    r.SetToggleCommandState(actionSection, actionCommand, state)
    r.RefreshToolbar2(actionSection, actionCommand)
  end
end
publishToggle(1)
r.atexit(function()
  publishToggle(0)
  clear()
  if activeTheme() then setFooter(0) end
end)
local nextUpdate = 0
local function run()
  local now = r.time_precise()
  if now >= nextUpdate then
    draw(now)
    nextUpdate = now + updateInterval
  end
  r.defer(run)
end
run()
