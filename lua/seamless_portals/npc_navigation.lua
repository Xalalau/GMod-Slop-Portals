-- Native ground navigation supplies the approach path; Lua owns only the link.
if not SERVER then return end
local SP = SeamlessPortals
if SP.CleanupNPCNavigation then SP.CleanupNPCNavigation() end
local enabled = CreateConVar("seamless_portals_npc_navigation", "1", FCVAR_ARCHIVE,
    "Allow native ground NPCs to route through walkable portals", 0, 1)
SP.NPCNavigation = setmetatable({}, {__mode = "k"})
SP.NPCPassages = setmetatable({}, {__mode = "k"})
local routes = SP.NPCNavigation
local passages = SP.NPCPassages
local retry = setmetatable({}, {__mode = "k"})
local world_up = Vector(0, 0, 1)

local function allowed(npc)
    local disabled = GetConVar("ai_disabled")
    return enabled:GetBool() and SP.IsLiveEntity(npc) and npc:IsNPC()
        and not npc:IsScripted() and npc:Health() > 0
        and npc:GetNPCState() ~= NPC_STATE_SCRIPT and npc:GetMoveType() == MOVETYPE_STEP
        and bit.band(npc:CapabilitiesGet(), CAP_MOVE_GROUND) ~= 0
        and not IsValid(npc:GetParent()) and not (disabled and disabled:GetBool())
end

local function targetAllowed(target)
    if not SP.IsLiveEntity(target) or target.SEAMLESS_PORTALS_NPC_PROXY then return false end
    if target:IsNPC() and target:Health() <= 0 then return false end
    if target:IsPlayer() then
        local ignore = GetConVar("ai_ignoreplayers")
        return target:Alive() and not (ignore and ignore:GetBool())
            and not target:IsFlagSet(FL_NOTARGET)
    end
    return true
end

local function walkable(entry, exit)
    if entry == exit or not SP.LinkAllows(entry, exit, "props") then return false end
    -- A walking hull stays upright. Floor/ceiling and rolled exits need a
    -- different locomotion adapter, rather than forcing a ground NPC to fly.
    return math.abs(entry:GetUp().z) < 0.05 and math.abs(exit:GetUp().z) < 0.05
        and SP.TransformDirection(entry, exit, world_up, false):Dot(world_up) > 0.99
end

local function hull(npc)
    local lo, hi = npc:GetCollisionBounds()
    if not SP.FiniteVector(lo) or not SP.FiniteVector(hi) then return end
    for axis = 1, 3 do if hi[axis] <= lo[axis] then return end end
    return lo, hi
end

local function support(lo, hi, normal)
    return -(math.min(lo.x * normal.x, hi.x * normal.x)
        + math.min(lo.y * normal.y, hi.y * normal.y) + math.min(lo.z * normal.z, hi.z * normal.z))
end

local function fits(portal, pos, lo, hi)
    -- Native ground NPCs use an axis-aligned movement hull, not a rotated model.
    for x = 0, 1 do for y = 0, 1 do for z = 0, 1 do
        local p = pos + Vector(x == 0 and lo.x or hi.x, y == 0 and lo.y or hi.y, z == 0 and lo.z or hi.z)
        if not SP.InAperture(portal, p) then return false end
    end end end
    return true
end

local function traceHull(npc, entry, exit, from, to, lo, hi)
    return util.TraceHull({start = from, endpos = to, mins = lo, maxs = hi,
        filter = {npc, entry, exit}, mask = MASK_NPCSOLID, SeamlessIgnore = true})
end

local function blocked(trace)
    return trace.StartSolid or trace.AllSolid or trace.Hit
end

local function ground(npc, entry, exit, pos, lo, hi, drop)
    local step = math.Clamp(npc:GetStepHeight(), 0, 32)
    local tr = traceHull(npc, entry, exit, pos + world_up * step,
        pos - world_up * drop, lo, hi)
    if tr.StartSolid or tr.AllSolid or not tr.Hit or tr.HitNormal.z < 0.7 then return end
    return tr.HitPos + world_up * 0.5
end

