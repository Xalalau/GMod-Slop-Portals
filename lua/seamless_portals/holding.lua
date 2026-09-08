-- Track confirmed native pickups; permission hooks are never treated as success.
local SP=SeamlessPortals
SP.Holds=SP.Holds or setmetatable({},{__mode="k"})
SP.HoldOwners=SP.HoldOwners or setmetatable({},{__mode="k"})
function SP.HeldBy(ent)
    local owners=SP.HoldOwners[ent]
    local found
    for ply in pairs(owners or {}) do
        if IsValid(ply) and SP.Holds[ply] and SP.Holds[ply].entity==ent then
            if found then return nil end -- competing native controllers: do not choose one
            found=ply
        end
    end
    return found
end
function SP.ClearHold(ply, ent)
    local old=SP.Holds[ply]
    if not old or (ent and old.entity~=ent) then return end
    if SERVER and SP.QueueCarryRelease then SP.QueueCarryRelease(old) end
    local owners=SP.HoldOwners[old.entity]
    if owners then owners[ply]=nil end
    SP.Holds[ply]=nil
    if SERVER and IsValid(ply) then ply:SetNWEntity("seamless_portals_held",NULL) end
end
function SP.RecordHold(ply,ent,kind)
    if not IsValid(ply) or not SP.IsLiveEntity(ent) or SP.IsPortal(ent)
        or ent:GetClass()=="seamless_portal_clone" then return end
    local old=SP.Holds[ply]
    if old and old.entity==ent and old.kind==kind then return end
    SP.ClearHold(ply)
    SP.Holds[ply]={entity=ent,kind=kind,tick=engine.TickCount()}
    SP.HoldOwners[ent]=SP.HoldOwners[ent] or setmetatable({},{__mode="k"})
    SP.HoldOwners[ent][ply]=true
    if SERVER then ply:SetNWEntity("seamless_portals_held",ent) end
end
function SP.HasTrackedHold(ent)
    for ply in pairs(SP.HoldOwners[ent] or {}) do
        local record=SP.Holds[ply]
        if IsValid(ply) and record and record.entity==ent then return true end
    end
    return false
end
function SP.GetHeldRecord(ply)
    if CLIENT then
        local ent=ply:GetNWEntity("seamless_portals_held")
        if IsValid(ent) then return {entity=ent,kind="replicated"} end
        return
    end
    local record=SP.Holds[ply]
    if record and (not SP.IsLiveEntity(record.entity)
        or (engine.TickCount()>record.tick+1 and not record.entity:IsPlayerHolding())) then
        SP.ClearHold(ply) return
    end
    return record
end
-- Optional integration point for another native/custom pickup implementation:
-- call RecordHold only after it actually attached, and ClearHold on release.
if SERVER then
    for event,kind in pairs({OnPhysgunPickup="physgun",OnPlayerPhysicsPickup="use",GravGunOnPickedUp="gravgun"}) do
        hook.Add(event,"seamless_portals_hold_tracking",function(ply,ent) SP.RecordHold(ply,ent,kind) end)
    end
    for _,event in ipairs({"PhysgunDrop","OnPlayerPhysicsDrop","GravGunOnDropped"}) do
        hook.Add(event,"seamless_portals_hold_tracking",function(ply,ent) SP.ClearHold(ply,ent) end)
    end
    for _,event in ipairs({"PlayerDeath","PlayerSilentDeath","PlayerDisconnected"}) do
        hook.Add(event,"seamless_portals_hold_tracking",function(ply) SP.ClearHold(ply) end)
    end
    hook.Add("EntityRemoved","seamless_portals_hold_tracking",function(ent)
        for ply,record in pairs(SP.Holds) do if record.entity==ent then SP.ClearHold(ply,ent) end end
        SP.HoldOwners[ent]=nil
    end)
end
hook.Add("PhysgunPickup","seamless_portals_preserve_hold",function(ply,ent)
    local record=SP.GetHeldRecord(ply)
    if record and record.entity~=ent and (SP.IsPortal(ent) or ent:GetClass()=="seamless_portal_clone") then
        return false
    end
end)
function SP.BlockHeldTraversal(ply,mv,entry,reason)
    if SP.RestorePlayerHull then SP.RestorePlayerHull(ply) end
    local lo,hi
    if ply:Crouching() then lo,hi=ply:GetHullDuck() else lo,hi=ply:GetHull() end
    local origin,normal=Vector(mv:GetOrigin()),entry:GetUp()
    local minimum=math.huge
    for x=0,1 do for y=0,1 do for z=0,1 do
        local p=origin+Vector(x==0 and lo.x or hi.x,y==0 and lo.y or hi.y,z==0 and lo.z or hi.z)
        minimum=math.min(minimum,(p-entry:GetPos()):Dot(normal))
    end end end
    if minimum<0.5 then origin:Add(normal*(0.5-minimum)) end
    local vel=Vector(mv:GetVelocity())
    local inward=vel:Dot(normal)
    if inward<0 then vel:Sub(normal*inward) end
    mv:SetOrigin(origin) mv:SetVelocity(vel)
    ply.SEAMLESS_PORTALS_TRANSPORT_BLOCKED=reason
    if SERVER and (ply.SEAMLESS_PORTALS_BLOCK_NOTICE or 0)<CurTime() then
        ply.SEAMLESS_PORTALS_BLOCK_NOTICE=CurTime()+1
        SP.RunSafeHook("SeamlessPortalsTransportBlocked",ply,entry,reason)
    end
    return true
end

if SERVER then
    SP.CarryAudit=SP.CarryAudit or setmetatable({},{__mode="k"})
    function SP.AuditHeldTransport(ply,hold,plan)
        local audit={kind=hold.kind,entity=hold.entity,tick=engine.TickCount(),native_hold="pending",bodies={}}
        for _,item in ipairs(plan.items) do
            for _,body in ipairs(item.bodies) do audit.bodies[#audit.bodies+1]={entity=item.entity,index=body.index,phys=body.phys} end
        end
        SP.CarryAudit[ply]=audit
        timer.Simple(0,function()
            if SP.CarryAudit[ply]~=audit or not IsValid(ply) then return end
            audit.native_hold=IsValid(hold.entity) and hold.entity:IsPlayerHolding() and "retained" or "released"
            audit.physics_identity=true
            for _,body in ipairs(audit.bodies) do
                if not IsValid(body.entity) or body.entity:GetPhysicsObjectNum(body.index)~=body.phys then audit.physics_identity=false end
            end
            SP.RunSafeHook("SeamlessPortalsCarryAudit",ply,audit)
        end)
    end
    concommand.Add("seamless_portals_transport_status",function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end
        for player,audit in pairs(SP.CarryAudit) do
            local text=string.format("%s: %s hold=%s physics_identity=%s tick=%d",tostring(player),audit.kind,
                audit.native_hold,tostring(audit.physics_identity),audit.tick)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE,text) else print(text) end
        end
    end)
end
