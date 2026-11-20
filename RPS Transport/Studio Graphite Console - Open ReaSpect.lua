-- @noindex
local path = debug.getinfo(1, "S").source:sub(2)
local folder = path:match("^(.*[\\\\/])")
assert(loadfile(folder .. "Studio Graphite Console - Transport Buttons.lua"))("ReaSpect")
