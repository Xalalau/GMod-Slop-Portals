-- Custom funnel behavior, integrated into the existing predicted Move hook.
-- 0.05 / 0.01 are normalized to a 66 Hz reference, not applied once per frame.
local SP=SeamlessPortals
function SP.FunnelAlpha(dt,lateral)
    if not SP.IsFinite(dt) or dt<=0 then return 0 end
    local rate=lateral and 0.01 or 0.05
    return 1-(1-rate)^(math.min(dt,0.1)*66)
end
function SP.ApplyFunneling(ply,mv,dt)
    if not IsValid(ply) or not ply:Alive() or ply:InVehicle() or ply:GetMoveType()~=MOVETYPE_WALK then return false end
    local velocity=mv:GetVelocity()
    local speed=velocity:Length()
    if speed<=math.max(ply:GetRunSpeed(),1) then return false end
    local direction=velocity/speed
    local position=mv:GetOrigin()+ply:GetCurrentViewOffset()
    local best,best_distance
    for _,entry in ipairs(SP.Portals) do
        local exit=SP.IsPortal(entry) and entry:GetExitPortal()
        if SP.IsPortal(exit) and SP.FeatureEnabled(entry,"funnel") and SP.LinkAllows(entry,exit,"players") then
            local delta=entry:GetPos()-position
            local distance=delta:LengthSqr()
            if distance>1 and distance<2000*2000 and delta:Dot(entry:GetUp())<0
                and direction:Dot(delta:GetNormalized())>=0.8660254038
                and direction:Dot(-entry:GetUp())>=0.7071067812 then
                if not best or distance<best_distance or (distance==best_distance and entry:EntIndex()<best:EntIndex()) then
                    best,best_distance=entry,distance
                end
            end
        end
    end
    if not best then return false end
    local target=(best:GetPos()-(position-velocity*0.1)):GetNormalized()
    local alpha=SP.FunnelAlpha(dt,math.abs(mv:GetSideSpeed())>1)
    local blended=direction*(1-alpha)+target*alpha
    if blended:LengthSqr()<1e-8 then return false end
    mv:SetVelocity(blended:GetNormalized()*speed)
    return true
end