local function approachDirection(entry, from, to)
    local direction = to - from
    direction.z = 0
    direction:Normalize()
    if direction:Dot(entry:GetUp()) >= -0.1 then return -entry:GetUp() end
    return direction
end

local function destination(npc, entry, exit, pos, lo, hi, direction)
    local center = (lo + hi) * 0.5
    direction = direction or -entry:GetUp()
    local inward = -direction:Dot(entry:GetUp())
    if inward < 0.1 then return end
    local plane = pos + center + direction * (SP.PlaneDistance(entry, pos + center) / inward)
    if not fits(entry, plane - center, lo, hi) then return end
    local mapped = SP.TransformPortal(entry, exit, plane)
    local movement = SP.TransformDirection(entry, exit, direction, false)
    movement.z = 0
    movement:Normalize()
    local outward = movement:Dot(exit:GetUp())
    if outward < 0.1 then return end
    local start = SP.TransformPortal(entry, exit, pos + center) - center
    local point = start + movement * ((support(lo, hi, exit:GetUp()) + 2 - SP.PlaneDistance(exit, start)) / outward)
    local landed = ground(npc, entry, exit, point, lo, hi, math.Clamp(npc:GetStepHeight(), 0, 32) + 1)
    if not landed or not fits(exit, landed, lo, hi) then return end
    if blocked(traceHull(npc, entry, exit, landed, landed, lo, hi)) then return end
    local raw = SP.RawTraceLine or SP.TraceLine or util.TraceLine
    if blocked(raw({start = mapped + exit:GetUp() * 0.1, endpos = landed + center,
        filter = {npc, entry, exit}, mask = MASK_NPCSOLID, SeamlessIgnore = true})) then return end
    return landed
end

local function lateralRange(portal, axis, lo, hi)
    local lower, upper = math.huge, -math.huge
    for _, vertex in ipairs(SP.ApertureVertices(portal)) do
        local distance = (portal:LocalToWorld(vertex) - portal:GetPos()):Dot(axis)
        lower, upper = math.min(lower, distance), math.max(upper, distance)
    end
    local half = (hi - lo) * 0.5
    local radius = math.abs(axis.x) * half.x + math.abs(axis.y) * half.y + math.abs(axis.z) * half.z + 2
    return lower + radius, upper - radius, radius * 2
end

