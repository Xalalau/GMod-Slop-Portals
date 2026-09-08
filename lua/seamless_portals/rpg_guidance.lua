-- Steer the existing RPG along the unfolded aim path after it crosses.
-- Native weapon updates overwrite its dot; native target handles are read-only.
if not SERVER then return end
local SP=SeamlessPortals
SP.RPGGuidance=SP.RPGGuidance or setmetatable({},{__mode="k"})
local records=SP.RPGGuidance
-- Retire the old visual helper when this module is hotloaded.
for _,record in pairs(records) do
    SafeRemoveEntity(record.laser)
    record.laser=nil
end
SP.RPGLaserDots=SP.RPGLaserDots or setmetatable({},{__mode="k"})
local dots=SP.RPGLaserDots
local function register(ent)
    if IsValid(ent) and ent:GetClass()=="env_laserdot" then dots[ent]=true end
end
hook.Add("OnEntityCreated","seamless_portals_rpg_lasers",register)
for _,ent in ipairs(ents.FindByClass("env_laserdot")) do register(ent) end
function SP.GetRPGLaser(owner,weapon)
    local dot=weapon:GetInternalVariable("m_hLaserDot")
    if IsValid(dot) and dot:GetOwner()==owner then return dot end
    -- HL2MP's weapon does not expose this handle in its save table.
    for ent in pairs(dots) do
        if not IsValid(ent) then dots[ent]=nil
        elseif not ent.SEAMLESS_PORTALS_GUIDANCE_DOT
            and (ent:GetOwner()==owner or (ent.SEAMLESS_PORTALS_RPG_RECORD and ent.SEAMLESS_PORTALS_RPG_RECORD.owner==owner))
            and ent:GetInternalVariable("m_bIsOn")==true then return ent end
    end
end
function SP.ClearRPGGuidance(missile)
    local record=records[missile]
    if not record then return end
    local dot=record.dot
    if IsValid(dot) and dot.SEAMLESS_PORTALS_RPG_RECORD==record then
        if dot:GetOwner()==record.target or not IsValid(dot:GetOwner()) then
            dot:SetOwner(IsValid(record.owner) and record.owner or NULL)
        end
        dot:SetNoDraw(record.old_nodraw)
        dot:SetNWEntity("seamless_portals_rpg_owner",NULL)
        dot.SEAMLESS_PORTALS_RPG_RECORD=nil
    end
    records[missile]=nil
    SafeRemoveEntity(record.laser)
    SafeRemoveEntity(record.target)
