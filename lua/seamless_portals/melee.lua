-- Native HL2 melee bypasses util.TraceLine. Continue only its portal impact;
-- hitscan retains its own pellet callback and spread/damage accounting.
if not SERVER then return end
local SP=SeamlessPortals
local ranges={weapon_crowbar=75,weapon_stunstick=75}
local relaying=false
function SP.RelayPortalMelee(portal,info,direction,trace)
    if relaying or not info:IsDamageType(DMG_CLUB) then return false end
    local enabled=GetConVar("seamless_portals_damage")
    if enabled and not enabled:GetBool() then return false end
    local attacker=info:GetAttacker()
    if not IsValid(attacker) or not attacker:IsPlayer() then return false end
    local weapon=attacker:GetActiveWeapon()
    local range=IsValid(weapon) and ranges[weapon:GetClass()]
    if not range then return false end
    local start=attacker:GetShootPos()
    direction=direction:GetNormalized()
    if not SP.CanCrossTrace(trace,start,direction,"damage") then return false end
    local result=SP.TracePortalLine({start=start,endpos=start+direction*range,
        filter=attacker,mask=MASK_SHOT_HULL,SeamlessFeature="damage"})
    if not result.SeamlessSegments or not result.Hit or SP.IsPortal(result.Entity)
        or result.StartSolid or result.AllSolid then return false end
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
        effect:SetHitBox(last.HitBox or 0)
        if IsValid(last.Entity) then effect:SetEntity(last.Entity) end
        util.Effect("Impact",effect,true,true)
    end,debug.traceback)
    relaying=false
    if not ok then ErrorNoHalt("[Seamless Portals] Melee continuation: "..tostring(err).."\n") end
    return ok
end
