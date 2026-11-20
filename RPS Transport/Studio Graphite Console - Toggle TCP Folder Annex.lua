-- @noindex
local path = debug.getinfo(1, "S").source:sub(2)
local folder = path:match("^(.*[\\/])")
local filename = "Studio Graphite Console - Mixer Folder Footer.lua"
local run = loadfile(folder .. filename)
if not run then run = assert(loadfile(folder .. "../" .. filename)) end
run("tcp")
