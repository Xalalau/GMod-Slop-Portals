-- Context-menu selection crosses portals; Sandbox's server range check does not.
if not SERVER then return end
local SP = SeamlessPortals
if not properties or not isfunction(properties.CanBeTargeted) then return end

SP.PropertyOwnership = SP.PropertyOwnership or {
    base = properties.CanBeTargeted,
    budgets = setmetatable({}, {__mode = "k"})
}
local state = SP.PropertyOwnership

function SP.CanTargetPropertyThroughPortal(ent, ply)
    if not SP.IsLiveEntity(ent) or not SP.IsLiveEntity(ply) or not ply:IsPlayer() then return false end
    local cv = GetConVar("seamless_portals_global_trace")
    if not cv or not cv:GetBool() or not SP.HasTraversablePortals() then return false end

    local source, target = ply:GetShootPos(), ent:LocalToWorld(ent:OBBCenter())
    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
    if not SP.FiniteVector(source) or not SP.FiniteVector(target)
        or not SP.FiniteVector(mins) or not SP.FiniteVector(maxs) then return false end
    -- Match the native OBB allowance; only extend a rejection caused by range.
    local range = 1024 + math.max(math.abs(mins.x) + maxs.x,
        math.abs(mins.y) + maxs.y, math.abs(mins.z) + maxs.z)
    if source:Distance(target) <= range or not state.base(ent) then return false end

    local tick = engine.TickCount()
    local budget = state.budgets[ply]
    if not budget or budget.tick ~= tick then
        budget = {tick = tick, remaining = 16}
        state.budgets[ply] = budget
    end
    for i, entry in ipairs(SP.Portals) do
        if i > 64 or budget.remaining <= 0 then break end
        local exit = SP.IsPortal(entry) and entry:GetExitPortal()
        if SP.IsUsableLink(entry, exit) then
            budget.remaining = budget.remaining - 1
            local path = SP.PortalSight(entry, exit, source, target, ply, ent)
            if path and path.distance <= range then return true end
        end
    end
    return false
end

-- Property Receive/Filter callbacks still enforce CanProperty on the real target.
-- Keep one wrapper across refreshes and preserve any later addon's outer wrapper.
if not state.wrapper then
    state.wrapper = function(ent, ply)
        local result = state.base(ent, ply)
        if result then return result end
        if SP.CanTargetPropertyThroughPortal(ent, ply) then return true end
        return result
    end
    properties.CanBeTargeted = state.wrapper
end
hook.Add("ShutDown", "seamless_portals_properties", function()
    if properties.CanBeTargeted == state.wrapper then properties.CanBeTargeted = state.base end
end)
