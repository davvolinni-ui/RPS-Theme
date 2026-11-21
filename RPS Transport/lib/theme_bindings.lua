-- @noindex
local folder = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local files = dofile(folder .. "theme_files.lua")
local M = {}

local function commandPattern(key)
  assert(key:match("^%a+$"), "Invalid button key.")
  return "(custom%s+trans%.custom%.rps" .. key .. "%a*%s+''%s+)(%S+)"
end
function M.readAll(path, keys)
  local commands = {}
  local ok, config = pcall(files.read, path, function(get) return get("rtconfig.txt") end)
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
  local ok, result, changed = pcall(files.edit, path, function(get)
    assert(command:match("^%d+$") or command:match("^_[%w_]+$"), "Invalid command ID.")
    local config = get("rtconfig.txt")
    local updated, count = config:gsub(commandPattern(key), function(prefix) return prefix .. command end)
    local hasHighlights = config:find("define_parameter%s+rpsTransActiveMask%s")
    local hasActiveVariant = config:find("custom%s+trans%.custom%.rps" .. key .. "On%s")
    local expected = (hasActiveVariant or (key ~= "Settings" and hasHighlights)) and 4 or 2
    assert(count == expected, "The theme does not contain all variants of this button.")
    return {["rtconfig.txt"] = updated}
  end)
  if not ok then return nil, tostring(result) end
  return result, changed
end

return M
