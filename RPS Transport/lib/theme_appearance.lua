-- @noindex
local folder = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local files = dofile(folder .. "theme_files.lua")
local M = {defaultGrid = 100, minGrid = 25, maxGrid = 150, defaultMeter = 0x4B9FA6, defaultInterlaced = true}
local themeFile = "Studio Graphite Console.ReaperTheme"
local gridColors = {col_gridlines = 7893603, col_gridlines2 = 12104362, col_gridlines3 = 10064771}
local meterImages = {
  "meter_strip_h.png", "meter_strip_v.png", "meter_strip_h_rms.png", "meter_strip_v_rms.png",
  "meter_clip_v_rms2.png", -- Master RMS good-signal band.
}
local gridSetting = ";sgcGridBrightness"

local function readNumber(config, key)
  return tonumber(config:match("[\r\n]" .. key .. "=(%d+)"))
end

local function setNumber(config, key, value)
  local updated, count = config:gsub("([\r\n]" .. key .. "=)%d+", function(prefix) return prefix .. value end)
  assert(count == 1, "Could not find theme setting " .. key .. ".")
  return updated
end

local function readSettings(config)
  local grid = readNumber(config, gridSetting)
  if not grid or grid < M.minGrid or grid > M.maxGrid then grid = M.defaultGrid end
  -- REAPER stores zero when the interlaced-meter checkbox is checked.
  return grid, readNumber(config, "col_vudoint") == 0
end

local function setSetting(config, key, value)
  config = config:gsub("\r?\n" .. key .. "=[^\r\n]+", "")
  if not value then return config end
  local newline = config:find("\r\n", 1, true) and "\r\n" or "\n"
  if not config:match("[\r\n]$") then config = config .. newline end
  return config .. key .. "=" .. value .. newline
end

local function channel(value)
  return math.min(255, math.max(0, math.floor(value + 0.5)))
end

local function luminanceChannel(byte)
  local value = byte / 255
  if value <= 0.04045 then return value / 12.92 end
  return ((value + 0.055) / 1.055) ^ 2.4
end

local function luminance(red, green, blue)
  return 0.2126 * luminanceChannel(red) + 0.7152 * luminanceChannel(green) + 0.0722 * luminanceChannel(blue)
end

-- Leave a small margin over 4.5:1 against the dark meter background for rounding.
local minimumReadoutLuminance = (luminance(38, 38, 38) + 0.05) * 4.6 - 0.05

