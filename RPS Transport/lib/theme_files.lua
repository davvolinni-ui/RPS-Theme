-- @noindex
local M = {}
local themeFile = "Studio Graphite Console.ReaperTheme"
local images = "Studio Graphite Console/"

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

function M.crc32(data)
  local crc = 0xffffffff
  for i = 1, #data do
    crc = crc ~ data:byte(i)
    for _ = 1, 8 do crc = (crc >> 1) ~ ((crc & 1) ~= 0 and 0xedb88320 or 0) end
  end
  return (~crc) & 0xffffffff
end

local function storedEntries(data)
  local eocd
  for p = #data - 21, math.max(1, #data - 65557), -1 do
    if data:sub(p, p + 3) == "PK\5\6" and p + 21 + string.unpack("<I2", data, p + 20) == #data then
      eocd = p
      break
    end
  end
  assert(eocd, "Invalid theme ZIP directory.")
  local disk, startDisk, diskCount, count, size, offset = string.unpack("<I2I2I2I2I4I4", data, eocd + 4)
  assert(disk == 0 and startDisk == 0 and diskCount == count and count < 65535, "Unsupported theme ZIP format.")
  assert(offset + size == eocd - 1, "Invalid theme ZIP directory size.")

  local entries, named, p = {}, {}, offset + 1
  for _ = 1, count do
    assert(data:sub(p, p + 3) == "PK\1\2", "Invalid ZIP entry.")
    local nameLength, extraLength, commentLength = string.unpack("<I2I2I2", data, p + 28)
    local localOffset = string.unpack("<I4", data, p + 42)
    local name = data:sub(p + 46, p + 45 + nameLength)
    local nextEntry = p + 46 + nameLength + extraLength + commentLength
    assert(not named[name] and localOffset < offset, "Invalid theme ZIP entry: " .. name)
    local entry = {name = name, offset = localOffset, directory = data:sub(p, nextEntry - 1)}
    entries[#entries + 1], named[name], p = entry, entry, nextEntry
  end
  assert(p == eocd, "Invalid theme ZIP directory.")

  local function archiveName(name)
    return name == themeFile and name or images .. name
  end

  local function get(name)
    local entry = assert(named[archiveName(name)], "Missing theme file: " .. name)
    local flags, method = string.unpack("<I2I2", entry.directory, 9)
    local crc, packed, unpacked = string.unpack("<I4I4I4", entry.directory, 17)
    assert(method == 0 and flags & 1 == 0 and packed == unpacked,
      "Use the updated Studio Graphite Console theme package to edit " .. name .. ".")
    local lp = entry.offset + 1
    assert(data:sub(lp, lp + 3) == "PK\3\4", "Invalid ZIP header: " .. name)
    local nl, el = string.unpack("<I2I2", data, lp + 26)
    local first = lp + 30 + nl + el
    local contents = data:sub(first, first + packed - 1)
    assert(first + packed - 1 <= offset and #contents == unpacked and M.crc32(contents) == crc,
      "Theme file failed its checksum: " .. name)
    return contents
  end

  local function rebuild(changed)
    local replacements, ordered = {}, {}
    for name, contents in pairs(changed) do replacements[archiveName(name)] = contents end
    for i, entry in ipairs(entries) do ordered[i] = entry end
    table.sort(ordered, function(a, b) return a.offset < b.offset end)
    local position = ordered[1].offset
    local records = {data:sub(1, position)}
    for i, entry in ipairs(ordered) do
      local name, directory = entry.name, entry.directory
      local nextOffset = ordered[i + 1] and ordered[i + 1].offset or offset
      assert(nextOffset > entry.offset, "Overlapping theme ZIP entries.")
      local record = data:sub(entry.offset + 1, nextOffset)
      local contents = replacements[name]
      if contents then
        local crc, length = M.crc32(contents), #contents
        record = "PK\3\4" .. string.pack("<I2I2I2I2I2I4I4I4I2I2",
          20, 0, 0, 0, 0, crc, length, length, #name, 0) .. name .. contents
        directory = "PK\1\2" .. string.pack("<I2I2I2I2I2I2I4I4I4I2I2I2I2I2I4I4",
          20, 20, 0, 0, 0, 0, crc, length, length, #name, 0, 0, 0, 0, 0, position) .. name
      elseif position ~= entry.offset then
        directory = directory:sub(1, 42) .. string.pack("<I4", position) .. directory:sub(47)
      end
      entry.updatedDirectory = directory
      position = position + #record
      records[#records + 1] = record
    end

    local directory = {}
    for i, entry in ipairs(entries) do directory[i] = entry.updatedDirectory end
    directory = table.concat(directory)
    local comment = data:sub(eocd + 22)
    return table.concat(records) .. directory .. "PK\5\6" ..
      string.pack("<I2I2I2I2I4I4I2", 0, 0, count, count, #directory, position, #comment) .. comment
  end

  local function exists(name)
    return named[archiveName(name)] ~= nil
  end

  return get, rebuild, exists
end

local function open(path)
  local data = read(path)
  -- After restart REAPER may report the virtual .ReaperTheme path inside a ZIP.
  if not data and path:lower():match("%.reapertheme$") then
    path = path .. "Zip"
    data = read(path)
  end
  assert(data, "Cannot read the active theme: " .. path)
  if path:lower():match("%.reaperthemezip$") then
    local get, rebuild, exists = storedEntries(data)
    return path, get, function(changed)
      local replacement = rebuild(changed)
      local verify = storedEntries(replacement)
      for name, contents in pairs(changed) do
        assert(verify(name) == contents, "Updated theme failed verification: " .. name)
      end
      return {{path = path, original = data, updated = replacement}}
    end, exists
  end

  local folder = assert(data:match("[\r\n]ui_img=([^\r\n]+)"), "Cannot find the active theme's image directory.")
  if not folder:match("^[/\\]") and not folder:match("^%a:") then
    folder = (path:match("^(.*[/\\])") or "") .. folder
  end
  local function loosePath(name)
    return name == themeFile and path or folder .. "/" .. name
  end
  local function get(name)
    local filename = loosePath(name)
    return assert(read(filename), "Cannot read " .. filename)
  end
  local function exists(name)
    local file = io.open(loosePath(name), "rb")
    if not file then return false end
    file:close()
    return true
  end
  return path, get, function(changed, originals)
    local files = {}
    for name, updated in pairs(changed) do
      files[#files + 1] = {path = loosePath(name), original = originals[name], updated = updated}
    end
    return files
  end, exists
end

local function save(files)
  local ok, problem = pcall(function()
    for _, file in ipairs(files) do
      local temp, backup = file.path .. ".sgc-tmp", file.path .. ".sgc-backup"
      assert(not read(temp) and not read(backup), "A previous theme update needs recovery: " .. file.path)
      local stream = assert(io.open(temp, "wb"), "Cannot write beside the theme: " .. file.path)
      file.temp, file.backup = temp, backup
      local wrote, writeError = stream:write(file.updated)
      local closed = stream:close()
      assert(wrote and closed and read(temp) == file.updated, writeError or "Could not save " .. file.path)
    end
    for _, file in ipairs(files) do
      assert(read(file.path) == file.original, "Theme changed during update. Try again.")
      assert(os.rename(file.path, file.backup))
      file.backedUp = true
    end
    for _, file in ipairs(files) do
      assert(os.rename(file.temp, file.path))
      file.installed = true
    end
  end)
  for _, file in ipairs(files) do
    if not ok and file.installed then os.remove(file.path) end
    if file.backedUp then
      if ok then
        os.remove(file.backup)
      elseif not os.rename(file.backup, file.path) then
        problem = tostring(problem) .. " Original file is at " .. file.backup
      end
    end
    if file.temp then os.remove(file.temp) end
  end
  assert(ok, problem)
end

function M.read(path, reader)
  local _, get, _, exists = open(path)
  return reader(get, exists)
end

function M.edit(path, editor)
  local active, get, rebuild, exists = open(path)
  local originals = {}
  local changed = editor(function(name)
    originals[name] = originals[name] or get(name)
    return originals[name]
  end, exists)
  for name, contents in pairs(changed) do
    assert(originals[name], "Cannot update an unread theme file: " .. name)
    if contents == originals[name] then changed[name] = nil end
  end
  if not next(changed) then return active, false end
  save(rebuild(changed, originals))
  return active, true
end

return M
