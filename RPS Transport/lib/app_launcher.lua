-- @noindex
-- Independent app discovery and window focus; no toolbar installation required.
local M = {}
function M.discover(r, app)
  local resource = r.GetResourcePath():gsub('\\', '/')
  local f = io.open(resource .. '/reaper-kb.ini', 'r')
  if not f then return nil end
  local best, ambiguous
  local windows = r.GetOS():match('^Win')
  local function normalize(path)
    path = path:gsub('\\', '/')
    return windows and path:lower() or path
  end
  local root = normalize(resource .. '/Scripts/')
  for line in f:lines() do
    local section, id, path = line:match('^SCR%s+%d+%s+(%d+)%s+(%S+)%s+"[^"]+"%s+(.+)$')
    if section == '0' then
      path = path:gsub('%s+$', ''):gsub('^"(.*)"$', '%1'):gsub('\\', '/')
      local base = path:match('([^/]+)$')
      if base and normalize(base) == normalize(app.file) then
        if not path:match('^%a:/') and not path:match('^/') then path = resource .. '/Scripts/' .. path end
        local file = io.open(path, 'rb')
        if file then
          file:close()
          local named = id:sub(1, 1) == '_' and id or '_' .. id
          local command = r.NamedCommandLookup(named)
          if command > 0 and (r.kbd_getTextFromCmd(command, 0) or '') ~= '' then
            local score = normalize(path):sub(1, #root) == root and 2 or 1
            if not best or score > best.score then
              best = {id = named, command = command, path = path, score = score}; ambiguous = false
            elseif score == best.score and normalize(path) ~= normalize(best.path) then ambiguous = true end
          end
        end
      end
    end
  end
  f:close()
  if ambiguous then return nil, 'Multiple copies found. Use Custom to choose an action.' end
  return best
end
function M.window(r, app)
  if not r.JS_Window_Find then return nil end
  local function matches(title)
    return title == app.label or title == app.label .. ' EULA' or
      (title and title:sub(1, #app.label + 3) == app.label .. '###')
  end
  for _, title in ipairs({app.label, app.label .. ' EULA'}) do
    local window = r.JS_Window_Find(title, true)
    if window then return window end
  end
  if r.JS_Window_ListFind and r.JS_Window_HandleFromAddress and r.JS_Window_GetTitle then
    local _, addresses = r.JS_Window_ListFind(app.label, false)
    for address in (addresses or ''):gmatch('[^,]+') do
      local handle = r.JS_Window_HandleFromAddress(address)
      if handle and matches(r.JS_Window_GetTitle(handle)) then return handle end
    end
  end
end
function M.open(r, app, settings)
  local window = M.window(r, app)
  if window then
    if r.DockIsChildOfDock and r.DockWindowActivate then
      local dock = r.DockIsChildOfDock(window)
      if dock and dock >= 0 then r.DockWindowActivate(window) end
    end
    if r.JS_Window_SetFocus then r.JS_Window_SetFocus(window) end
    return true
  end
  local found, problem = M.discover(r, app)
  if not found then return nil, problem or (app.label .. ' not found. Install/register ' .. app.file ..
    ' in the Main Action List, or choose ' .. (app.native and 'Native or Custom' or 'Custom') .. ' in Transport Buttons.') end
  if r.GetToggleCommandStateEx(0, found.command) == 1 then return true end
  local key = 'launch_' .. app.key
  local now = r.time_precise()
  local previous = tonumber(r.GetExtState(settings, key))
  if previous and now - previous < 1.5 then return true end
  r.SetExtState(settings, key, tostring(now), false)
  r.Main_OnCommand(found.command, 0)
  return true
end
return M
