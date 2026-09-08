-- Native HL2 melee bypasses util.TraceLine. Continue only its portal impact;
-- hitscan retains its own pellet callback and spread/damage accounting.
local SP=SeamlessPortals
local ranges={weapon_crowbar=75,weapon_stunstick=75}
local hull=Vector(16,16,16)
local swings=setmetatable({},{__mode="k"})

local function remoteHit(result)
    return result.SeamlessSegments~=nil and result.Hit and not SP.IsPortal(result.Entity)
        and not result.StartSolid and not result.AllSolid and not result.HitSky
end

local function traceSwing(attacker,direction,range)
    local start=attacker:GetShootPos()
    return SP.TracePortalLine({start=start,endpos=start+direction*range,
        filter=attacker,mask=MASK_SHOT_HULL,SeamlessFeature="damage"})
end

local function nativeSwingTrace(attacker,range)
    local start=attacker:GetShootPos()
    local direction=attacker:GetAimVector()
    local data={start=start,endpos=start+direction*range,filter=attacker,
        mask=MASK_SHOT_HULL,SeamlessIgnore=true}
    local raw=SP.RawTraceLine
    local trace=raw(data)
    if trace.Hit then return trace end
    -- Match the native short hull and its corner refinement at aperture edges.
    data.endpos=start+direction*(range-1.732*16)
    data.mins,data.maxs=-hull,hull
    trace=util.TraceHull(data)
    if not trace.Hit or not IsValid(trace.Entity)
        or (trace.Entity:GetPos()-start):GetNormalized():Dot(direction)<0.70721 then return end
    data.mins,data.maxs=nil,nil
    local endpoint=start+(trace.HitPos-start)*2
    data.endpos=endpoint
    local refined=raw(data)
    if refined.Hit then return refined end
    local nearest=math.huge
    for x=-1,1,2 do for y=-1,1,2 do for z=-1,1,2 do
        data.endpos=endpoint+Vector(x*16,y*16,z*16)
        local corner=raw(data)
        if corner.Hit then
            local distance=start:DistToSqr(corner.HitPos)
            if distance<nearest then trace,nearest=corner,distance end
        end
    end end end
    return trace
end

function SP.SuppressPortalMeleeSound(event)
    -- ImpactTrace suppresses surface effects, but native crowbar Hit also emits
    -- this separate flesh sound for every entity, including an empty portal.
    local name=event.OriginalSoundName or event.SoundName
    if name~="Weapon_Crowbar.Melee_Hit" and name~="Weapon_Crowbar.Melee_HitWorld" then return false end
    local attacker=event.Entity
    if not IsValid(attacker) then return false end
    if not attacker:IsPlayer() then attacker=attacker:GetOwner() end
    if not IsValid(attacker) or not attacker:IsPlayer() then return false end
    local weapon=attacker:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass()~="weapon_crowbar" then return false end
    local trace=nativeSwingTrace(attacker,ranges.weapon_crowbar)
    return trace~=nil and SP.IsPortal(trace.Entity)
end

hook.Add("DoAnimationEvent","seamless_portals_melee_animation",function(attacker,event)
    if event~=PLAYERANIMEVENT_ATTACK_PRIMARY or not IsValid(attacker) then return end
    local weapon=attacker:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass()~="weapon_crowbar" then return end
    local hit
    local swing=swings[weapon]
    swings[weapon]=nil
    if swing and swing.time==CurTime() then
        -- Keep the hit animation even if damage just removed the remote target.
        hit=swing.hit
    else
        local trace=nativeSwingTrace(attacker,ranges.weapon_crowbar)
        if not trace or not SP.IsPortal(trace.Entity) then return end
        local enabled=GetConVar("seamless_portals_damage")
        hit=(not enabled or enabled:GetBool())
            and remoteHit(traceSwing(attacker,attacker:GetAimVector(),ranges.weapon_crowbar))
    end
    -- Native Swing has selected its viewmodel animation before this event.
    -- Leave the player's gesture and attack cooldown to the engine/gamemode.
    if not hit then weapon:SendWeaponAnim(ACT_VM_MISSCENTER) end
end)

if not SERVER then return end
local relaying=false
function SP.RelayPortalMelee(portal,info,direction,trace)
    if relaying or not info:IsDamageType(DMG_CLUB) then return false end
    local attacker=info:GetAttacker()
    if not IsValid(attacker) or not attacker:IsPlayer() then return false end
    local weapon=attacker:GetActiveWeapon()
    local range=IsValid(weapon) and ranges[weapon:GetClass()]
    if not range then return false end
    local swing={time=CurTime(),hit=false}
    swings[weapon]=swing
    local enabled=GetConVar("seamless_portals_damage")
    if enabled and not enabled:GetBool() then return false end
    local start=attacker:GetShootPos()
    direction=direction:GetNormalized()
    if not SP.CanCrossTrace(trace,start,direction,"damage") then return false end
    local result=traceSwing(attacker,direction,range)
    if not remoteHit(result) then return false end
    swing.hit=true
    local segments=result.SeamlessSegments
    local last=segments[#segments]
    local values=SP.SnapshotDamage(info)
    for i=1,#segments-1 do
        local entry=segments[i].Entity
        values.DamageForce=SP.TransformDirection(entry,entry:GetExitPortal(),values.DamageForce,false)
    end
    values.DamagePosition=Vector(result.HitPos)
    values.Weapon=weapon
    relaying=true
    local ok,err=xpcall(function()
        if IsValid(result.Entity) then
            result.Entity:DispatchTraceAttack(SP.CopyDamage(values),last,(last.HitPos-last.StartPos):GetNormalized())
        end
        local effect=EffectData()
        effect:SetOrigin(last.HitPos) effect:SetStart(last.StartPos) effect:SetNormal(last.HitNormal)
        effect:SetSurfaceProp(last.SurfaceProps or 0) effect:SetDamageType(DMG_CLUB)
        effect:SetHitBox(last.HitBoxBone or last.HitBox or 0)
        -- IsValid(worldspawn) is false. Reset the retained effect entity for it.
        if last.HitWorld then effect:SetEntIndex(0)
        elseif IsValid(last.Entity) then effect:SetEntity(last.Entity) end
        util.Effect("Impact",effect,true,true)
    end,debug.traceback)
    relaying=false
    if not ok then ErrorNoHalt("[Seamless Portals] Melee continuation: "..tostring(err).."\n") end
    return ok
end
