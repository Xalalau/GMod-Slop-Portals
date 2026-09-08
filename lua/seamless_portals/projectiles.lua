-- F06: Known native projectile entities are not ordinary props or hitscan.
-- Predict contact of the leading shape BEFORE the portal collider consumes it.
if not SERVER then return end
local SP=SeamlessPortals
local enabled=CreateConVar("seamless_portals_projectiles","1",bit.bor(FCVAR_ARCHIVE,FCVAR_REPLICATED),"Transport supported native projectiles through damage-enabled portals",0,1)
SP.ProjectileClasses=SP.ProjectileClasses or {
    rpg_missile=true,npc_grenade_frag=true,crossbow_bolt=true,prop_combine_ball=true,
    grenade_ar2=true,grenade_helicopter=true,
}
SP.ProjectileCandidates=SP.ProjectileCandidates or setmetatable({},{__mode="k"})
local tracked=SP.ProjectileCandidates
local function register(ent)
    if IsValid(ent) and SP.ProjectileClasses[ent:GetClass()] then tracked[ent]={} end
end
hook.Add("OnEntityCreated","seamless_portals_projectiles",register)
for _,ent in ipairs(ents.GetAll()) do register(ent) end
local function split_grenade_trail(ent)
    if ent:GetClass()~="npc_grenade_frag" then return end
    local native=ent:GetInternalVariable("m_pGlowTrail")
    local old=SP.IsLiveEntity(ent.SEAMLESS_PORTALS_GRENADE_TRAIL) and ent.SEAMLESS_PORTALS_GRENADE_TRAIL or native
    if not SP.IsLiveEntity(old) or old:GetClass()~="env_spritetrail" or old:GetParent()~=ent then return end
    local attachment=old:GetInternalVariable("m_nAttachment") or 0
    local lifetime=old:GetInternalVariable("lifetime") or 0.5
    local trail=util.SpriteTrail(ent,attachment,old:GetColor(),true,
        old:GetInternalVariable("startwidth") or 8,old:GetInternalVariable("endwidth") or 1,
        lifetime,old:GetInternalVariable("m_flTextureRes") or 0,old:GetModel())
    if not SP.IsLiveEntity(trail) then return end
    trail:SetRenderMode(old:GetRenderMode()) trail:SetRenderFX(old:GetRenderFX())
    for _,key in ipairs({"m_nBrightness","m_flStartWidthVariance","m_flMinFadeLength","HDRColorScale"}) do
        local value=old:GetInternalVariable(key)
        if value~=nil then trail:SetSaveValue(key,value) end
    end
    -- Native trails retain client-side world positions across SetPos. Their
    -- internal entity handles are read-only in GLua; keep the original hidden
    -- for native fuse cleanup and replace only our visible trail at each jump.
    if SP.IsLiveEntity(native) then native:SetNoDraw(true) end
    if old~=native then old:Remove() end
    ent.SEAMLESS_PORTALS_GRENADE_TRAIL=trail
    ent:DeleteOnRemove(trail)
end
function SP.ProjectileCrossing(ent,delta)
    local best
    for _,entry in ipairs(SP.Portals) do
        local exit=SP.IsPortal(entry) and entry:GetExitPortal()
        if SP.IsUsableLink(entry,exit) and SP.LinkAllows(entry,exit,"damage") then
            local bounds=SP.PortalOBB(entry,ent)
            local support=math.max(0,SP.PlaneDistance(entry,ent:GetPos())-bounds.lo.z)
            local hit=SP.PlaneCrossing(entry,ent:GetPos(),delta,0,support)
            if hit and (not best or hit.fraction<best.fraction) then
                local fit=SP.PortalOBB(entry,ent,hit.center,ent:GetAngles())
                if fit.fits then best=hit end
            end
        end
    end
    return best
end
function SP.TraceReturningBolt(ent,record,dt)
    if not record.returning or record.consumed or ent:GetClass()~="crossbow_bolt"
        or not enabled:GetBool() then return false end
    local owner=ent:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return false end
    local velocity=ent:GetVelocity()
    if not SP.FiniteVector(velocity) or velocity:LengthSqr()<1 then return false end
    local raw=SP.RawTraceLine or SP.TraceLine or util.TraceLine
    -- An entity filter also excludes its owner in native traces. A function
    -- excludes only the bolt, so a returning bolt can hit its original shooter.
    local trace=raw({start=ent:GetPos(),endpos=ent:GetPos()+velocity*dt,
        filter=function(target) return target~=ent end,mask=MASK_SHOT,SeamlessIgnore=true})
    if not trace.Hit or trace.Entity~=owner then return false end
    local damage=tonumber(ent:GetInternalVariable("m_iDamage"))
    if not SP.IsFinite(damage) or damage<0 then return false end
    record.consumed=true
    local info=DamageInfo()
    info:SetDamage(damage) info:SetDamageType(bit.bor(DMG_BULLET,DMG_NEVERGIB))
    info:SetAttacker(owner) info:SetInflictor(ent)
    info:SetDamagePosition(trace.HitPos)
    info:SetDamageForce(velocity:GetNormalized()*damage*210)
    owner:DispatchTraceAttack(info,trace,velocity:GetNormalized())
    if IsValid(ent) then ent:EmitSound("Weapon_Crossbow.BoltHitBody") ent:Remove() end
    SP.CountField("projectile_owner_hits")
    return true
