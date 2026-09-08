local max_distance = CreateConVar("seamless_portals_pvs_maxdistance", "500", FCVAR_ARCHIVE, "Maximum accepted draw-distance multiplier", 0, 2000)
local max_origins = CreateConVar("seamless_portals_pvs_maxorigins", "8", FCVAR_ARCHIVE, "Maximum distinct exit origins per player visibility pass", 0, 64)
SeamlessPortals.PVSStats = setmetatable({}, {__mode = "k"})
hook.Add("SetupPlayerVisibility", "seamless_portals", function(ply, view_entity)
    if not IsValid(ply) or #SeamlessPortals.Portals == 0 then return end
    local requested = ply:GetInfoNum("seamless_portals_drawdistance", 250)
    if not SeamlessPortals.IsFinite(requested) then requested = 250 end
    local distance = math.Clamp(requested, 0, max_distance:GetFloat())
    local cap = max_origins:GetInt()
    if distance == 0 or cap <= 0 then return end
    local remote_camera = IsValid(view_entity) and view_entity ~= ply
    local eye_pos = remote_camera and view_entity:GetPos() or ply:EyePos()
    local eye_ang = remote_camera and view_entity:GetAngles() or ply:EyeAngles()
    local candidates = {}
    for _, portal in ipairs(SeamlessPortals.Portals) do
        if SeamlessPortals.IsPortal(portal) then
            local exit = portal:GetExitPortal()
            if SeamlessPortals.IsUsableLink(portal, exit)
                and (remote_camera or ply:TestPVS(portal))
                and SeamlessPortals.ShouldRender(portal, eye_pos, eye_ang, distance) then
                candidates[#candidates + 1] = {exit = exit, distance = portal:GetPos():DistToSqr(eye_pos), id = portal:EntIndex()}
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.distance == b.distance then return a.id < b.id end
        return a.distance < b.distance
    end)
    local seen, submitted = {}, 0
    for _, candidate in ipairs(candidates) do
        if not seen[candidate.exit] then
            AddOriginToPVS(candidate.exit:GetPos())
            seen[candidate.exit] = true
            submitted = submitted + 1
            if submitted >= cap then break end
        end
    end
    SeamlessPortals.PVSStats[ply] = {candidates = #candidates, origins = submitted, distance = distance}
end)
