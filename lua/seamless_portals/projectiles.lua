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
function SP.TransferProjectile(ent,dt,record)
    if not enabled:GetBool() or not IsValid(ent) or not SP.ProjectileClasses[ent:GetClass()]
        or not SP.HasTraversablePortals() then return false end
    record=record or tracked[ent] or {}
    if record.tick==engine.TickCount() then return false end
    if IsValid(ent:GetParent()) or ent:GetPhysicsObjectCount()>1 then return false end
    local phys=ent:GetPhysicsObject()
    local velocity=IsValid(phys) and phys:GetVelocity() or ent:GetVelocity()
    if not SP.FiniteVector(velocity) or velocity:LengthSqr()<1 then return false end
    local hit=SP.ProjectileCrossing(ent,velocity*math.Clamp(dt or engine.TickInterval(),0,0.05))
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
    local push=exit:GetUp()*math.max(0,0.1-bounds.lo.z)
    destination=destination+push
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
    local new_velocity=SP.TransformDirection(entry,exit,velocity,false)
    local body_pos,body_angle
    if IsValid(phys) then
        body_pos,body_angle=SP.TransformPortal(entry,exit,phys:GetPos()+hit.center-ent:GetPos(),phys:GetAngles())
        body_pos=body_pos+push
    end
    -- Identity, owner, damage settings, native fuse and callbacks are untouched.
    ent:SetPos(destination) ent:SetAngles(angle)
    if IsValid(phys) then
        phys:SetPos(body_pos) phys:SetAngles(body_angle) phys:SetVelocityInstantaneous(new_velocity) phys:Wake()
    else ent:SetLocalVelocity(new_velocity) end
    record.tick=engine.TickCount() record.exit=exit tracked[ent]=record
    SP.CountField("projectile_transfers")
    SP.RunSafeHook("SeamlessPortalsProjectileTransferred",ent,entry,exit)
    return true
end
hook.Add("Tick","seamless_portals_projectiles",function()
    for ent,record in pairs(tracked) do
        if not IsValid(ent) then tracked[ent]=nil
        else SP.TransferProjectile(ent,engine.TickInterval(),record) end
    end
end)
hook.Add("PostCleanupMap","seamless_portals_projectiles_reset",function()
    for ent in pairs(tracked) do tracked[ent]=nil end
    for _,ent in ipairs(ents.GetAll()) do register(ent) end
end)