-- Candidate plane points only; every chosen point still needs floor and hull checks.
function SP.NPCPortalRoutePoints(npc, entry, exit)
    if not allowed(npc) or not walkable(entry, exit) then return {} end
    local lo, hi = hull(npc)
    if not lo then return {} end
    local axis = world_up:Cross(entry:GetUp()):GetNormalized()
    local mapped = SP.TransformDirection(entry, exit, axis)
    local scale = mapped:Length()
    local lower, upper, width = lateralRange(entry, axis, lo, hi)
    local exitLower, exitUpper, exitWidth = lateralRange(exit, mapped / scale, lo, hi)
    lower, upper = math.max(lower, exitLower / scale), math.min(upper, exitUpper / scale)
    if lower > upper then return {} end
    local spacing = math.max(64, width + 4, math.max(64, exitWidth + 4) / scale)
    local halfCount = math.min(4, math.floor((upper - lower) / (spacing * 2)))
    local middle = lower <= 0 and upper >= 0 and 0 or (lower + upper) * 0.5
    local points = {entry:GetPos() + axis * middle}
    -- Sample lane centers, leaving clearance for an oblique crossing near an edge.
    for i = 1, halfCount do
        points[#points + 1] = entry:GetPos() + axis * (middle + (lower - middle) * i / (halfCount + 0.5))
        points[#points + 1] = entry:GetPos() + axis * (middle + (upper - middle) * i / (halfCount + 0.5))
    end
    return points
end

function SP.FindNPCPortalRoute(npc, target)
    if not allowed(npc) or not targetAllowed(target) then return end
    local lo, hi = hull(npc)
    if not lo then return end
    local source, goal = npc:GetPos(), target:GetPos()
    local limit = GetConVar("seamless_portals_npc_distance"):GetFloat()
    local candidates = {}
    local straightDistance = source:Distance(goal)
    local direct = straightDistance
    local nativeDistance = npc:GetPathDistanceToGoal()
    if nativeDistance > direct then direct = nativeDistance end
    local detour = not npc:Visible(target) and (SP.NPCAttention[npc] ~= nil
        or not IsValid(npc:GetEnemy()) or (nativeDistance <= 0 and npc:IsUnreachable(target)))
    for _,entry in ipairs(SP.Portals) do
        local exit = SP.IsPortal(entry) and entry:GetExitPortal()
        -- The native path can approach the front from either side of the room.
        -- Only the actual transfer requires the hull to be at the front plane.
        if walkable(entry, exit) and SP.PlaneDistance(exit, goal) >= 0 then
            local remaining = exit:GetPos():Distance(goal)
            local cost = source:Distance(entry:GetPos()) + remaining
            -- Native paths can remain long on both sides of a wall. Require
            -- progress toward the target even when that path suggests a detour.
            if cost < limit and remaining + 64 < straightDistance and (cost + 64 < direct or detour) then
                candidates[#candidates + 1] = {entry = entry, exit = exit, cost = cost}
            end
        end
    end
    table.sort(candidates, function(a, b) return a.cost < b.cost end)
    local points = {}
    for i = 1, math.min(#candidates, 4) do
        local link = candidates[i]
        for index, point in ipairs(SP.NPCPortalRoutePoints(npc, link.entry, link.exit)) do
            local mapped = SP.TransformPortal(link.entry, link.exit, point)
            local remaining = mapped:Distance(goal)
            local cost = source:Distance(point) + remaining
            if cost < limit and remaining + 64 < straightDistance and (cost + 64 < direct or detour) then
                points[#points + 1] = {entry = link.entry, exit = link.exit, point = point, cost = cost, order = index}
            end
        end
    end
    table.sort(points, function(a, b)
        if a.cost ~= b.cost then return a.cost < b.cost end
        return a.order < b.order
    end)
    for i = 1, math.min(#points, 12) do
        local r = points[i]
        local entry, exit = r.entry, r.exit
        local aim = r.point - (lo + hi) * 0.5
        aim = aim + entry:GetUp() * (support(lo, hi, entry:GetUp()) + 1 - SP.PlaneDistance(entry, aim))
        local approach = ground(npc, entry, exit, aim, lo, hi, math.max(entry:GetSize().x, entry:GetSize().y))
        if approach and fits(entry, approach, lo, hi)
            and not blocked(traceHull(npc, entry, exit, approach, approach, lo, hi)) then
            local dest = destination(npc, entry, exit, approach, lo, hi, approachDirection(entry, source, approach))
            if dest then
                r.approach, r.destination, r.target = approach, dest, target
                r.geometry = SP.CaptureGeometry(entry)
                return r
            end
        end
    end
end

local function ownsPosition(npc, r)
    local last = npc:GetInternalVariable("m_vecLastPosition")
    return SP.FiniteVector(last) and last:DistToSqr(r.approach) < 1
end

local function ownsSchedule(npc, r)
    return npc:IsCurrentSchedule(SCHED_FORCED_GO_RUN) and ownsPosition(npc, r)
end

local function routeTargetAllowed(npc, r)
    if not targetAllowed(r.target) or (r.kind ~= "goal" and npc:Disposition(r.target) ~= D_HT) then return false end
    local enemy = npc:GetEnemy()
    return not IsValid(enemy) or enemy == r.target or enemy == r.enemy
end

function SP.ClearNPCNavigation(npc, reason)
    local r = routes[npc]
    if not r then return end
    routes[npc] = nil
    retry[npc] = CurTime() + 2
    if SP.IsLiveEntity(npc) then
        if ownsSchedule(npc, r) and npc:GetNPCState() ~= NPC_STATE_SCRIPT then
            npc:ClearSchedule()
        end
        if ownsPosition(npc, r) and SP.FiniteVector(r.last) then npc:SetLastPosition(r.last) end
    end
    SP.CountField("npc_route_" .. (reason or "cancelled"))
end

local function resume(npc, r)
    if r.kind == "goal" then
        npc:SetLastPosition(r.target:GetPos())
        npc:SetSchedule(SCHED_FORCED_GO_RUN)
    else
        npc:SetEnemy(r.target)
        npc:UpdateEnemyMemory(r.target, r.target:GetPos())
        npc:SetSchedule(SCHED_CHASE_ENEMY)
    end
end

local function finishPassage(npc)
    local r = passages[npc]
    if not r then return end
    passages[npc] = nil
    if not SP.IsLiveEntity(npc) then return end
    if r.moveWait and math.abs(npc:GetMoveDelay() + CurTime() - r.moveWait) < 0.01 then
        npc:SetMoveDelay(math.max(0, r.previousMoveWait - CurTime()))
    end
    if not npc:IsCurrentSchedule(SCHED_NPC_FREEZE) then return end
    npc:ClearSchedule()
    npc:SetPlaybackRate(r.animation.rate)
    if npc:Health() <= 0 or npc:GetNPCState() == NPC_STATE_SCRIPT then return end
    -- The client blends into the native resumed pose. Forcing the old gait
    -- here makes the next native activity selection restart it a second time.
    if routeTargetAllowed(npc, r) then resume(npc, r) end
end

function SP.TransferNPCThroughPortal(npc, r)
    if routes[npc] ~= r or not allowed(npc) or not routeTargetAllowed(npc, r)
        or not walkable(r.entry, r.exit)
        or not SP.SameGeometry(r.geometry, SP.CaptureGeometry(r.entry)) then return false end
    local lo, hi = hull(npc)
    if not lo then return false end
    local source, entry, exit = npc:GetPos(), r.entry, r.exit
    local offset = source - r.approach
    if offset:Length2DSqr() > 36 or math.abs(offset.z) > 4 then return false end
    -- Native walking rests closer to the floor than our trace clearance. Use
    -- the verified clearance at the lip, sweeping the small rise before moving.
    local pos = source + world_up * math.max(0, r.approach.z - source.z)
    local radius = support(lo, hi, entry:GetUp())
    local depth = SP.PlaneDistance(entry, pos)
    if depth < radius - 2 or depth > radius + 6 or not fits(entry, pos, lo, hi) then return false end
    local contact = pos + entry:GetUp() * (radius + 0.5 - depth)
    if blocked(traceHull(npc, entry, exit, source, contact, lo, hi)) then return false end
    local direction = r.direction or approachDirection(entry, r.samplePosition or source, r.approach)
    local dest = destination(npc, entry, exit, pos, lo, hi, direction)
    if not dest then return false end
    local velocity = SP.TransformDirection(entry, exit, npc:GetVelocity(), false)
    local _, angle = SP.TransformPortal(entry, exit, nil, npc:GetAngles())
    local duration, animation
    if SP.SendNPCTransition then duration, animation = SP.SendNPCTransition(npc, entry, exit, source, dest, angle) end
    SP.ClearNPCNavigation(npc, "completed")
    npc:ClearGoal()
    npc:SetPos(dest)
    npc:SetAngles(Angle(0, angle.y, 0))
    npc:SetLocalVelocity(velocity)
    if duration and animation then
        -- Spend the normal walking time clearing the aperture before native
        -- pursuit resumes, avoiding a second movement on top of the crossing.
        r.finished, r.animation = CurTime() + duration, animation
        passages[npc] = r
        npc:SetLocalVelocity(Vector(0, 0, 0))
        -- ClearGoal leaves a stopping segment in the old room. Replace that
        -- segment and pause the motor itself, not just its schedule.
        npc:NavSetGoalPos(dest)
        npc:SetSchedule(SCHED_NPC_FREEZE)
        r.previousMoveWait = CurTime() + math.max(0, npc:GetMoveDelay())
        npc:SetMoveDelay(math.max(duration + 0.1, npc:GetMoveDelay()))
        r.moveWait = CurTime() + npc:GetMoveDelay()
    else
        resume(npc, r)
    end
    SP.NotifyTraversal(npc, entry, exit, "npc")
    return true
end

function SP.UpdateNPCNavigation(npc, players)
    if passages[npc] then return true end
    if not allowed(npc) then SP.ClearNPCNavigation(npc, "disabled") return false end
    if routes[npc] then return true end
    if CurTime() < (retry[npc] or 0) then return false end
    retry[npc] = CurTime() + 0.5
    local count = 0
    for _ in pairs(routes) do count = count + 1 end
    for _ in pairs(passages) do count = count + 1 end
    if count >= 32 then return false end
    local attention = SP.NPCAttention[npc]
    local target = attention and attention.player or npc:GetEnemy()
    local kind = "enemy"
    if not targetAllowed(target) then
        target = npc:GetGoalTarget()
        kind = "goal"
    end
    if not targetAllowed(target) then
        local hostile = {}
        for _,ply in ipairs(players) do
            if targetAllowed(ply) and npc:Disposition(ply) == D_HT then hostile[#hostile + 1] = ply end
        end
        local sight = SP.FindNPCTarget(npc, hostile)
        target, kind = sight and sight.player, "enemy"
    end
    if not targetAllowed(target) then return false end
    local r = SP.FindNPCPortalRoute(npc, target)
    if not r then return false end
    r.kind, r.last = kind, npc:GetInternalVariable("m_vecLastPosition")
    r.started, r.progress, r.remaining = CurTime(), CurTime(), npc:GetPos():DistToSqr(r.approach)
    r.samplePosition = npc:GetPos()
    SP.ClearNPCAttention(npc)
    r.enemy = npc:GetEnemy()
    routes[npc] = r
    npc:SetLastPosition(r.approach)
    npc:SetSchedule(SCHED_FORCED_GO_RUN)
    SP.CountField("npc_route_started")
    return true
end

local nextStep = 0
hook.Add("Think", "seamless_portals_npc_navigation", function()
    if CurTime() < nextStep then return end
    nextStep = CurTime() + 0.05
    for npc, r in pairs(passages) do
        if not allowed(npc) or not routeTargetAllowed(npc, r) or not walkable(r.entry, r.exit)
            or not SP.SameGeometry(r.geometry, SP.CaptureGeometry(r.entry))
            or not npc:IsCurrentSchedule(SCHED_NPC_FREEZE) or CurTime() >= r.finished then
            finishPassage(npc)
        end
    end
    for npc, r in pairs(routes) do
        if not allowed(npc) or not routeTargetAllowed(npc, r) or not walkable(r.entry, r.exit)
            or not SP.SameGeometry(r.geometry, SP.CaptureGeometry(r.entry)) then
            SP.ClearNPCNavigation(npc, "invalidated")
        elseif CurTime() - r.started > 15 or CurTime() - r.progress > 3 then
            SP.ClearNPCNavigation(npc, "stalled")
        elseif CurTime() - r.started > 0.25 and not ownsSchedule(npc, r) then
            SP.ClearNPCNavigation(npc, "interrupted")
        else
            local position = npc:GetPos()
            local movement = position - r.samplePosition
            movement.z = 0
            if movement:Length2DSqr() > 0.01 then
                local direction = movement:GetNormalized()
                if direction:Dot(r.entry:GetUp()) < -0.1 then r.direction = direction end
            end
            r.samplePosition = position
            local remaining = position:DistToSqr(r.approach)
            if remaining + 4 < r.remaining then r.remaining, r.progress = remaining, CurTime() end
            SP.TransferNPCThroughPortal(npc, r)
        end
    end
end)

function SP.CleanupNPCNavigation()
    for npc in pairs(routes) do SP.ClearNPCNavigation(npc, "cleanup") end
    for npc in pairs(passages) do finishPassage(npc) end
    for npc in pairs(retry) do retry[npc] = nil end
end
hook.Add("PostCleanupMap", "seamless_portals_npc_navigation", SP.CleanupNPCNavigation)
hook.Add("ShutDown", "seamless_portals_npc_navigation", SP.CleanupNPCNavigation)