end
function SP.TransferProjectile(ent,dt,record)
    if not enabled:GetBool() or not IsValid(ent) or not SP.ProjectileClasses[ent:GetClass()]
        or not SP.HasTraversablePortals() then return false end
    record=record or tracked[ent] or {}
    if record.tick==engine.TickCount() then return false end
    if IsValid(ent:GetParent()) or ent:GetPhysicsObjectCount()>1 then return false end
    local phys=ent:GetPhysicsObject()
    local velocity=IsValid(phys) and phys:GetVelocity() or ent:GetVelocity()
    if not SP.FiniteVector(velocity) or velocity:LengthSqr()<1 then return false end
    local step=math.Clamp(dt or engine.TickInterval(),0,0.05)
    -- Frag VPhysicsUpdate raycasts one more step after physics moves it and
    -- bounces off the portal before our next Tick. Cover both steps up front.
    if ent:GetClass()=="npc_grenade_frag" then step=step*2 end
    local hit=SP.ProjectileCrossing(ent,velocity*step)
    if not hit then return false end
    local entry,exit=hit.entry,hit.exit
    -- A wall or prop BEFORE the aperture still blocks the real projectile.
    local raw=SP.RawTraceLine or SP.TraceLine or util.TraceLine
    local obstacle=raw({start=ent:GetPos(),endpos=hit.center,filter={ent,entry,ent:GetOwner()},
        mask=MASK_SOLID,SeamlessIgnore=true})
    if obstacle.StartSolid or obstacle.AllSolid or (obstacle.Hit and (obstacle.Fraction or 0)<0.999) then
        SP.CountField("projectile_source_blocked") return false
    end
    local destination,angle=SP.TransformPortal(entry,exit,hit.center,ent:GetAngles())
    local bounds=SP.PortalOBB(exit,ent,destination,angle)
    if not bounds.fits then SP.CountField("projectile_exit_aperture_blocked") return false end
    local new_velocity=SP.TransformDirection(entry,exit,velocity,false)
    local direction=new_velocity:GetNormalized()
    local outward=direction:Dot(exit:GetUp())
    if outward<=1e-6 then return false end
    -- Clear the leading shape along its ray. A normal-only push moves oblique
    -- energy balls onto a different trajectory.
    local push=direction*(math.max(0,0.1-bounds.lo.z)/outward)
    destination=destination+push
    local corridor=raw({start=hit.mapped+exit:GetUp()*0.05,endpos=destination,
        filter={ent,exit},mask=MASK_SOLID,SeamlessIgnore=true})
    if corridor.StartSolid or corridor.AllSolid or corridor.Hit then return false end
    -- Test the transformed real shape conservatively. Do not disable world
    -- collisions or delete the projectile if its destination is obstructed.
    local lo,hi=Vector(math.huge,math.huge,math.huge),Vector(-math.huge,-math.huge,-math.huge)
    for _,point in ipairs(SP.EntityCorners(ent,destination,angle)) do
        point=point-destination
        for axis=1,3 do lo[axis]=math.min(lo[axis],point[axis]) hi[axis]=math.max(hi[axis],point[axis]) end
    end
    local block=util.TraceHull({start=destination,endpos=destination,mins=lo,maxs=hi,
        filter={ent,exit},mask=MASK_SOLID,SeamlessIgnore=true})
    if block.StartSolid or block.AllSolid or block.Hit then SP.CountField("projectile_exit_blocked") return false end
    local body_pos,body_angle
    if IsValid(phys) then
        body_pos,body_angle=SP.TransformPortal(entry,exit,phys:GetPos()+hit.center-ent:GetPos(),phys:GetAngles())
        body_pos=body_pos+push
    end
    -- Identity, owner, damage settings, native fuse and callbacks are untouched.
    local source_pos=ent:GetPos()
    split_grenade_trail(ent)
    ent:SetPos(destination) ent:SetAngles(angle)
    if IsValid(phys) then
        phys:SetPos(body_pos) phys:SetAngles(body_angle) phys:SetVelocityInstantaneous(new_velocity) phys:Wake()
    else ent:SetLocalVelocity(new_velocity) end
    if SP.ResetToolTrail then SP.ResetToolTrail(ent,source_pos) end
    record.tick=engine.TickCount() record.exit=exit record.returning=true tracked[ent]=record
    SP.CountField("projectile_transfers")
    SP.RunSafeHook("SeamlessPortalsProjectileTransferred",ent,entry,exit)
    return true
end
hook.Add("Tick","seamless_portals_projectiles",function()
    for ent,record in pairs(tracked) do
        if not IsValid(ent) then tracked[ent]=nil
        else
            local dt=engine.TickInterval()
            if not SP.TraceReturningBolt(ent,record,dt) and SP.TransferProjectile(ent,dt,record) then
                SP.TraceReturningBolt(ent,record,dt)
            end
        end
    end
end)
hook.Add("PostCleanupMap","seamless_portals_projectiles_reset",function()
    for ent in pairs(tracked) do tracked[ent]=nil end
    for _,ent in ipairs(ents.GetAll()) do register(ent) end
end)