local function setRmsReadout(config, rgb)
  local red, green, blue = rgb >> 16, rgb >> 8 & 255, rgb & 255
  if rgb == M.defaultMeter then red, green, blue = 109, 208, 207 end

  local blend, r, g, b = 0, red, green, blue
  while luminance(r, g, b) < minimumReadoutLuminance do
    blend = blend + 1
    r = channel(red + (255 - red) * blend / 100)
    g = channel(green + (255 - green) * blend / 100)
    b = channel(blue + (255 - blue) * blend / 100)
  end

  local brightness = 50
  while luminance(r * brightness // 100, g * brightness // 100, b * brightness // 100) < minimumReadoutLuminance do
    brightness = brightness + 1
  end
  local multiplier = ("%d.%02d"):format(brightness // 100, brightness % 100)
  local style = ("* textBrightness{0}<%d %s textBrightnessMult{0} [%d %d %d]")
    :format(brightness, multiplier, r, g, b)
  local pattern = "([\r\n][ \t]*set[ \t]+master%.mcp%.meter%.rmsreadout%.color[ \t]+" ..
    "!masterMcpMeterVals{0}[ \t]+%[0 0 0%][ \t]+)[^\r\n]+"
  local updated, count = config:gsub(pattern, function(prefix) return prefix .. style end)
  assert(count == 1, "Could not find the master RMS readout setting in the theme.")
  return updated
end

local function setLitMeterScale(config, darkest)
  -- A bright peak can make charcoal look suitable even when it disappears
  -- over the lower gradient. Require contrast at the darkest lit shade.
  local darkContrast = (darkest + 0.05) / (luminance(16, 20, 23) + 0.05)
  local style = darkContrast >= 4.5 and "[16 20 23 255 0 0 0 0]" or "[223 228 230 255 0 0 0 0]"
  local pattern = "([\r\n][ \t]*set[ \t]+[%w%.]+%.meter%.scale%.color%.lit%.%a+[ \t]+" ..
    "[!?][%w_]+{0}[ \t]+%[0 0 0 0 0 0 0 0%][ \t]+)[^\r\n]+"
  local updated, count = config:gsub(pattern, function(prefix) return prefix .. style end)
  assert(count == 8, "Could not find all track and master lit meter scale settings in the theme.")
  return updated
end

local function scaleGrid(config, brightness)
  for key, original in pairs(gridColors) do
    -- Theme integers store red in the low byte.
    local r = channel((original & 255) * brightness / 100)
    local g = channel((original >> 8 & 255) * brightness / 100)
    local b = channel((original >> 16 & 255) * brightness / 100)
    config = setNumber(config, key, r | g << 8 | b << 16)
  end
  return config
end

local function appearanceConfig(get, exists)
  for _, name in ipairs(meterImages) do
    assert(exists(name), "Load the updated Studio Graphite Console theme with customizable meter strips.")
  end
  return get(themeFile)
end

local function meterPalette(image)
  assert(image:sub(1, 8) == "\137PNG\r\n\26\n" and image:byte(26) == 3,
    "Load the updated Studio Graphite Console theme with indexed meter strips.")
  local stock, paletteOffset, paletteLength
  local pos = 9
  while pos + 11 <= #image do
    local size, kind = string.unpack(">I4c4", image, pos)
    assert(pos + size + 11 <= #image, "Invalid meter strip.")
    if kind == "sgCP" then stock = image:sub(pos + 8, pos + 7 + size) end
    if kind == "PLTE" then paletteOffset, paletteLength = pos, size end
    if kind == "IEND" then break end
    pos = pos + size + 12
  end
  assert(stock and paletteLength and #stock == paletteLength / 3 * 4,
    "Missing Studio Graphite Console meter palette.")
  return stock, paletteOffset, paletteLength
end

local function meterColor(image)
  local stock, paletteOffset = meterPalette(image)
  local base = string.pack(">I3I1", M.defaultMeter, 255)
  for i = 1, #stock, 4 do
    if stock:sub(i, i + 3) == base then
      return string.unpack(">I3", image, paletteOffset + 8 + 3 * ((i - 1) // 4))
    end
  end
  error("Missing Studio Graphite Console base meter color.")
end

local function tintMeter(image, rgb)
  local stock, paletteOffset, paletteLength = meterPalette(image)
  local red, green, blue = rgb >> 16, rgb >> 8 & 255, rgb & 255
  local baseRed, baseGreen, baseBlue = M.defaultMeter >> 16, M.defaultMeter >> 8 & 255, M.defaultMeter & 255
  local palette = {}
  local darkest = 1
  -- sgCP records the original RGB and tint weight for each index. Zero-weight
  -- entries include the unlit bands and amber, so their colors always stay fixed.
  for i = 1, #stock, 4 do
    local r, g, b, tint = stock:byte(i, i + 3)
    if tint == 255 then
      r, g, b = r * red / baseRed, g * green / baseGreen, b * blue / baseBlue
    elseif tint > 0 then
      local weight = tint / 255
      r, g, b = r + (red - baseRed) * weight, g + (green - baseGreen) * weight, b + (blue - baseBlue) * weight
    end
    r, g, b = channel(r), channel(g), channel(b)
    palette[#palette + 1] = string.char(r, g, b)
    -- Leave the amber transition and inactive bands out of the contrast check.
    if tint == 255 then
      darkest = math.min(darkest, luminance(r, g, b))
    end
  end
  local chunk = "PLTE" .. table.concat(palette)
  return image:sub(1, paletteOffset + 3) .. chunk .. string.pack(">I4", files.crc32(chunk)) ..
    image:sub(paletteOffset + paletteLength + 12), darkest
end

function M.read(path)
  return pcall(files.read, path, function(get, exists)
    local grid, interlaced = readSettings(appearanceConfig(get, exists))
    return grid, meterColor(get("meter_strip_v.png")), interlaced
  end)
end

function M.apply(path, brightness, rgb, interlaced)
  local ok, result, changed = pcall(files.edit, path, function(get, exists)
    assert(math.tointeger(brightness) and brightness >= M.minGrid and brightness <= M.maxGrid,
      "Gridline brightness is out of range.")
    assert(math.tointeger(rgb) and rgb >= 0 and rgb <= 0xffffff, "Invalid meter color.")
    assert(type(interlaced) == "boolean", "Invalid meter interlacing setting.")
    local config = appearanceConfig(get, exists)
    local savedGrid, savedInterlaced = readSettings(config)
    local updates = {}
    if brightness ~= savedGrid then
      config = setSetting(scaleGrid(config, brightness), gridSetting, brightness ~= M.defaultGrid and brightness)
    end
    local darkest = 1
    for _, name in ipairs(meterImages) do
      local image, minimum = tintMeter(get(name), rgb)
      updates[name] = image
      darkest = math.min(darkest, minimum)
    end
    local layout = setRmsReadout(get("rtconfig.txt"), rgb)
    updates["rtconfig.txt"] = setLitMeterScale(layout, darkest)
    if interlaced ~= savedInterlaced then
      config = setNumber(config, "col_vudoint", interlaced and 0 or 1)
    end
    updates[themeFile] = config
    return updates
  end)
  if not ok then return nil, tostring(result) end
  return result, changed
end

return M
