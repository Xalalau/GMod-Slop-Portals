-- F08: Source FireBullets excludes the firing entity from its own trace.
-- A continuation originates in another coordinate frame; its original attacker
-- must be hittable there. Keep attribution, but use an inert firing identity.
local SP=SeamlessPortals
local pool={}
function SP.FirePortalContinuation(shooter,data)
    if not SERVER then shooter:FireBullets(data) return true end
    local slot=math.Clamp(SP.BulletContinuationDepth or 1,1,8)
    local emitter=pool[slot]
    if not IsValid(emitter) then
        emitter=ents.Create("info_target")
        if not IsValid(emitter) then SP.CountField("bullet_emitter_failed") return false end
        emitter.SEAMLESS_PORTALS_BULLET_EMITTER=true
        emitter:SetPos(data.Src) emitter:SetNoDraw(true)
        emitter:Spawn() emitter:SetSolid(SOLID_NONE) emitter:SetMoveType(MOVETYPE_NONE)
        -- Deliberately no SetOwner(attacker): owner filtering can reintroduce
        -- the exact self-immunity this emitter exists to remove.
        pool[slot]=emitter
    end
    emitter:SetPos(data.Src)
    emitter:FireBullets(data)
    SP.CountField("neutral_bullet_continuations")
    return true
end
local function cleanup()
    for slot,ent in pairs(pool) do if IsValid(ent) then ent:Remove() end pool[slot]=nil end
end
hook.Add("PostCleanupMap","seamless_portals_bullet_emitters",cleanup)
hook.Add("ShutDown","seamless_portals_bullet_emitters",cleanup)
