-- F02: Native +USE/physgun controllers stay attached to the original PhysObj.
-- While the holder is in the entrance room the original is a clipped handle;
-- a physical/damage proxy represents its emerged portion in the exit room.
-- This is deliberately NOT a drop/regrab replacement for the native controls.
if not SERVER then return end
local SP=SeamlessPortals
SP.CarryReleased=SP.CarryReleased or {}
local max_reach=CreateConVar("seamless_portals_carry_reach","4096",FCVAR_ARCHIVE,"Maximum unfolded held-object corridor length",128,16384)
local function eye(ply)
    return ply:EyePos()
end
local function snapshot(group)
    local items={}
    for _,ent in ipairs(group) do
        local item={entity=ent,pos=Vector(ent:GetPos()),ang=Angle(ent:GetAngles()),bodies={}}
        for i=0,ent:GetPhysicsObjectCount()-1 do
            local phys=ent:GetPhysicsObjectNum(i)
            item.bodies[#item.bodies+1]={phys=phys,index=i,pos=Vector(phys:GetPos()),ang=Angle(phys:GetAngles())}
        end
        items[#items+1]=item
    end
    return items
end
function SP.ClearCarryState(record)
    for _,ent in ipairs(record.group or {}) do
        if IsValid(ent) and ent.SEAMLESS_PORTALS_CARRY==record then ent.SEAMLESS_PORTALS_CARRY=nil end
    end
    record.entry,record.exit,record.group,record.safe=nil,nil,nil,nil
end
function SP.RestoreCarryFront(record)
    -- Used only when a corridor disappears or remote release cannot be committed.
    -- Restore the last fully-front source pose, before collision ownership ends.
    for _,item in ipairs(record.safe or {}) do
        local ent=item.entity
        if IsValid(ent) then
            ent:SetPos(item.pos) ent:SetAngles(item.ang)
            for _,b in ipairs(item.bodies) do
                if IsValid(b.phys) and ent:GetPhysicsObjectNum(b.index)==b.phys then
                    b.phys:SetPos(b.pos,true) b.phys:SetAngles(b.ang)
                    b.phys:SetVelocity(vector_origin) b.phys:SetAngleVelocity(vector_origin)
                end
            end
        end
    end
end
function SP.EndCarryCorridor(record,restore)
    if restore then SP.RestoreCarryFront(record) end
    for _,ent in ipairs(record.group or {}) do
        if IsValid(ent) then
            local cutout=ent.SEAMLESS_PORTALS_CUTOUT
            if IsValid(cutout) then cutout:RemoveEntity(ent) end
        end
    end
    SP.ClearCarryState(record)
end
function SP.QueueCarryRelease(record)
    if not record.entry then return end
    record.released=true
    SP.CarryReleased[#SP.CarryReleased+1]=record
end
function SP.DrainCarryReleases()
    local pending=SP.CarryReleased
    SP.CarryReleased={}
    for _,record in ipairs(pending) do
        local root=record.entity
        if SP.IsLiveEntity(root) and not root:IsPlayerHolding() and SP.IsUsableLink(record.entry,record.exit) then
            local footprint=SP.PortalOBB(record.entry,root)
            if footprint.hi.z<0 then
                local plan,reason=SP.PlanTransport(root,record.entry,record.exit)
                local ok=false
                if plan then ok,reason=SP.CommitTransport(plan) end
                if ok then
                    SP.NotifyTransport(plan,"released_carry")
                    SP.CountField("carry_remote_releases")
                    SP.ClearCarryState(record)
                else
                    SP.CountField("carry_release_blocked")
                    root.SEAMLESS_PORTALS_TRANSPORT_BLOCKED=reason
                    SP.EndCarryCorridor(record,true)
                end
            else
                -- Still straddling: release to the ordinary physical crossing path.
                SP.ClearCarryState(record)
            end
        elseif SP.IsLiveEntity(root) and root:IsPlayerHolding() then
            -- A genuine new pickup owns it; never teleport out of that controller.
            SP.ClearCarryState(record)
        else
            SP.EndCarryCorridor(record,true)
        end
    end
end
function SP.CarryKeepsAdmission(ent,portal)
    local record=ent.SEAMLESS_PORTALS_CARRY
    return record and record.entry==portal and SP.IsUsableLink(record.entry,record.exit)
        and (record.released or (IsValid(record.player) and SP.Holds[record.player]==record))
end
function SP.CarryAlreadyThrough(ent,portal)
    local record=ent.SEAMLESS_PORTALS_CARRY
    return record and record.entry==portal and record.crossed and SP.PortalOBB(portal,ent).fully_back
end
local function start_corridor(ply,record,entry,group)
    local exit=entry:GetExitPortal()
    if not entry:UpdateCutout() then return false end
    local cutout=entry.SEAMLESS_PORTALS_CUTOUT
    if not IsValid(cutout) then return false end
    record.player,record.entry,record.exit,record.group=ply,entry,exit,group
    -- Even the first observed pose must be restorable outside the entrance wall.
    record.safe=snapshot(group)
    local correction=0
    for _,ent in ipairs(group) do correction=math.max(correction,0.5-SP.PortalOBB(entry,ent).lo.z) end
    if correction>0 then
        local offset=entry:GetUp()*correction
        for _,item in ipairs(record.safe) do
            item.pos:Add(offset)
            for _,body in ipairs(item.bodies) do body.pos:Add(offset) end
        end
    end
    local admitted={}
    for _,ent in ipairs(group) do
        ent.SEAMLESS_PORTALS_CARRY=record
        if not cutout:AddEntity(ent) then
            ent.SEAMLESS_PORTALS_CARRY=nil
            for _,old in ipairs(admitted) do cutout:RemoveEntity(old) end
            SP.ClearCarryState(record)
            return false
        end
        admitted[#admitted+1]=ent
    end
    SP.CountField("carry_corridors_started")
    return true
end
function SP.RefreshCarry(ply,record)
    if not IsValid(ply) or not SP.IsLiveEntity(record.entity) then SP.EndCarryCorridor(record,true) return end
    local root=record.entity
    local center=root:LocalToWorld(root:OBBCenter())
    local eyes=eye(ply)
    if record.entry then
        local entry,exit=record.entry,record.exit
        if not SP.SupportsPropTraversal(entry,exit) or exit:GetExitPortal()~=entry
            or eyes:DistToSqr(center)>max_reach:GetFloat()^2 or SP.PlaneDistance(entry,eyes)<-8 then
            SP.EndCarryCorridor(record,true) return
        end
        local all_front=true
        for _,ent in ipairs(record.group) do
            if not SP.IsLiveEntity(ent) then SP.EndCarryCorridor(record,true) return end
            local fp=SP.PortalOBB(entry,ent)
            if not fp.fully_front then all_front=false end
            if fp.straddling and fp.fits then record.crossed=true end
            -- A leading object cannot move sideways through a closed frame.
            if fp.straddling and not fp.fits then
                SP.RestoreCarryFront(record)
                root.SEAMLESS_PORTALS_TRANSPORT_BLOCKED="held_footprint_outside_aperture"
                SP.CountField("carry_frame_blocks")
                return
            end
        end
        if all_front then
            record.safe=snapshot(record.group)
            if SP.PortalOBB(entry,root).lo.z>32 then SP.EndCarryCorridor(record,false) return end
        else
            record.crossed=true
        end
        return
    end
    if root:GetPhysicsObjectCount()<1 or root:GetClass()=="seamless_portal_clone" then return end
    local chosen,depth
    for _,entry in ipairs(SP.Portals) do
        local exit=SP.IsPortal(entry) and entry:GetExitPortal()
        if SP.SupportsPropTraversal(entry,exit) and exit:GetExitPortal()==entry
            and SP.PlaneDistance(entry,eyes)>=0 then
            local fp=SP.PortalOBB(entry,root)
            local velocity=root:GetPhysicsObject():GetVelocity()
            local lead=math.min(128,16+velocity:Length()*engine.TickInterval())
            if fp.overlap and fp.lo.z<=lead and fp.hi.z>=-8
                and (not depth or math.abs(fp.lo.z)<depth) then chosen,depth=entry,math.abs(fp.lo.z) end
        end
    end
    if not chosen then return end
    local group,reason=SP.CollectTransportGroup(root,ply)
    if not group then root.SEAMLESS_PORTALS_TRANSPORT_BLOCKED=reason return end
    start_corridor(ply,record,chosen,group)
end
function SP.RefreshHeldCorridors()
    SP.DrainCarryReleases()
    for ply,record in pairs(SP.Holds) do
        if SP.GetHeldRecord(ply)==record then SP.RefreshCarry(ply,record) end
    end
end
hook.Add("Tick","seamless_portals_held_corridors",SP.RefreshHeldCorridors)
function SP.FinishHeldTraversal(ply,record)
    SP.ClearCarryState(record)
    SP.CountField("carry_holder_transfers")
end
hook.Add("PostCleanupMap","seamless_portals_carry_cleanup",function()
    for _,record in pairs(SP.Holds) do SP.ClearCarryState(record) end
    SP.CarryReleased={}
end)
