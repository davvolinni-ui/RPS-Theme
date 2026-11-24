-- @noindex
local folder = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local files = dofile(folder .. "theme_files.lua")
local M = {}

local dockerKeys = {DockerLeft = true, DockerRight = true, DockerBottom = true}

local function commandPattern(key)
  assert(key:match("^%a+$"), "Invalid button key.")
  if dockerKeys[key] or key == "Quantize" then
    return "(custom%s+trans%.custom%.sgc" .. key .. "%a*%s+''%s+)(%S+)"
  end
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
function M.applyAll(path, commands)
  local ok, result, changed = pcall(files.edit, path, function(get)
    local config = get("rtconfig.txt")
    local hasHighlights = config:find("define_parameter%s+rpsTransActiveMask%s")
    for key, command in pairs(commands) do
      assert(command:match("^%d+$") or command:match("^_[%w_]+$"), "Invalid command ID.")
      local hasActiveVariant = config:find("custom%s+trans%.custom%.rps" .. key .. "On%s")
      local quantizeActive = key == "Quantize" and config:find("custom%s+trans%.custom%.sgcQuantizeOn%s")
      local rpsActive = not dockerKeys[key] and key ~= "Quantize" and
        (hasActiveVariant or (key ~= "Settings" and hasHighlights))
      local expected = (quantizeActive or rpsActive) and 4 or 2
      local count
      config, count = config:gsub(commandPattern(key), function(prefix) return prefix .. command end)
      assert(count == expected, "The theme does not contain all variants of " .. key .. ".")
      if dockerKeys[key] or key == "Quantize" then
        local bound = tonumber(command) == 0 and "0" or "1"
        config = config:gsub("(set%s+sgc" .. key .. "Bound%s+)[01](%s)", function(prefix, ending)
          return prefix .. bound .. ending
        end)
      end
    end
    return {["rtconfig.txt"] = config}
  end)
  if not ok then return nil, tostring(result) end
  return result, changed
end

function M.apply(path, key, command)
  return M.applyAll(path, {[key] = command})
end

return M