end
hook.Add("SeamlessPortalsProjectileTransferred","seamless_portals_rpg_guidance",function(ent,entry,exit)
    if ent:GetClass()~="rpg_missile" then return end
    SP.ClearRPGGuidance(ent)
    records[ent]={entry=entry,exit=exit}
end)
function SP.UpdateRPGGuidance(missile,record)
    local owner=IsValid(missile) and missile:GetOwner()
    local damage=GetConVar("seamless_portals_damage")
    local projectiles=GetConVar("seamless_portals_projectiles")
    if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive()
        or (damage and not damage:GetBool()) or (projectiles and not projectiles:GetBool())
        or not SP.IsUsableLink(record.entry,record.exit)
        or record.entry:GetExitPortal()~=record.exit
        or not SP.LinkAllows(record.entry,record.exit,"damage") then
        SP.ClearRPGGuidance(missile) return false
    end
    local weapon=owner:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass()~="weapon_rpg" then
        SP.ClearRPGGuidance(missile) return false
    end
    local dot=SP.GetRPGLaser(owner,weapon)
    if not IsValid(dot) or dot:GetInternalVariable("m_bIsOn")==false then
        SP.ClearRPGGuidance(missile) return false
    end
    if dot.SEAMLESS_PORTALS_RPG_RECORD and dot.SEAMLESS_PORTALS_RPG_RECORD~=record then return false end
    local start=owner:GetShootPos()
    local trace=SP.TracePortalLine({start=start,endpos=start+owner:GetAimVector()*56756,
        filter={owner,weapon,missile},mask=bit.band(MASK_SHOT,bit.bnot(CONTENTS_WINDOW)),SeamlessFeature="damage"})
    local segment
    for i,part in ipairs(trace.SeamlessSegments or {}) do
        if part.Entity==record.entry and record.entry:GetExitPortal()==record.exit then
            segment=trace.SeamlessSegments[i+1]
        end
    end
    if not segment or segment.StartSolid or segment.AllSolid then
        -- Native weapon logic owns the dot as soon as the aim leaves this path.
        SP.ClearRPGGuidance(missile)
        records[missile]={entry=record.entry,exit=record.exit}
        return false
    end
    if not IsValid(record.target) then
        local target=ents.Create("info_target")
        if not IsValid(target) then return false end
        target:SetNoDraw(true) target:SetNotSolid(true) target:Spawn()
        target.SEAMLESS_PORTALS_AI_PROXY=true
        record.target=target
        missile:DeleteOnRemove(target)
    end
    if dot.SEAMLESS_PORTALS_RPG_RECORD~=record then
        record.old_nodraw=dot:GetNoDraw()
        record.owner=owner
        dot.SEAMLESS_PORTALS_RPG_RECORD=record
    end
    record.dot=dot
    record.target:SetPos(segment.HitPos)
    -- The native dot stays under weapon control, but no longer competes for
    -- this player's missile. Restore its owner and visibility on every exit.
    -- Keep the native dot networked for the client aim renderer.
    dot:SetOwner(record.target) dot:SetNoDraw(record.old_nodraw)
    dot:SetNWEntity("seamless_portals_rpg_owner",owner)
    if record.steered_tick~=engine.TickCount() then
        local velocity=missile:GetVelocity()
        local speed=velocity:Length()
        if SP.FiniteVector(velocity) and speed>1 then
            local goal=SP.RPGGuidePoint(missile:GetPos(),segment)
            local direction=(goal-missile:GetPos()):GetNormalized()
            local fraction=1-math.pow(0.875,engine.TickInterval()*66)
            local steered=(velocity/speed*(1-fraction)+direction*fraction):GetNormalized()
            missile:SetLocalVelocity(steered*speed)
            missile:SetAngles(steered:Angle())
        end
        record.steered_tick=engine.TickCount()
    end
    SP.CountField("rpg_guidance_updates")
    return true
end
function SP.RPGGuidePoint(position,segment)
    if IsValid(segment.Entity) then return segment.HitPos end
    local delta=segment.HitPos-segment.StartPos
    local length=delta:Length()
    if length<1 then return segment.HitPos end
    if position:Distance(segment.StartPos)>=length and position:Distance(segment.HitPos)>512 then return segment.HitPos end
    local direction=delta/length
    local along=math.Clamp((position-segment.StartPos):Dot(direction),0,length)
    return segment.StartPos+direction*(along+256)
end
hook.Add("Tick","seamless_portals_rpg_guidance",function()
    for missile,record in pairs(records) do SP.UpdateRPGGuidance(missile,record) end
end)
hook.Add("PlayerPostThink","seamless_portals_rpg_guidance",function(ply)
    for missile,record in pairs(records) do
        if IsValid(missile) and missile:GetOwner()==ply then SP.UpdateRPGGuidance(missile,record) end
    end
end)
hook.Add("EntityRemoved","seamless_portals_rpg_guidance",function(ent)
    dots[ent]=nil
    SP.ClearRPGGuidance(ent)
    for missile,record in pairs(records) do
        if record.entry==ent or record.exit==ent or record.dot==ent then SP.ClearRPGGuidance(missile) end
    end
end)
local function cleanup()
    for missile in pairs(records) do SP.ClearRPGGuidance(missile) end
end
hook.Add("PostCleanupMap","seamless_portals_rpg_guidance",cleanup)
hook.Add("ShutDown","seamless_portals_rpg_guidance",cleanup)
