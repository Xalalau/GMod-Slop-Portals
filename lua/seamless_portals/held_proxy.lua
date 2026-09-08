-- F03: Conservative collision sweep for the emerged part of a held proxy.
-- The native grab target remains untouched; remote obstruction constrains its
-- source-space handle without allocating a replacement native physics object.
if not SERVER then return end
local SP=SeamlessPortals
local function visible_bounds(points,portal)
    local visible={}
    local distances={}
    for i,p in ipairs(points) do
        local d=SP.PlaneDistance(portal,p)-0.1
        distances[i]=d
        if d>=0 then visible[#visible+1]=p end
    end
    -- All corner pairs are conservative (includes face diagonals); clipping the
    -- resulting AABB never underestimates the emerged OBB.
    for i=1,#points do for j=i+1,#points do
        local a,b=distances[i],distances[j]
        if (a<0 and b>0) or (a>0 and b<0) then visible[#visible+1]=points[i]+(points[j]-points[i])*(a/(a-b)) end
    end end
    if #visible==0 then return end
    local lo,hi=Vector(math.huge,math.huge,math.huge),Vector(-math.huge,-math.huge,-math.huge)
    for _,p in ipairs(visible) do
        for axis=1,3 do lo[axis]=math.min(lo[axis],p[axis]) hi[axis]=math.max(hi[axis],p[axis]) end
    end
    return lo,hi
end
function SP.TraceHeldProxyMovement(data,allowEscape)
    local tr=util.TraceHull(data)
    local left=tr.FractionLeftSolid
    if allowEscape and tr.StartSolid and not tr.AllSolid and SP.IsFinite(left) and left>0 and left<1 then
        -- A resting, tilted prop can overlap the conservative box initially.
        -- Check the remaining sweep after leaving that contact, including walls.
        left=math.min(1,left+0.0001)
        local remaining={}
        for key,value in pairs(data) do remaining[key]=value end
        remaining.start=LerpVector(left,data.start,data.endpos)
        tr=util.TraceHull(remaining)
        tr.Fraction=left+(1-left)*(tr.Fraction or 0)
    end
    return tr
end
function SP.ClampHeldProxy(clone,child,entry,exit,position,angle)
    local record=child.SEAMLESS_PORTALS_CARRY
    if not record then return position,angle end
    local points={}
    for _,p in ipairs(SP.EntityCorners(child)) do points[#points+1]=SP.TransformPortal(entry,exit,p) end
    local lo,hi=visible_bounds(points,exit)
    if not lo then clone.SEAMLESS_PORTALS_PROXY_LAST=nil return position,angle end
    local center=(lo+hi)*0.5
    local previous=clone.SEAMLESS_PORTALS_PROXY_LAST
    local delta=previous and position-previous.position or vector_origin
    -- A growing emerged hull can begin its sweep behind the exit wall. Recheck
    -- the remaining sweep after it leaves that initial overlap.
    local tr=SP.TraceHeldProxyMovement({start=center-delta,endpos=center,mins=lo-center,maxs=hi-center,mask=MASK_SOLID,
        filter=function(ent)
            if ent==clone or ent==entry or ent==exit or ent==record.player then return false end
            if ent:GetClass()=="seamless_portal_cutout" then return false end
            for _,member in ipairs(record.group or {child}) do
                if ent==member or ent==member.SEAMLESS_PORTALS_CLONE then return false end
            end
            return true
        end},record.nativePickup~=nil or record.kind=="gravgun")
    if tr.StartSolid or tr.AllSolid or tr.Hit then
        SP.CountField("carry_remote_collision_blocks")
        local corrected
        if previous and not tr.StartSolid and not tr.AllSolid then
            corrected=previous.position+delta*math.max(0,(tr.Fraction or 0)-0.001)
        end
        if corrected and #(record.group or {})==1 then
            local source,source_angle=SP.TransformPortal(exit,entry,corrected,angle)
            child:SetPos(source) child:SetAngles(source_angle)
            local phys=child:GetPhysicsObject()
            phys:SetPos(source,true) phys:SetAngles(source_angle)
            phys:SetVelocity(vector_origin)
            position=corrected
        else
            SP.RestoreCarryContact(record)
            position,angle=SP.TransformPortal(entry,exit,child:GetPos(),child:GetAngles())
        end
    elseif record.nativePickup then
        record.contact=SP.CaptureCarryPose(record.group)
    end
    clone.SEAMLESS_PORTALS_PROXY_LAST={position=Vector(position),angle=Angle(angle)}
    return position,angle
end
SP.ForwardedProxyDamage=SP.ForwardedProxyDamage or setmetatable({},{__mode="k"})
hook.Add("EntityTakeDamage","seamless_portals_hidden_handle_damage",function(ent,info)
    local record=ent.SEAMLESS_PORTALS_CARRY
    if not record or SP.ForwardedProxyDamage[info] or not SP.IsPortal(record.entry) then return end
    if SP.PortalOBB(record.entry,ent).fully_back then return true end
end)
