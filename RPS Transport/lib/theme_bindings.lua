-- @noindex
-- ZIP editing uses only Lua. The distributed theme stores rtconfig.txt uncompressed.
local M = {}
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a"); f:close(); return data
end
local function crc32(data)
  local crc = 0xffffffff
  for i = 1, #data do
    crc = crc ~ data:byte(i)
    for _ = 1, 8 do crc = (crc >> 1) ~ ((crc & 1) ~= 0 and 0xedb88320 or 0) end
  end
  return (~crc) & 0xffffffff
end
local function zipConfig(data)
  local eocd
  for p = #data - 21, math.max(1, #data - 65557), -1 do
    if data:sub(p, p + 3) == "PK\5\6" and p + 21 + string.unpack("<I2", data, p + 20) == #data then
      eocd = p; break
    end
  end
  assert(eocd, "Invalid theme ZIP directory.")
  local disk, startDisk, diskCount, count, size, offset = string.unpack("<I2I2I2I2I4I4", data, eocd + 4)
  assert(disk == 0 and startDisk == 0 and diskCount == count and count < 65535, "Unsupported theme ZIP format.")
  assert(offset + size == eocd - 1, "Invalid theme ZIP directory size.")
  local entries, target, p = {}, nil, offset + 1
  for _ = 1, count do
    assert(data:sub(p, p + 3) == "PK\1\2", "Invalid ZIP entry.")
    local flags, method = string.unpack("<I2I2", data, p + 8)
    local crc, packed, unpacked, nl, el, cl = string.unpack("<I4I4I4I2I2I2", data, p + 16)
    local localOffset = string.unpack("<I4", data, p + 42)
    local name = data:sub(p + 46, p + 45 + nl)
    local entry = data:sub(p, p + 45 + nl + el + cl)
    entries[#entries + 1] = entry
    if name == "Studio Graphite Console/rtconfig.txt" then
      assert(not target, "Duplicate rtconfig.txt in theme.")
      assert(method == 0 and flags & 1 == 0 and packed == unpacked,
        "This archive has a compressed rtconfig.txt. Use the updated theme supplied with Transport Buttons.")
      local lp = localOffset + 1
      assert(data:sub(lp, lp + 3) == "PK\3\4", "Invalid rtconfig ZIP header.")
      local ln, le = string.unpack("<I2I2", data, lp + 26)
      local first = lp + 30 + ln + le
      local config = data:sub(first, first + packed - 1)
      assert(#config == unpacked and crc32(config) == crc, "Theme configuration failed its checksum.")
      target = {index = #entries, name = name, config = config,
        appendOffset = first + packed - 1 == offset and localOffset or offset}
    end
    p = p + #entry
  end
  assert(target and p == eocd, "Theme configuration was not found.")
  return target.config, function(config)
    local name, crc, n = target.name, crc32(config), #config
    local appendOffset = target.appendOffset
    local record = "PK\3\4" .. string.pack("<I2I2I2I2I2I4I4I4I2I2", 20, 0, 0, 0, 0, crc, n, n, #name, 0) .. name .. config
    entries[target.index] = "PK\1\2" .. string.pack("<I2I2I2I2I2I2I4I4I4I2I2I2I2I2I4I4",
      20, 20, 0, 0, 0, 0, crc, n, n, #name, 0, 0, 0, 0, 0, appendOffset) .. name
    local directory = table.concat(entries)
    local comment = data:sub(eocd + 22)
    return data:sub(1, appendOffset) .. record .. directory .. "PK\5\6" ..
      string.pack("<I2I2I2I2I4I4I2", 0, 0, count, count, #directory, appendOffset + #record, #comment) .. comment
  end
end
local function source(path)
  -- REAPER can report the virtual .ReaperTheme name for an active ZIP after restart.
  local data = read(path)
  if not data and path:lower():match("%.reapertheme$") then path = path .. "Zip"; data = read(path) end
  assert(data, "Cannot read the active theme: " .. path)
  if path:lower():match("%.reaperthemezip$") then
    local config, rebuild = zipConfig(data)
    return path, data, config, rebuild
  end
  local images = data:match("[\r\n]ui_img=([^\r\n]+)")
  assert(images, "Cannot find the active theme's image directory.")
  if not images:match("^[/\\]") and not images:match("^%a:") then
    images = (path:match("^(.*[/\\])") or "") .. images
  end
  path = images .. "/rtconfig.txt"
  data = assert(read(path), "Cannot read " .. path)
  return path, data, data, function(config) return config end
end
local function commandPattern(key)
  assert(key:match("^%a+$"), "Invalid button key.")
  return "(custom%s+trans%.custom%.rps" .. key .. "%a*%s+''%s+)(%S+)"
end
function M.readAll(path, keys)
  local commands = {}
  local ok, _, _, config = pcall(source, path)
  if ok then
    for _, key in ipairs(keys) do
      local _, command = config:match(commandPattern(key))
      commands[key] = command
    end
  end
  return commands
end
function M.current(path, key)
  return M.readAll(path, {key})[key] or ""
end
function M.apply(path, key, command)
  local ok, result, changed = pcall(function()
    assert(command:match("^%d+$") or command:match("^_[%w_]+$"), "Invalid command ID.")
    local target, original, config, rebuild = source(path)
    local count, updated
    updated, count = config:gsub(commandPattern(key), function(prefix) return prefix .. command end)
    local hasHighlights = config:find("define_parameter%s+rpsTransActiveMask%s")
    local expected = (key == "Settings" or not hasHighlights) and 2 or 4
    assert(count == expected, "The theme does not contain all variants of this button.")
    if updated == config then return target, false end
    local replacement = rebuild(updated)
    if target:lower():match("%.reaperthemezip$") then
      local verified = zipConfig(replacement)
      assert(verified == updated, "Updated theme failed verification.")
    end
    local temp, backup = target .. ".bindings-tmp", target .. ".bindings-backup"
    assert(not read(temp) and not read(backup), "A previous binding update needs recovery: " .. backup)
    local f = assert(io.open(temp, "wb"), "Cannot write beside the theme. Move it to a writable folder.")
    local wrote, writeError = f:write(replacement)
    local closed = f:close()
    if not wrote or not closed or read(temp) ~= replacement then os.remove(temp); error(writeError or "Could not save the updated theme.") end
    if read(target) ~= original then os.remove(temp); error("Theme changed during update. Try again.") end
    local moved, message = os.rename(target, backup)
    if not moved then os.remove(temp); error(message) end
    local installed, installError = os.rename(temp, target)
    if not installed then
      local restored = os.rename(backup, target)
      os.remove(temp)
      error(tostring(installError) .. (restored and " Original theme restored." or " Original theme is at " .. backup))
    end
    os.remove(backup)
    return target, true
  end)
  if not ok then return nil, tostring(result) end
  return result, changed
end
return M
