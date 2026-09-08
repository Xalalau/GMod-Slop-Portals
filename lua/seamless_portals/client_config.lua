if not CLIENT then return end
SeamlessPortals.ClientConVars = SeamlessPortals.ClientConVars or {}
local definitions = {
    size_x = {"100", 1, 1000, "Portal X size"},
    size_y = {"100", 1, 1000, "Portal Y size"},
    size_z = {"8", 1, 100, "Portal thickness (tool UI range)"},
    sides = {"4", 3, 100, "Integral polygon sides"},
    backface = {"1", 0, 1, "Draw portal backface"},
    align = {"1", 0, 1, "Nudge portals from walls"},
    toolsided = {"1", 0, 1, "Make the tooled side the front"},
    snap_angle = {"90", 0, 90, "Fitter angle snap"},
    drawdistance = {"250", 0, 2000, "Portal render distance multiplier"}
}
for key, definition in pairs(definitions) do
    local name = "seamless_portals_" .. key
    SeamlessPortals.ClientConVars[key] = GetConVar(name)
        or CreateClientConVar(name, definition[1], key == "drawdistance", true, definition[4], definition[2], definition[3])
end
