-- Server-authoritative rigid transport. Keeps entity/PhysObj/constraint identity.
-- Native physics execution is not transactional; the Lua commit is synchronous,
-- validates before writing, and restores surviving objects on a Lua failure.
if not SERVER then return end
local SP = SeamlessPortals
local function fail(reason) return nil,reason end
function SP.CollectTransportGroup(root, holder, admission)
    if not SP.IsLiveEntity(root) then return fail("invalid_root") end
    local set = constraint.GetAllConstrainedEntities(root) or {[root]=root}
    local group = {}
    -- Admission may start at an unheld member of a held assembly. Resolve the
    -- one tracked controller across the graph, without permitting a transfer by
    -- somebody else. Actual PlanTransport calls never enable this inference.
    if admission and not holder then
        for ent in pairs(set) do
            if SP.IsLiveEntity(ent) and ent:IsPlayerHolding() then
                local owner = SP.HeldBy and SP.HeldBy(ent)
                if not owner or (holder and holder ~= owner) then return fail("other_or_untracked_holder") end
                holder = owner
            end
        end
    end
    for ent in pairs(set) do
        if not SP.IsLiveEntity(ent) or ent:IsWorld() or ent:IsPlayer() or SP.IsPortal(ent)
            or ent:GetClass() == "seamless_portal_clone" or ent:GetClass() == "seamless_portal_cutout" then
            return fail("unsupported_group_member")
        end
        if IsValid(ent:GetParent()) then return fail("parented_group_member") end
        if ent:IsVehicle() and IsValid(ent:GetDriver()) then return fail("occupied_vehicle") end
        if ent:IsPlayerHolding() and (not SP.HeldBy or SP.HeldBy(ent) ~= holder) then return fail("other_or_untracked_holder") end
        local count = ent:GetPhysicsObjectCount()
        if count < 1 or count > 32 then return fail("unsupported_physics_count") end
        for i=0,count-1 do if not IsValid(ent:GetPhysicsObjectNum(i)) then return fail("invalid_physics") end end
        for _, con in ipairs(constraint.GetTable(ent)) do
            -- A world NoCollide is not an anchor. Other world attachments are.
            for _, endpoint in pairs(con.Entity or {}) do
                if (endpoint.World or endpoint.Entity == game.GetWorld()) and con.Type ~= "NoCollide" then
                    return fail("world_anchored_constraint")
                end
                if not endpoint.World and endpoint.Entity ~= game.GetWorld()
                    and IsValid(endpoint.Entity) and not set[endpoint.Entity] then return fail("incomplete_constraint_graph") end
            end
        end
        group[#group+1] = ent
        if #group>64 then return fail("group_entity_budget") end
    end
    table.sort(group,function(a,b) return a:EntIndex()<b:EntIndex() end)
    return group
end
function SP.RigidPoint(entry,exit,point,anchor,target)
    return target+SP.TransformDirection(entry,exit,point-anchor,false)
end
local function corners(ent)
    local lo,hi = ent:OBBMins(),ent:OBBMaxs()
    local points = {}
    for x=0,1 do for y=0,1 do for z=0,1 do
        points[#points+1] = ent:LocalToWorld(Vector(x==0 and lo.x or hi.x,y==0 and lo.y or hi.y,z==0 and lo.z or hi.z))
    end end end
    return points
end
function SP.PlanTransport(root,entry,exit,holder,anchor,target)
    if not SP.SupportsPropTraversal(entry,exit) then return fail("props_disabled_or_mirror") end
    if exit:GetExitPortal() ~= entry then return fail("nonreciprocal_physical_pair") end
    local group,reason = SP.CollectTransportGroup(root,holder)
    if not group then return fail(reason) end
    anchor = anchor or root:GetPos()
    target = target or SP.TransformPortal(entry,exit,anchor)
    if not SP.FiniteVector(anchor) or not SP.FiniteVector(target) then return fail("nonfinite_anchor") end
    local plan = {entry=entry,exit=exit,root=root,holder=holder,items={},filter={},offset=Vector(0,0,0),
        geometry=SP.CaptureGeometry(entry),anchor=Vector(anchor),target=Vector(target)}
    plan.filter[entry],plan.filter[exit] = true,true
    if IsValid(holder) then plan.filter[holder] = true end
    local clearance = 0
    for _, ent in ipairs(group) do
        plan.filter[ent] = true
        local clone, owner = ent.SEAMLESS_PORTALS_CLONE,ent.SEAMLESS_PORTALS_CUTOUT
        if IsValid(clone) then
            if clone:IsPlayerHolding() then return fail("held_remote_proxy") end
            plan.filter[clone] = true
        end
        if IsValid(owner) then
            if owner:GetPortal() ~= entry and owner:GetPortal() ~= exit then return fail("another_portal_owns_member") end
            plan.filter[owner] = true
        end
        if IsValid(entry.SEAMLESS_PORTALS_CUTOUT) then plan.filter[entry.SEAMLESS_PORTALS_CUTOUT]=true end
        if IsValid(exit.SEAMLESS_PORTALS_CUTOUT) then plan.filter[exit.SEAMLESS_PORTALS_CUTOUT]=true end
        local pos,ang=ent:GetPos(),ent:GetAngles()
        local _,newang=SP.TransformPortal(entry,exit,pos,ang)
        local item={entity=ent,pos=Vector(pos),ang=Angle(ang),owner=owner,clone=clone,bodies={},points={},
            newpos=SP.RigidPoint(entry,exit,pos,anchor,target),newang=newang}
        for _,point in ipairs(corners(ent)) do
            if not (SP.CarryAlreadyThrough and SP.CarryAlreadyThrough(ent,entry))
                and not SP.InAperture(entry,point,0.05) then return fail("group_does_not_fit_entry") end
            local mapped=SP.RigidPoint(entry,exit,point,anchor,target)
            if not (SP.CarryAlreadyThrough and SP.CarryAlreadyThrough(ent,entry))
                and not SP.InAperture(exit,mapped,0.05) then return fail("group_does_not_fit_exit") end
            clearance=math.max(clearance,0.5-(mapped-exit:GetPos()):Dot(exit:GetUp()))
            item.points[#item.points+1]=mapped
        end
        for i=0,ent:GetPhysicsObjectCount()-1 do
            local phys=ent:GetPhysicsObjectNum(i)
            local p,a,v,w=phys:GetPos(),phys:GetAngles(),phys:GetVelocity(),phys:GetAngleVelocity()
            if not SP.FiniteVector(p) or not SP.FiniteVector(v) or not SP.FiniteVector(w) then return fail("nonfinite_physics") end
            local _,newa=SP.TransformPortal(entry,exit,p,a)
            item.bodies[#item.bodies+1]={phys=phys,index=i,pos=Vector(p),ang=Angle(a),vel=Vector(v),angular=Vector(w),
                motion=phys:IsMotionEnabled(),held=ent:IsPlayerHolding(),newpos=SP.RigidPoint(entry,exit,p,anchor,target),newang=newa,
                newvel=SP.TransformDirection(entry,exit,v,false)}
        end
        plan.items[#plan.items+1]=item
    end
    if IsValid(holder) then
        local lo,hi
        if holder:Crouching() then
            lo=holder.SEAMLESS_PORTALS_HULL_DUCK_MINS
            hi=holder.SEAMLESS_PORTALS_HULL_DUCK_MAXS
            if not lo then lo,hi=holder:GetHullDuck() end
        else
            lo=holder.SEAMLESS_PORTALS_HULL_MINS
            hi=holder.SEAMLESS_PORTALS_HULL_MAXS
            if not lo then lo,hi=holder:GetHull() end
        end
        local origin=target-holder:GetCurrentViewOffset()
        for x=0,1 do for y=0,1 do for z=0,1 do
            local p=origin+Vector(x==0 and lo.x or hi.x,y==0 and lo.y or hi.y,z==0 and lo.z or hi.z)
            clearance=math.max(clearance,0.5-(p-exit:GetPos()):Dot(exit:GetUp()))
        end end end
        plan.player_origin,plan.player_mins,plan.player_maxs=origin,Vector(lo),Vector(hi)
    end
    -- Move the entire assembly by one common clearance, never stretch welds/ropes.
    if clearance>256 then return fail("excessive_exit_clearance") end
    plan.offset=exit:GetUp()*clearance
    for _,item in ipairs(plan.items) do
        item.newpos:Add(plan.offset)
        local lo,hi=Vector(math.huge,math.huge,math.huge),Vector(-math.huge,-math.huge,-math.huge)
        for _,p in ipairs(item.points) do
            p:Add(plan.offset)
            for axis=1,3 do lo[axis]=math.min(lo[axis],p[axis]) hi[axis]=math.max(hi[axis],p[axis]) end
        end
        for _,body in ipairs(item.bodies) do body.newpos:Add(plan.offset) end
        local center=(lo+hi)*0.5
        local tr=util.TraceHull({start=center,endpos=center,mins=lo-center,maxs=hi-center,mask=MASK_SOLID,
            filter=function(ent) return not plan.filter[ent] end})
        if tr.StartSolid or tr.AllSolid or tr.Hit then return fail("exit_obstructed") end
    end
    if plan.player_origin then
        local pos=plan.player_origin+plan.offset
        local tr=util.TraceHull({start=pos,endpos=pos,mins=plan.player_mins,maxs=plan.player_maxs,mask=MASK_PLAYERSOLID,
            filter=function(ent) return not plan.filter[ent] end})
        if tr.StartSolid or tr.AllSolid or tr.Hit then return fail("player_exit_obstructed") end
    end
    return plan
end
function SP.RollbackTransport(plan)
    local errors={}
    for _,item in ipairs(plan.items) do
        local ok,err=xpcall(function()
            if not IsValid(item.entity) then return end
            item.entity:SetPos(item.pos) item.entity:SetAngles(item.ang)
            for _,b in ipairs(item.bodies) do
                if IsValid(b.phys) and item.entity:GetPhysicsObjectNum(b.index)==b.phys then
                    b.phys:SetPos(b.pos,true) b.phys:SetAngles(b.ang)
                    if b.phys:IsMotionEnabled() ~= b.motion then b.phys:EnableMotion(b.motion) end
                    b.phys:SetVelocity(b.vel) b.phys:SetAngleVelocity(b.angular)
                end
            end
            if IsValid(item.owner) and item.owner.SEAMLESS_PORTALS_READY and not item.entity.SEAMLESS_PORTALS_CUTOUT then
                item.owner:AddEntity(item.entity)
            end
        end,debug.traceback)
        if not ok then errors[#errors+1]=tostring(err) end
    end
    if #errors>0 then ErrorNoHalt("[Seamless Portals] Transport rollback incomplete: "..table.concat(errors,"; ").."\n") end
    return #errors==0
end
function SP.CommitTransport(plan)
    if not SP.SupportsPropTraversal(plan.entry,plan.exit) or plan.exit:GetExitPortal() ~= plan.entry
        or not SP.SameGeometry(plan.geometry,SP.CaptureGeometry(plan.entry)) then return false,"portal_changed" end
    local current, reason = SP.CollectTransportGroup(plan.root,plan.holder)
    if not current then return false,reason end
    if #current ~= #plan.items then return false,"constraint_graph_changed" end
    for i,ent in ipairs(current) do if ent ~= plan.items[i].entity then return false,"constraint_graph_changed" end end
    -- Revalidate every handle before the first write; callbacks may have invalidated it.
    for _,item in ipairs(plan.items) do
        if not SP.IsLiveEntity(item.entity) then return false,"member_removed" end
        for _,b in ipairs(item.bodies) do
            if not IsValid(b.phys) or item.entity:GetPhysicsObjectNum(b.index)~=b.phys then return false,"physics_replaced" end
        end
    end
    local ok,err=xpcall(function()
        for _,item in ipairs(plan.items) do
            -- No temporary freezing: toggling motion can detach a native grab
            -- controller. Lua writes finish before the next physics integration.
            if IsValid(item.owner) then item.owner:RemoveEntity(item.entity,true) end
        end
        for _,item in ipairs(plan.items) do
            item.entity:SetPos(item.newpos) item.entity:SetAngles(item.newang)
            for _,b in ipairs(item.bodies) do b.phys:SetPos(b.newpos,true) b.phys:SetAngles(b.newang) end
        end
        for _,item in ipairs(plan.items) do
            for _,b in ipairs(item.bodies) do
                if b.phys:IsMotionEnabled() ~= b.motion then b.phys:EnableMotion(b.motion) end
                b.phys:SetVelocity(b.newvel) b.phys:SetAngleVelocity(b.angular)
                if b.motion then b.phys:Wake() end
            end
        end
    end,debug.traceback)
    if not ok then SP.RollbackTransport(plan) return false,tostring(err) end
    for _,item in ipairs(plan.items) do
        item.entity.SEAMLESS_PORTALS_LAST_TRANSFER=engine.TickCount()
        item.entity.SEAMLESS_PORTALS_CLONE=nil
        if IsValid(item.clone) then
            item.clone.SEAMLESS_PORTALS_RETIRED = true
            item.clone:SetNotSolid(true)
            item.clone:SetNoDraw(true)
            SafeRemoveEntity(item.clone)
        end
    end
    return true
end
function SP.NotifyTransport(plan,kind)
    for _,item in ipairs(plan.items) do SP.NotifyTraversal(item.entity,plan.entry,plan.exit,kind or "assembly") end
end
