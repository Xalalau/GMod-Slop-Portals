-- Start a native physgun hold through a temporary selection handle.
-- Only the owned helper and its constraint are created; original PhysObjs and constraints survive.
if not SERVER then return end
local SP=SeamlessPortals
local permissionPlayers=setmetatable({},{__mode="k"})
function SP.CheckNativePickupPermission(ply,root)
    local previous=permissionPlayers[root]
    permissionPlayers[root]=ply
    local ok,result=xpcall(function() return hook.Run("PhysgunPickup",ply,root) end,debug.traceback)
    permissionPlayers[root]=previous
    if not ok then ErrorNoHalt(tostring(result).."\n") return false end
    return result==true
end
local function reach()
    local native=GetConVar("physgun_maxrange")
    local carry=GetConVar("seamless_portals_carry_reach")
    return math.Clamp(math.min(native and native:GetFloat() or 4096,carry and carry:GetFloat() or 4096),128,16384)
end
function SP.RemotePhysgunGroupFits(portal,points)
    local lo,hi=Vector(math.huge,math.huge,0),Vector(-math.huge,-math.huge,0)
    local localPoints={}
    for _,point in ipairs(points) do
        local p=portal:WorldToLocal(point)
        localPoints[#localPoints+1]=p
        lo.x,lo.y=math.min(lo.x,p.x),math.min(lo.y,p.y)
        hi.x,hi.y=math.max(hi.x,p.x),math.max(hi.y,p.y)
    end
    if #localPoints==0 then return false end
    local center=(lo+hi)*0.5
    for _,p in ipairs(localPoints) do
        if not SP.InApertureLocal(portal,p-center,0.05) then return false end
    end
    return true
end
local function pickup_plan(ply)
    if not SP.TracePortalLine then return end
    local start=ply:EyePos()
    local tr=SP.TracePortalLine({start=start,endpos=start+ply:GetAimVector()*reach(),filter=ply,
        mask=MASK_SHOT,SeamlessMaxHops=1,SeamlessFeature="props"})
    local segments=tr.SeamlessSegments
    local root,hit=tr.Entity,tr.HitPos
    local entry,exit,alreadyFolded,localNPC
    if segments and #segments==2 then
        entry=segments[1].Entity
        exit=SP.IsPortal(entry) and entry:GetExitPortal()
        if SP.IsLiveEntity(root) and root:GetClass()=="seamless_portal_clone" then
            if root:GetPortal1()~=entry or root:GetPortal2()~=exit then return end
            root=root:GetChild()
            hit=SP.TransformPortal(exit,entry,hit)
            alreadyFolded=true
        end
    elseif not segments and SP.IsLiveEntity(root) and root:GetClass()=="seamless_portal_clone" then
        entry,exit=root:GetPortal2(),root:GetPortal1()
        hit=SP.TransformPortal(entry,exit,hit)
        root=root:GetChild()
    elseif (not segments or #segments==1) and SP.IsLiveEntity(root) and root:IsNPC()
        and root:GetMoveType()~=MOVETYPE_VPHYSICS then
        localNPC=true
    else return end
    if not localNPC and (not SP.SupportsPropTraversal(entry,exit) or exit:GetExitPortal()~=entry) then return end
    if not SP.IsLiveEntity(root) or root:IsPlayerHolding() or SP.HasTrackedHold(root) then return end
    if root:GetClass()~="prop_physics" and root:GetClass()~="prop_physics_multiplayer" and not root:IsNPC() then return end
    local bone=tr.PhysicsBone or 0
    if root:IsNPC() and root:GetPhysicsObjectCount()==1 then bone=0 end
    local phys=root:GetPhysicsObjectNum(bone)
    if not IsValid(phys) or phys:HasGameFlag(FVPHYSICS_PLAYER_HELD) then return end
    -- Run the actual target through Sandbox/CPPI and addon pickup permissions.
    if not SP.CheckNativePickupPermission(ply,root) then return end
    if SP.GetHeldRecord(ply) or not SP.IsLiveEntity(root) or root:GetPhysicsObjectNum(bone)~=phys or root:IsPlayerHolding()
        or (not localNPC and (not SP.SupportsPropTraversal(entry,exit) or exit:GetExitPortal()~=entry)) then return end
    local group=SP.CollectTransportGroup(root,ply)
    if not group or #group>=64 then return end
    local anchor=root:GetPos()
    local target=(alreadyFolded or localNPC) and anchor or SP.TransformPortal(exit,entry,anchor)
    local function point(p) return (alreadyFolded or localNPC) and Vector(p) or SP.RigidPoint(exit,entry,p,anchor,target) end
    local function angle(p,a)
        if alreadyFolded or localNPC then return Angle(a) end
        local _,mapped=SP.TransformPortal(exit,entry,p,a)
        return mapped
    end
    local plan={root=root,entry=exit,exit=entry,items={},localNPC=localNPC,
        tracePoint=not localNPC and segments and segments[1].HitPos or tr.HitPos}
    if localNPC then
        -- Native NPC selection hits the movement hull before the model hitboxes.
        local hull=SP.RawTraceLine({start=start,endpos=start+ply:GetAimVector()*reach(),filter=ply,mask=MASK_SOLID})
        if hull.Entity~=root then return end
        local padding=Vector(8,8,8)
        local boundary=util.IntersectRayWithOBB(start,ply:GetAimVector()*reach(),root:GetPos(),root:GetAngles(),root:OBBMins()-padding,root:OBBMaxs()+padding)
        plan.tracePoint=boundary or hull.HitPos
    end
    local sourcePoints,destinationPoints={},{}
    for _,ent in ipairs(group) do
        local owner=ent.SEAMLESS_PORTALS_CUTOUT
        if owner and (not IsValid(owner) or (not localNPC and owner:GetPortal()~=(alreadyFolded and entry or exit))) then return end
        local newangle=angle(ent:GetPos(),ent:GetAngles())
        local item={entity=ent,pos=Vector(ent:GetPos()),ang=Angle(ent:GetAngles()),owner=owner,bodies={},
            newpos=point(ent:GetPos()),newang=newangle}
        local lo,hi=ent:OBBMins(),ent:OBBMaxs()
        for x=0,1 do for y=0,1 do for z=0,1 do
            local corner=ent:LocalToWorld(Vector(x==0 and lo.x or hi.x,y==0 and lo.y or hi.y,z==0 and lo.z or hi.z))
            sourcePoints[#sourcePoints+1]=corner
            destinationPoints[#destinationPoints+1]=point(corner)
        end end end
        for i=0,ent:GetPhysicsObjectCount()-1 do
            local body=ent:GetPhysicsObjectNum(i)
            if body~=phys and not body:IsMotionEnabled() then return end
            local a=angle(body:GetPos(),body:GetAngles())
            item.bodies[#item.bodies+1]={phys=body,index=i,pos=Vector(body:GetPos()),ang=Angle(body:GetAngles()),
                vel=Vector(body:GetVelocity()),angular=Vector(body:GetAngleVelocity()),motion=body:IsMotionEnabled(),
                newpos=point(body:GetPos()),newang=a}
        end
        plan.items[#plan.items+1]=item
    end
    -- Size admission is independent of the remote prop's lateral offset.
    -- RefreshCarry enforces its actual footprint when it reaches the frame.
    if not localNPC and (not SP.RemotePhysgunGroupFits(alreadyFolded and entry or exit,sourcePoints)
        or not SP.RemotePhysgunGroupFits(entry,destinationPoints)) then return end
    return plan,group,phys,phys:WorldToLocal(hit),bone
end
SP.NativePickupStates=SP.NativePickupStates or {}
SP.NativePickupTargets=SP.NativePickupTargets or setmetatable({},{__mode='k'})
SP.NativePickupNext=SP.NativePickupNext or setmetatable({},{__mode='k'})
local function remove_state(state,rollback)
 if state.removed then return end state.removed=true
 if rollback and state.record then
  for _,ent in ipairs(state.record.group or {}) do
   local clone=IsValid(ent) and ent.SEAMLESS_PORTALS_CLONE
   if IsValid(clone) then
    clone.SEAMLESS_PORTALS_RETIRED=true
    clone:SetNotSolid(true) clone:SetNoDraw(true)
   end
  end
  SP.EndCarryCorridor(state.record,false)
 elseif state.record and not state.record.entry then
  SP.ClearCarryState(state.record)
 end
 if IsValid(state.weld) then state.weld:Remove() end
 if IsValid(state.ply) and state.ply:GetNWEntity('seamless_portals_native_physgun_handle')==state.handle then
  state.ply:SetNWEntity('seamless_portals_native_physgun_handle',NULL)
 end
 if IsValid(state.handle) then
  local body=state.handle:GetPhysicsObject()
  if rollback and IsValid(body) then
   -- Remove is deferred: keep the owned weld aligned until the engine retires it.
   body:EnableMotion(false)
   for _,item in ipairs(state.plan.items) do
    if item.entity==state.plan.root then
     state.handle:SetPos(item.pos) state.handle:SetAngles(item.ang)
     body:SetPos(item.pos,true) body:SetAngles(item.ang)
     body:SetVelocity(vector_origin) body:SetAngleVelocity(vector_origin)
     break
    end
   end
  end
  if not rollback and IsValid(body) and not body:IsMotionEnabled() and IsValid(state.phys) then
   state.phys:EnableMotion(false)
  end
  state.handle:Remove()
 end
 if state.npcMoveType and SP.IsLiveEntity(state.plan.root) and state.plan.root:GetMoveType()==MOVETYPE_NONE then
  state.plan.root:SetMoveType(state.npcMoveType)
 end
 if rollback then SP.RollbackTransport(state.plan) end
 if state.handle then SP.NativePickupStates[state.handle]=nil end
 if SP.NativePickupTargets[state.plan.root]==state then SP.NativePickupTargets[state.plan.root]=nil end
end
function SP.RestoreNativePickupRemote(record)
 local state=record.nativePickup
 if not state or state.removed or not state.confirmed then return false end
 if IsValid(state.handle) and state.handle:IsPlayerHolding() then return false end
 -- A rejected release must return to the known remote pose, never the
 -- synthetic pose outside the entrance wall. Preserve the user's freeze state.
 local motion={}
 for _,item in ipairs(state.plan.items) do
  for _,body in ipairs(item.bodies) do
   if IsValid(body.phys) then motion[body.phys]=body.phys:IsMotionEnabled() end
  end
 end
 remove_state(state,true)
 for body,enabled in pairs(motion) do
  if IsValid(body) and body:IsMotionEnabled()~=enabled then body:EnableMotion(enabled) end
 end
 return true
end
local function restore_bounds(state)
 local h=state.handle
 if not IsValid(h) then return end
 h:SetSolidFlags(state.flags)
 h:SetCollisionBounds(state.lo,state.hi)
 h:SetSurroundingBoundsType(BOUNDS_COLLISION)
 h.TestCollision=nil
 h:SetNotSolid(true)
end
function SP.NativePhysgunSelection(state,start,delta,isbox)
 local ply=state.ply
 if state.confirmed or state.removed or isbox or not IsValid(ply) or start:DistToSqr(ply:EyePos())>1 then return end
 local length=delta:Length()
 if length<1 or delta:GetNormalized():Dot(ply:GetAimVector())<0.99999 then return end
 local distance=math.max(0,start:Distance(state.plan.tracePoint)-0.5)
 if distance>=length then return end
 -- The engine clips delta against the world before testing entities. Only the
 -- entrance must precede that wall; pickup_plan already checked the full path.
 return {HitPos=state.hit,Normal=-ply:GetAimVector(),Fraction=distance/length}
end
local function pickup_mesh(phys)
 local convexes=phys:GetMeshConvexes()
 if not istable(convexes) or #convexes==0 then return end
 local mesh,total={},0
 for _,convex in ipairs(convexes) do
  local vertices={}
  for _,vertex in ipairs(convex) do
   total=total+1
   if total>16000 then return end
   vertices[#vertices+1]=Vector(vertex.pos)
  end
  mesh[#mesh+1]=vertices
 end
 return mesh
end
local function begin(ply)
 local plan,group,phys,grab,bone=pickup_plan(ply)
 if not plan then return end
 local mesh=pickup_mesh(phys)
 if not mesh then return end
 local state={ply=ply,plan=plan,phys=phys,group=group,bone=bone}
 local ok,err=xpcall(function()
  if plan.root:IsNPC() and plan.root:GetMoveType()~=MOVETYPE_VPHYSICS then
   state.npcMoveType=plan.root:GetMoveType()
   plan.root:SetMoveType(MOVETYPE_NONE)
  end
  for _,item in ipairs(plan.items) do
   if IsValid(item.owner) then item.owner:RemoveEntity(item.entity) end
   item.entity:SetPos(item.newpos) item.entity:SetAngles(item.newang)
   for _,body in ipairs(item.bodies) do
    body.phys:SetPos(body.newpos,true) body.phys:SetAngles(body.newang)
    body.phys:SetVelocity(vector_origin) body.phys:SetAngleVelocity(vector_origin)
   end
  end
  local handle=ents.Create('base_anim') state.handle=handle
  handle:SetModel(plan.root:GetModel()) handle:SetPos(plan.root:GetPos()) handle:SetAngles(plan.root:GetAngles())
  handle:SetModelScale(plan.root:GetModelScale(),0)
  handle:Spawn() handle:SetSolid(SOLID_VPHYSICS)
  if not handle:PhysicsInitMultiConvex(mesh) then error('native pickup physics failed') end
  handle:SetMoveType(MOVETYPE_VPHYSICS)
  handle:SetCollisionBounds(plan.root:OBBMins(),plan.root:OBBMaxs())
  handle:SetNoDraw(true) handle.DisableDuplicator=true
  handle:SetName('seamless_portals_native_physgun_handle')
  handle.SEAMLESS_PORTALS_NATIVE_PICKUP=state
  handle:GetPhysicsObject():SetMass(phys:GetMass()) handle:GetPhysicsObject():EnableMotion(false)
  local weld=state.npcMoveType and constraint.NoCollide(handle,plan.root,0,bone) or constraint.Weld(handle,plan.root,0,bone,0,true,false)
  if not IsValid(weld) then error('native pickup weld failed') end
  state.weld=weld weld.DisableDuplicator=true
  group[#group+1]=handle
  local record={entity=plan.root,controllerEntity=handle,kind='physgun',player=ply,group=group,
   crossed=not plan.localNPC,nativePickup=state}
  state.record=record
  if not plan.localNPC and not SP.StartCarryCorridor(ply,record,plan.exit,group) then error('native pickup corridor failed') end
  record.contact=SP.CaptureCarryPose(group)
  state.flags=handle:GetSolidFlags() state.lo,state.hi=handle:GetCollisionBounds()
  local lo,hi=handle:WorldToLocal(plan.tracePoint)-Vector(2,2,2),handle:WorldToLocal(plan.tracePoint)+Vector(2,2,2)
  for i=1,3 do lo[i]=math.min(lo[i],state.lo[i]);hi[i]=math.max(hi[i],state.hi[i]) end
  handle:SetCollisionBounds(lo,hi)
  local d=plan.tracePoint-handle:GetPos()
  handle:SetSurroundingBounds(d-Vector(4,4,4),d+Vector(4,4,4))
  handle:EnableCustomCollisions()
  state.hit=phys:LocalToWorld(grab) state.grab=grab
  handle:SetNWEntity('seamless_portals_native_target',plan.root)
  handle:SetNWBool('seamless_portals_physgun_entity_grab',state.npcMoveType~=nil)
  handle.TestCollision=function(self,start,delta,isbox)
   return SP.NativePhysgunSelection(state,start,delta,isbox)
  end
  SP.NativePickupStates[handle]=state
  SP.NativePickupTargets[plan.root]=state
 end,debug.traceback)
 if not ok then remove_state(state,true) ErrorNoHalt(tostring(err)..'\n') end
end
hook.Add('PlayerPostThink','seamless_portals_native_physgun_pickup',function(ply)
 if not ply:Alive() or SP.GetHeldRecord(ply) or not ply:KeyDown(IN_ATTACK) or SP.WantsPortalPhysgun(ply) then return end
 local weapon=ply:GetActiveWeapon()
 if not IsValid(weapon) or weapon:GetClass()~='weapon_physgun' then return end
 for _,state in pairs(SP.NativePickupStates) do if state.ply==ply then return end end
 if (SP.NativePickupNext[ply] or 0)>CurTime() then return end
 SP.NativePickupNext[ply]=CurTime()+0.1
 begin(ply)
end)
hook.Add('PhysgunPickup','seamless_portals_native_physgun_pickup',function(ply,ent)
 local owner=SP.NativePickupTargets[ent]
 if owner and owner.permissionPlayer~=ply then return false end
 local state=ent.SEAMLESS_PORTALS_NATIVE_PICKUP
 if not state then
  -- Select a native physics handle before the first grab. The engine's NPC
  -- controller otherwise clips every move against the uncut map wall.
  if ent:IsNPC() and ent:GetMoveType()~=MOVETYPE_VPHYSICS
   and IsValid(ent:GetPhysicsObject()) and not owner and permissionPlayers[ent]~=ply
   and not SP.WantsPortalPhysgun(ply) then return false end
  return
 end
 if state.ply~=ply or state.confirmed then return false end
 state.permissionPlayer=ply
 local ok,result=xpcall(function() return hook.Run('PhysgunPickup',ply,state.plan.root) end,debug.traceback)
 state.permissionPlayer=nil
 if not ok then ErrorNoHalt(tostring(result)..'\n') return false end
 return result==true
end)
for _,event in ipairs({'AllowPlayerPickup','GravGunPickupAllowed'}) do
 hook.Add(event,'seamless_portals_native_physgun_pickup',function(ply,ent)
  if SP.NativePickupTargets[ent] or ent.SEAMLESS_PORTALS_NATIVE_PICKUP then return false end
 end)
end
hook.Add('OnPhysgunPickup','seamless_portals_native_physgun_pickup',function(ply,ent)
 local state=ent.SEAMLESS_PORTALS_NATIVE_PICKUP
 if state and state.ply==ply then state.phys:EnableMotion(true) end
end)
hook.Add('Think','seamless_portals_native_physgun_pickup',function()
 for _,state in pairs(SP.NativePickupStates) do
  local handle=state.handle
  if state.confirmed and state.npcMoveType and SP.IsLiveEntity(state.plan.root)
   and IsValid(handle) and handle:IsPlayerHolding() then
   -- NPCs use a movement hull, not a dynamic VPhysics body. Follow the native
   -- handle while their motor waits; keep their original shadow body intact.
   local root=state.plan.root
   root:SetPos(handle:GetPos()) root:SetAngles(handle:GetAngles())
   local body=root:GetPhysicsObject()
   if IsValid(body) then body:SetPos(handle:GetPos(),true) body:SetAngles(handle:GetAngles()) end
  end
  if state.confirmed and (not IsValid(state.ply) or not SP.IsLiveEntity(state.plan.root) or not IsValid(handle)) then
   SP.ClearHold(state.ply,state.plan.root)
  end
  if not state.confirmed then
   restore_bounds(state)
   local actual=SP.GetHeldRecord(state.ply)
   if IsValid(handle) and handle:IsPlayerHolding() and actual and actual.controllerEntity==handle and actual.entity==state.plan.root then
    for _,key in ipairs({'player','entry','exit','group','safe','crossed','contact','nativePickup'}) do actual[key]=state.record[key] end
    state.record=actual state.confirmed=true
    for _,ent in ipairs(state.group) do ent.SEAMLESS_PORTALS_CARRY=actual end
    handle.SEAMLESS_PORTALS_CARRY=actual
    state.ply:SetNWEntity('seamless_portals_native_physgun_handle',handle)
    state.ply:SetNWVector('seamless_portals_physgun_grab',state.grab)
    state.ply:SetNWInt('seamless_portals_physgun_bone',state.bone)
   else remove_state(state,true) end
  elseif SP.Holds[state.ply]~=state.record and not state.record.entry then remove_state(state,false) end
 end
end)
hook.Add('OnPhysgunFreeze','seamless_portals_native_physgun_pickup',function(weapon,phys,ent,ply)
 local state=ent.SEAMLESS_PORTALS_NATIVE_PICKUP
 if not state then return end
 if not SP.IsLiveEntity(state.plan.root) or not IsValid(state.phys) then return false end
 local result=hook.Run('OnPhysgunFreeze',weapon,state.phys,state.plan.root,ply)
 if result==false or state.phys:IsMotionEnabled() then return false end
end)
