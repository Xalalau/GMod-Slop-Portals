-- Native gravity-gun traces stop at the portal. Relay forces to the real body;
-- pulled objects cross normally before the native grab controller attaches.
local SP=SeamlessPortals
local mask=bit.bor(MASK_SHOT,CONTENTS_GRATE)
local pulling=setmetatable({},{__mode="k"})
local punting,checking=false,false

local function setting(name,default,maximum)
    local cv=GetConVar(name)
    local value=cv and cv:GetFloat() or default
    return SP.IsFinite(value) and math.Clamp(value,0,maximum) or default
end

local function proxy(ent)
    return SP.IsLiveEntity(ent) and ent:GetClass()=="seamless_portal_clone"
end

function SP.TraceGravityGun(ply,pull)
    local range=setting("physcannon_tracelength",250,4096)*(pull and 4 or 1)
    local start,direction=ply:GetShootPos(),ply:GetAimVector()
    local result=SP.TracePortalLine({start=start,endpos=start+direction*range,filter=ply,
        mask=mask,SeamlessFeature="props",SeamlessMaxHops=4})
    local segments=result.SeamlessSegments
    local origin=Vector(start)
    local puntDirection=Vector(direction)
    local links={}
    local last=result
    if segments then
        for i=1,#segments-1 do
            local entry=segments[i].Entity
            local exit=SP.IsPortal(entry) and entry:GetExitPortal()
            if not SP.SupportsPropTraversal(entry,exit) or exit:GetExitPortal()~=entry then return end
            links[#links+1]={entry,exit}
            origin=SP.TransformPortal(entry,exit,origin)
            puntDirection=SP.TransformDirection(entry,exit,puntDirection,false)
        end
        last=segments[#segments]
        -- Keep the small native selection hull within the final traced segment.
        if not last.Hit or last.HitWorld then
            local exit=segments[#segments-1].Entity:GetExitPortal()
            local radius=pull and 4 or 8
            local hull=util.TraceHull({start=last.StartPos,endpos=last.HitPos,
                mins=Vector(-radius,-radius,-radius),maxs=Vector(radius,radius,radius),
                filter={ply,exit},mask=mask,SeamlessIgnore=true})
            if hull.Hit and not hull.StartSolid and not hull.AllSolid then last=hull end
        end
    elseif not proxy(result.Entity) then return end
    if not last.Hit or last.StartSolid or last.AllSolid or last.HitWorld or last.HitSky then return end
    local path={}
    for _,leg in ipairs(segments or {result}) do
        path[#path+1]={start=Vector(leg.StartPos),finish=Vector(leg.HitPos)}
    end
    path[#path].finish=Vector(last.HitPos)
    local root,hit=last.Entity,last.HitPos
    if not root then return end
    if proxy(root) then
        ---@cast root any
        local entry,exit=root:GetPortal2(),root:GetPortal1()
        if not SP.SupportsPropTraversal(entry,exit) or exit:GetExitPortal()~=entry then return end
        links[#links+1]={entry,exit}
        origin=SP.TransformPortal(entry,exit,origin)
        hit=SP.TransformPortal(entry,exit,hit)
        puntDirection=SP.TransformDirection(entry,exit,puntDirection,false)
        root=root:GetChild()
    end
    if not SP.IsLiveEntity(root) or SP.IsPortal(root) or proxy(root) then return end
    return {entity=root,hit=hit,origin=origin,direction=puntDirection,trace=last,links=links,segments=path}
end

local function eligible(ply,plan,pull)
    local ent=plan and plan.entity
    if not SP.IsLiveEntity(ent) or ent:IsPlayer() or ent:IsNPC() or ent:GetMoveType()~=MOVETYPE_VPHYSICS
        or IsValid(ent:GetParent()) or ent:IsPlayerHolding() or SP.HasTrackedHold(ent)
        or ent.SEAMLESS_PORTALS_NATIVE_PICKUP or (SP.NativePickupTargets and SP.NativePickupTargets[ent])
        or ent:IsEFlagSet(EFL_NO_PHYSCANNON_INTERACTION) then return false end
    if ent:GetClass()=="seamless_portal_cutout" then return false end
    local count=ent:GetPhysicsObjectCount()
    if count<1 or count>32 then return false end
    local mass,bodies=0,{}
    for i=0,count-1 do
        local phys=ent:GetPhysicsObjectNum(i)
        if not IsValid(phys) or not phys:IsMotionEnabled() or phys:HasGameFlag(FVPHYSICS_PLAYER_HELD)
            or (pull and phys:HasGameFlag(FVPHYSICS_NO_PLAYER_PICKUP)) then return false end
        local weight=phys:GetMass()
        if not SP.IsFinite(weight) or weight<=0 then return false end
        bodies[#bodies+1]=phys
        mass=mass+weight
    end
    if not SP.IsFinite(mass) or mass<=0 then return false end
    if pull and (mass>setting("physcannon_maxmass",250,50000) or ply:GetGroundEntity()==ent) then return false end
    if SERVER then
        if checking then return false end
        checking=true
        local ok,result=xpcall(function()
            return hook.Run(pull and "GravGunPickupAllowed" or "GravGunPunt",ply,ent)
        end,debug.traceback)
        checking=false
        if not ok then ErrorNoHalt("[Seamless Portals] Gravity gun permission: "..tostring(result).."\n") end
        if not ok or result~=true then return false end
    end
    -- Permission callbacks may remove or replace their target.
    if not SP.IsLiveEntity(ent) or ent:IsPlayerHolding() or SP.HasTrackedHold(ent) then return false end
    for _,link in ipairs(plan.links) do
        if not SP.SupportsPropTraversal(link[1],link[2]) or link[2]:GetExitPortal()~=link[1] then return false end
    end
    if ent:GetPhysicsObjectCount()~=count then return false end
    for i,phys in ipairs(bodies) do
        if not IsValid(phys) or ent:GetPhysicsObjectNum(i-1)~=phys or not phys:IsMotionEnabled()
            or phys:HasGameFlag(FVPHYSICS_PLAYER_HELD) then return false end
    end
    plan.bodies=bodies
    return true,mass
end

local function activeWeapon(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or SP.GetHeldRecord(ply) then return end
    local weapon=ply:GetActiveWeapon()
    if IsValid(weapon) and weapon:GetClass()=="weapon_physcannon"
        and weapon:GetInternalVariable("m_bActive")~=true then return weapon end
end

function SP.PuntThroughPortal(ply)
    if CLIENT then return false end
    if punting or checking then return false end
    local weapon=activeWeapon(ply)
    if not weapon then return false end
    local plan=SP.TraceGravityGun(ply,false)
    if not plan or not plan.entity then return false end
    local allowed,mass=eligible(ply,plan,false)
    if not allowed then return false end
    if activeWeapon(ply)~=weapon then return false end
    if SERVER then
        local ent=plan.entity
        local primary=ent:GetPhysicsObject()
        local cap=ent:IsVehicle() and 625 or 250
        punting=true
        local ok,err=xpcall(function()
            for _,phys in ipairs(plan.bodies) do
                local ratio=phys:GetMass()/mass
                ratio=phys==primary and math.min(1,ratio+0.5) or ratio*0.5
                phys:ApplyForceCenter(plan.direction*15000*ratio)
                phys:ApplyForceOffset(plan.direction*math.min(mass,cap)*600*ratio,plan.hit)
                phys:AddGameFlag(FVPHYSICS_WAS_THROWN)
            end
            ent:SetPhysicsAttacker(ply,10)
            SP.SendBulletVisual({shooter=ply,name="seamless_gravitygun",draw=true,segments=plan.segments})
            ply:EmitSound("Weapon_PhysCannon.Launch")
        end,debug.traceback)
        punting=false
        if not ok then ErrorNoHalt("[Seamless Portals] Gravity gun punt: "..tostring(err).."\n") return false end
    end
    weapon:SendWeaponAnim(ACT_VM_SECONDARYATTACK)
    ply:ViewPunch(Angle(-6,0,0))
    weapon:SetNextSecondaryFire(CurTime()+0.5)
    pulling[weapon]=CurTime()+0.5
    return true
end

function SP.GravityGunPuntFeedback(weapon)
    if not CLIENT or not IsValid(weapon) or weapon:GetClass()~="weapon_physcannon" then return end
    local ply=weapon:GetOwner()
    if not IsValid(ply) or ply~=LocalPlayer() or ply:GetActiveWeapon()~=weapon then return end
    weapon:SendWeaponAnim(ACT_VM_SECONDARYATTACK)
end

hook.Add("GravGunPunt","seamless_portals_gravitygun",function(ply,ent)
    if not SP.IsPortal(ent) and not proxy(ent) then return end
    if not punting then SP.PuntThroughPortal(ply) end
    return false
end)

function SP.SuppressPortalGravitySound(event)
    if event.OriginalSoundName~="Weapon_PhysCannon.TooHeavy" then return false end
    local ply=event.Entity
    if not IsValid(ply) then return false end
    if not ply:IsPlayer() then ply=ply:GetOwner() end
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    local weapon=ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass()~="weapon_physcannon" then return false end
    local start=ply:GetShootPos()
    local tr=SP.RawTraceLine({start=start,endpos=start+ply:GetAimVector()*setting("physcannon_tracelength",250,4096)*4,
        filter=ply,mask=mask,SeamlessIgnore=true})
    return SP.IsPortal(tr.Entity) or proxy(tr.Entity)
end

-- The native grip shortens at brush walls and uses the player's current hull
-- radius. Portal cutouts and our temporary narrow hull must not shorten it.
local gripMeshes=setmetatable({},{__mode="k"})
local function gripExtent(ent,phys,direction)
    local cached=gripMeshes[phys]
    if not cached then
        local mesh=phys:GetMesh()
        cached={mesh=mesh and #mesh<=4096 and mesh or false}
        if not mesh then
            local lo,hi=phys:GetAABB()
            if lo and hi then cached.sphere=(hi-lo):Length()/math.sqrt(12) end
        end
        gripMeshes[phys]=cached
    end
    if cached.sphere then return cached.sphere end
    if not cached.mesh or #cached.mesh==0 then return end
    local localDirection=ent:WorldToLocal(ent:GetPos()+direction)
    if cached.direction and localDirection:DistToSqr(cached.direction)<1e-10 then return cached.extent end
    local minimum=math.huge
    for _,vertex in ipairs(cached.mesh) do minimum=math.min(minimum,vertex.pos:Dot(localDirection)) end
    cached.direction,cached.extent=localDirection,math.abs(minimum)
    return cached.extent
end

SP.GravityGripOffsets=SP.GravityGripOffsets or setmetatable({},{__mode="k"})
local gripOffsets=SP.GravityGripOffsets
function SP.RestoreGravityGunGrip(ply)
    local pending=gripOffsets[ply]
    if not pending then return end
    gripOffsets[ply]=nil
    if IsValid(ply) then
        if ply:GetCurrentViewOffset()==pending.applied then ply:SetCurrentViewOffset(pending.original) end
        if pending.angles and ply:EyeAngles()==pending.appliedAngles then ply:SetEyeAngles(pending.angles) end
        for _,hull in ipairs(pending.hulls or {}) do
            local lo,hi=ply[hull.get](ply)
            if lo==hull.appliedLo and hi==hull.appliedHi then ply[hull.set](ply,hull.lo,hull.hi) end
        end
    end
end
function SP.ClearGravityGunGrips()
    for ply in pairs(gripOffsets) do SP.RestoreGravityGunGrip(ply) end
end
SP.ClearGravityGunGrips()

function SP.PrepareGravityGunGrip(ply)
    SP.RestoreGravityGunGrip(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local weapon=ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass()~="weapon_physcannon" then return end
    local record=SP.GetHeldRecord(ply)
    if not record or (SERVER and record.kind~="gravgun") then return end
    local ent=record.entity
    if not SP.IsLiveEntity(ent) then return end
    local phys=ent:GetPhysicsObject()
    if not IsValid(phys) or not phys:IsMotionEnabled() then return end
    local angles=ply:EyeAngles()
    angles.p=math.Clamp(math.NormalizeAngle(angles.p),-75,75)
    local direction=angles:Forward()
    local extent=gripExtent(ent,phys,direction)
    if not extent or not SP.IsFinite(extent) or extent>512 then return end
    local hull=ply:OBBMaxs()
    local saved=ply:Crouching() and ply.SEAMLESS_PORTALS_HULL_DUCK_MAXS or ply.SEAMLESS_PORTALS_HULL_MAXS
    local radius=hull:Length2D()+extent
    local desired=24+(saved and (saved*ply:GetModelScale()):Length2D() or hull:Length2D())+extent
    local start=ply:GetShootPos()
    local function shortGrip(shift)
        local origin=start+direction*shift
        return SP.RawTraceLine({start=origin,endpos=origin+direction*(24+radius*2),
            filter={ply,ent},mask=MASK_SOLID_BRUSHONLY}).Fraction<0.5
    end
    local shift=desired-(24+radius)
    local offset,hullFactor
    if shortGrip(shift) then
        local crossing=SP.FirstCrossing(start,direction*desired,"props")
        if not crossing or not SP.SupportsPropTraversal(crossing.entry,crossing.exit)
            or crossing.exit:GetExitPortal()~=crossing.entry then return end
        -- A wall before the opening remains ordinary cover.
        local front=SP.RawTraceLine({start=start,endpos=crossing.point,filter={ply,ent},mask=MASK_SOLID_BRUSHONLY})
        if front.StartSolid or front.AllSolid or (front.Hit and front.HitPos:DistToSqr(crossing.point)>1) then return end
        shift=desired-radius*0.5
        if not shortGrip(shift) then
            -- The native clearance sphere can keep the same grip when a thin
            -- brush invalidates the shifted trace. Keep the view angles intact.
            local horizontal=direction:Length2D()
            local clearance=math.max(desired-24,desired*horizontal)
            if (start-ply:GetPos()):Length2D()>0.01 or hull:Length2D()<0.01 then return end
            local function accepts(candidate,short)
                local origin=start+candidate
                local tr=SP.RawTraceLine({start=origin,endpos=origin+direction*(24+2*clearance),
                    filter={ply,ent},mask=MASK_SOLID_BRUSHONLY})
                return (tr.Fraction<0.5)==short
            end
            -- After the native short trace, its player-clearance clamp supplies
            -- the horizontal reach. This offset preserves the vertical reach.
            offset=Vector(0,0,direction.z*(desired-clearance*0.5))
            if not accepts(offset,true) then
                local length=24+clearance
                offset=Vector(direction.x*(6-length),direction.y*(6-length),direction.z*(desired-length))
                if not accepts(offset,false) then return end
            end
            hullFactor=(clearance-extent)/hull:Length2D()
        end
    end
    if not offset and math.abs(shift)<0.001 then return end
    local original=Vector(ply:GetCurrentViewOffset())
    local pending={original=original,applied=original+(offset or direction*shift),entity=ent,weapon=weapon}
    gripOffsets[ply]=pending
    if hullFactor then
        pending.hulls={}
        for _,names in ipairs({{"GetHull","SetHull"},{"GetHullDuck","SetHullDuck"}}) do
            local lo,hi=ply[names[1]](ply)
            local appliedLo,appliedHi=Vector(lo),Vector(hi)
            appliedLo.x,appliedLo.y=lo.x*hullFactor,lo.y*hullFactor
            appliedHi.x,appliedHi.y=hi.x*hullFactor,hi.y*hullFactor
            pending.hulls[#pending.hulls+1]={get=names[1],set=names[2],lo=Vector(lo),hi=Vector(hi),
                appliedLo=appliedLo,appliedHi=appliedHi}
            ply[names[2]](ply,appliedLo,appliedHi)
        end
    end
    -- Only ItemPreFrame sees this origin. Movement, firing and rendering use
    -- the restored eye position; the native controller keeps the real body.
    ply:SetCurrentViewOffset(pending.applied)
    timer.Simple(0,function()
        if gripOffsets[ply]==pending then SP.RestoreGravityGunGrip(ply) end
    end)
end
hook.Add("StartCommand","seamless_portals_gravitygun_grip",SP.PrepareGravityGunGrip)
hook.Add("SetupMove","seamless_portals_gravitygun_grip",SP.RestoreGravityGunGrip)
hook.Add("PlayerPostThink","seamless_portals_gravitygun_grip",SP.RestoreGravityGunGrip)
for _,event in ipairs({"GravGunOnDropped","PlayerDeath","PlayerSilentDeath","PlayerDisconnected"}) do
    hook.Add(event,"seamless_portals_gravitygun_grip",SP.RestoreGravityGunGrip)
end
hook.Add("EntityRemoved","seamless_portals_gravitygun_grip",function(ent)
    for ply,pending in pairs(gripOffsets) do
        if ent==pending.entity or ent==pending.weapon then SP.RestoreGravityGunGrip(ply) end
    end
end)
hook.Add("PostCleanupMap","seamless_portals_gravitygun_grip",SP.ClearGravityGunGrips)
hook.Add("ShutDown","seamless_portals_gravitygun_grip",SP.ClearGravityGunGrips)

-- Cache each exceptional pair outside the physics callback, in both realms.
local collisionKey="seamless_portals_gravity_passage_holder"
SP.GravityPassageOwners=SP.GravityPassageOwners or setmetatable({},{__mode="k"})
local passageOwners=SP.GravityPassageOwners
function SP.SetGravityPassageOwner(ent,ply)
    local old=passageOwners[ent]
    if not IsValid(ent) then passageOwners[ent]=nil return end
    ply=IsValid(ply) and ply:IsPlayer() and ply or nil
    if (old and old.player)==ply then return end
    local custom=ent:GetCustomCollisionCheck()
    if old then custom=old.custom end
    passageOwners[ent]=ply and {player=ply,custom=custom} or nil
    if ply then ent:SetCustomCollisionCheck(true)
    elseif not custom then ent:SetCustomCollisionCheck(false) end
    ent:CollisionRulesChanged()
    if SERVER then ent:SetNWEntity(collisionKey,ply or NULL) end
end
hook.Add("ShouldCollide","seamless_portals_gravitygun_passage",function(a,b)
    local first,second=passageOwners[a],passageOwners[b]
    if (first and first.player==b) or (second and second.player==a) then return false end
end)
hook.Add("EntityNetworkedVarChanged","seamless_portals_gravitygun_passage",function(ent,key,_,value)
    if CLIENT and key==collisionKey then SP.SetGravityPassageOwner(ent,value) end
end)
hook.Add("EntityRemoved","seamless_portals_gravitygun_passage",function(ent)
    passageOwners[ent]=nil
    for member,state in pairs(passageOwners) do
        if state.player==ent then SP.SetGravityPassageOwner(member,nil) end
    end
end)
function SP.ClearGravityPassageOwners()
    for ent in pairs(passageOwners) do SP.SetGravityPassageOwner(ent,nil) end
end
hook.Add("PostCleanupMap","seamless_portals_gravitygun_passage",SP.ClearGravityPassageOwners)
hook.Add("ShutDown","seamless_portals_gravitygun_passage",SP.ClearGravityPassageOwners)

if not SERVER then return end

function SP.RefreshGravityPassageOwners()
    local wanted={}
    for ply,record in pairs(SP.Holds) do
        if IsValid(ply) and record.kind=="gravgun" and SP.IsPortal(record.entry)
            and SP.GetHeldRecord(ply)==record then
            for _,ent in ipairs(record.group or {record.entity}) do
                if SP.IsLiveEntity(ent) then
                    wanted[ent]=ply
                    local clone=ent.SEAMLESS_PORTALS_CLONE
                    if SP.IsLiveEntity(clone) then wanted[clone]=ply end
                end
            end
            if SP.IsLiveEntity(record.controllerEntity) then wanted[record.controllerEntity]=ply end
        end
    end
    for ent in pairs(passageOwners) do if not wanted[ent] then SP.SetGravityPassageOwner(ent,nil) end end
    for ent,ply in pairs(wanted) do SP.SetGravityPassageOwner(ent,ply) end
end
hook.Add("Think","seamless_portals_gravitygun_passage",SP.RefreshGravityPassageOwners)

-- ItemPreFrame checks the previous grab target before updating it for the
-- teleported player. Keep its error sample in that old space for this one call.
SP.GravityCarryTransfers=SP.GravityCarryTransfers or setmetatable({},{__mode="k"})
local transfers=SP.GravityCarryTransfers
function SP.FinishGravityGunTransfer(ply)
    local pending=transfers[ply]
    if not pending then return end
    transfers[ply]=nil
    for _,item in ipairs(pending.plan.items) do
        for _,body in ipairs(item.bodies) do
            local phys=body.phys
            if IsValid(item.entity) and IsValid(phys) and item.entity:GetPhysicsObjectNum(body.index)==phys then
                if pending.rebased then
                    phys:SetPos(body.newpos,true) phys:SetAngles(body.newang)
                    phys:SetVelocity(body.newvel) phys:SetAngleVelocity(body.angular)
                end
                if body.motion then phys:Wake() end
            end
        end
    end
end
function SP.ClearGravityGunTransfers()
    for ply in pairs(transfers) do SP.FinishGravityGunTransfer(ply) end
end
function SP.PrepareGravityGunTransfer(plan)
    local ply=plan.holder
    if not IsValid(ply) then return end
    local hold=SP.GetHeldRecord(ply)
    if not hold or hold.kind~="gravgun" or hold.entity~=plan.root then return end
    local weapon=ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass()~="weapon_physcannon" then return end
    SP.FinishGravityGunTransfer(ply)
    transfers[ply]={plan=plan,hold=hold,weapon=weapon}
    -- Sleeping skips the single physics step with the stale native target.
    -- Motion, constraints and the native grab controller remain intact.
    for _,item in ipairs(plan.items) do for _,body in ipairs(item.bodies) do body.phys:Sleep() end end
end
hook.Add("StartCommand","seamless_portals_gravitygun_transfer",function(ply)
    local pending=transfers[ply]
    if not pending then return end
    if pending.rebased or SP.GetHeldRecord(ply)~=pending.hold or ply:GetActiveWeapon()~=pending.weapon then
        SP.FinishGravityGunTransfer(ply) return
    end
    for _,item in ipairs(pending.plan.items) do for _,body in ipairs(item.bodies) do
        if not IsValid(item.entity) or not IsValid(body.phys) or item.entity:GetPhysicsObjectNum(body.index)~=body.phys then
            SP.FinishGravityGunTransfer(ply) return
        end
    end end
    pending.rebased=true
    -- No physics integration occurs between StartCommand and SetupMove.
    for _,item in ipairs(pending.plan.items) do for _,body in ipairs(item.bodies) do
        body.phys:SetPos(body.pos,true) body.phys:SetAngles(body.ang)
    end end
    timer.Simple(0,function()
        if transfers[ply]==pending and pending.rebased then SP.FinishGravityGunTransfer(ply) end
    end)
end)
hook.Add("SetupMove","seamless_portals_gravitygun_transfer",SP.FinishGravityGunTransfer)
hook.Add("PlayerPostThink","seamless_portals_gravitygun_transfer",function(ply)
    if transfers[ply] and transfers[ply].rebased then SP.FinishGravityGunTransfer(ply) end
end)
for _,event in ipairs({"GravGunOnDropped","PlayerDeath","PlayerDisconnected"}) do
    hook.Add(event,"seamless_portals_gravitygun_transfer",SP.FinishGravityGunTransfer)
end
hook.Add("EntityRemoved","seamless_portals_gravitygun_transfer",function(ent)
    for ply,pending in pairs(transfers) do
        if ent==pending.weapon or ent==pending.plan.root then SP.FinishGravityGunTransfer(ply) end
    end
end)
hook.Add("PostCleanupMap","seamless_portals_gravitygun_transfer",SP.ClearGravityGunTransfers)
hook.Add("ShutDown","seamless_portals_gravitygun_transfer",SP.ClearGravityGunTransfers)

hook.Add("GravGunPickupAllowed","seamless_portals_gravitygun",function(_,ent)
    if SP.IsPortal(ent) or proxy(ent) then return false end
end)

function SP.PullThroughPortal(ply)
    if checking then return false end
    local weapon=activeWeapon(ply)
    if not weapon then return false end
    local plan=SP.TraceGravityGun(ply,true)
    if not plan or not plan.entity then return false end
    local allowed,mass=eligible(ply,plan,true)
    if not allowed then return false end
    if activeWeapon(ply)~=weapon or not SP.CollectTransportGroup(plan.entity,ply) then return false end
    local phys=plan.entity:GetPhysicsObject()
    if not IsValid(phys) then return false end
    local force=setting("physcannon_pullforce",4000,100000)
    if mass<50 then force=force*(mass+0.5)/50 end
    phys:ApplyForceCenter((plan.origin-plan.entity:WorldSpaceCenter()):GetNormalized()*force)
    return true
end

hook.Add("PlayerPostThink","seamless_portals_gravitygun",function(ply)
    if not ply:Alive() or not ply:KeyDown(IN_ATTACK2) or ply:KeyDown(IN_ATTACK) or SP.GetHeldRecord(ply) then return end
    local weapon=ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass()~="weapon_physcannon"
        or weapon:GetInternalVariable("m_bActive")==true or (pulling[weapon] or 0)>CurTime() then return end
    pulling[weapon]=CurTime()+0.1
    SP.PullThroughPortal(ply)
end)
