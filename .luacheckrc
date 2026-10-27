-- luacheck config for layouts.lua and its tests.
std = "lua54"
max_line_length = 120
-- `hl` is Hyprland's Lua API; _CENTRE_SPLIT is the module handle layouts.lua
-- publishes for `hyprctl eval` callers (apply doctor/restore).
globals = { "hl", "_CENTRE_SPLIT" }
