AddCSLuaFile()
local enabled = CreateConVar("seamless_portals_debug_movement", "0", FCVAR_NONE, "Record bounded local movement diagnostics", 0, 1)
local records = setmetatable({}, {__mode = "k"})
function SeamlessPortals.RecordMovement(ply, mv, stage)
    if not enabled:GetBool() then return end
    local ring = records[ply] or {next = 1, values = {}}
    records[ply] = ring
    local mins, maxs = ply:GetHull()
    ring.values[ring.next] = {stage = stage, command = ply.SEAMLESS_PORTALS_DEBUG_COMMAND,
        tick = engine.TickCount(), realm = SERVER and "server" or "client",
        position = Vector(mv:GetOrigin()), velocity = Vector(mv:GetVelocity()),
        hull_mins = Vector(mins), hull_maxs = Vector(maxs)}
    ring.next = ring.next % 256 + 1
end
hook.Add("SetupMove", "seamless_portals_debug_command", function(ply, _, cmd)
    if enabled:GetBool() then ply.SEAMLESS_PORTALS_DEBUG_COMMAND = cmd:CommandNumber() end
end)
concommand.Add("seamless_portals_dump_movement", function(caller)
    if SERVER and IsValid(caller) and not caller:IsAdmin() then return end
    for ply, ring in pairs(records) do
        print("[Seamless Portals] movement", ply, "next slot", ring.next)
        PrintTable(ring.values)
    end
end)

if SERVER then
    local sweep = CreateConVar("seamless_portals_debug_sweeps", "0", FCVAR_NONE, "Observe bounded swept-center crossing candidates", 0, 1)
    local previous = setmetatable({}, {__mode = "k"})
    local events, cursor, was_enabled = {}, 1, false
    hook.Add("Tick", "seamless_portals_debug_sweeps", function()
        if not sweep:GetBool() then
            if was_enabled then previous = setmetatable({}, {__mode = "k"}) end
            was_enabled = false
            return
        end
        was_enabled = true
        -- Debug-only cap: NOT a complete broadphase or a production admission algorithm.
        local props = ents.FindByClass("prop_physics")
        for i = 1, math.min(#props, 128) do
            local ent = props[i]
            local now = ent:LocalToWorld(ent:OBBCenter())
            local before = previous[ent]
            previous[ent] = Vector(now)
            if before then
                for j = 1, math.min(#SeamlessPortals.Portals, 64) do
                    local portal = SeamlessPortals.Portals[j]
                    if SeamlessPortals.IsPortal(portal) then
                        local normal, origin = portal:GetUp(), portal:GetPos()
                        local a, b = (before - origin):Dot(normal), (now - origin):Dot(normal)
                        if a > 0 and b <= 0 then
                            local point = portal:WorldToLocal(before + (now - before) * (a / (a - b)))
                            local size = portal:GetSize()
                            if math.abs(point[1]) <= size[1] / 2 and math.abs(point[2]) <= size[2] / 2 then
                                events[cursor] = {tick = engine.TickCount(), entity = ent:EntIndex(),
                                    portal = portal:EntIndex(), admitted = ent.SEAMLESS_PORTALS_CUTOUT ~= nil,
                                    distance = now:Distance(before)}
                                cursor = cursor % 128 + 1
                            end
                        end
                    end
                end
            end
        end
    end)
    concommand.Add("seamless_portals_dump_sweeps", function(caller)
        if IsValid(caller) and not caller:IsAdmin() then return end
        print("[Seamless Portals] swept-center candidates; next slot", cursor)
        PrintTable(events)
    end)
end
