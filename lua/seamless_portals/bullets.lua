-- Continue actual pellet impacts, not a center ray that ignores native spread.
local SP = SeamlessPortals
local enabled = CreateConVar("seamless_portals_damage", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "Relay supported hitscan damage through portals", 0, 1)
SP.BulletContinuationDepth = SP.BulletContinuationDepth or 0
local function shallow(t)
    local c = {} for k,v in pairs(t) do c[k] = v end return c
end
local function final_callback(callback, attacker, trace, damage)
    if callback then return callback(attacker, trace, damage) end
end
function SP.PortalBulletCallback(shooter, data, original, hops, inherited_visual)
    return function(attacker, tr, damage)
        local visual=inherited_visual or (SP.NewBulletVisual and SP.NewBulletVisual(shooter,data))
        local function finish(result)
            if hops==0 and SP.SendBulletVisual then SP.SendBulletVisual(visual,result) end
            return result
        end
        -- Metadata belongs to this segment, not a nested closure from an older
        -- segment. In particular, force must rotate exactly once per traversal.
        local metadata = data.SeamlessDamageMetadata
        if metadata then
            damage:SetDamageType(metadata.type)
            damage:SetDamageCustom(metadata.custom)
            if IsValid(metadata.inflictor) then damage:SetInflictor(metadata.inflictor) end
            damage:SetDamageForce(metadata.force)
        end
        local start = tr.StartPos or data.Src
        if SP.AddBulletVisual then SP.AddBulletVisual(visual,start,tr.HitPos) end
        local direction = (tr.HitPos-start):GetNormalized()
        if direction:LengthSqr() < 0.5 then direction = data.Dir:GetNormalized() end
        if not enabled:GetBool() or not IsValid(shooter)
            or not SP.CanCrossTrace(tr, start, direction, "damage") then
            return finish(final_callback(original, attacker, tr, damage))
        end
        -- An exhausted portal path is a terminal surface; never double-apply damage.
        if hops >= 8 or SP.BulletContinuationDepth >= 8 then finish() return {damage=false, effects=false} end
        local entry, exit = tr.Entity, tr.Entity:GetExitPortal()
        local range = (data.Distance or 56756) - start:Distance(tr.HitPos)
        local next_dir = SP.TransformDirection(entry, exit, direction, false):GetNormalized()
        local clearance = ((data.HullSize or 0)+0.05) / math.max(next_dir:Dot(exit:GetUp()), 0.001)
        if not SP.IsFinite(range) or range <= clearance then finish() return {damage=false, effects=false} end
        local next_data = shallow(data)
        next_data.Src = SP.TransformPortal(entry, exit, tr.HitPos) + next_dir * clearance
        next_data.Dir, next_data.Spread, next_data.Num = next_dir, Vector(0,0,0), 1
        next_data.Distance = range-clearance
        -- Weapons often explicitly ignore their owner on the initial ray. That
        -- immunity belongs to the source room, not the unfolded continuation.
        if next_data.IgnoreEntity==shooter or next_data.IgnoreEntity==attacker then next_data.IgnoreEntity=nil end
        -- Keep unrelated exclusions, such as a vehicle the weapon is mounted on.
        next_data.Attacker = IsValid(attacker) and attacker or shooter
        -- Damage=0 requests ammo-defined damage; replacing it with the damage
        -- calculated against the portal can change damage to players/NPCs.
        next_data.Damage = data.Damage == nil and damage:GetDamage() or data.Damage
        next_data.SeamlessDamageMetadata = {
            type=damage:GetDamageType(), custom=damage:GetDamageCustom(),
            inflictor=damage:GetInflictor(),
            force=SP.TransformDirection(entry, exit, damage:GetDamageForce(), false),
        }
        next_data.Callback = SP.PortalBulletCallback(shooter, next_data, original, hops+1, visual)
        SP.BulletContinuationDepth = SP.BulletContinuationDepth+1
        local ok, err = xpcall(function()
            if SP.FirePortalContinuation then SP.FirePortalContinuation(shooter,next_data)
            else shooter:FireBullets(next_data) end
        end, debug.traceback)
        SP.BulletContinuationDepth = SP.BulletContinuationDepth-1
        if not ok then ErrorNoHalt("[Seamless Portals] Bullet continuation: "..tostring(err).."\n") end
        finish()
        return {damage=false, effects=false}
    end
end
hook.Add("EntityFireBullets", "seamless_portal_detour_bullet", function(entity, data)
    if not enabled:GetBool() or SP.BulletContinuationDepth > 0 or not SP.HasTraversablePortals() then return end
    if not SP.FiniteVector(data.Src) or not SP.FiniteVector(data.Dir) then return end
    if not SP.IsFinite(data.Distance or 56756) or (data.Distance or 56756) <= 0 then return end
    if not SP.IsFinite(data.HullSize or 0) or (data.HullSize or 0) < 0 then return end
    if SP.AdjustNPCPortalBullet then SP.AdjustNPCPortalBullet(entity,data) end
    data.SeamlessTracerInterval=data.Tracer==nil and 1 or data.Tracer
    -- Suppress the native attached tracer in BOTH realms, including the first
    -- segment; render nonportal pellets too so ordinary shots are not lost.
    data.Tracer=0
    data.Callback = SP.PortalBulletCallback(entity, data, data.Callback, 0)
    return true
end)
