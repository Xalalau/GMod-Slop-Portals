-- F00: Shared front-plane geometry. Never infer a crossing from entity origin
-- membership in a thin box, or from a portal's decorative backface.
local SP = SeamlessPortals
function SP.PlaneDistance(portal, point)
    return (point - portal:GetPos()):Dot(portal:GetUp())
end
function SP.PlaneCrossing(portal, start, delta, margin, leading_radius)
    if not SP.IsPortal(portal) or not SP.FiniteVector(start) or not SP.FiniteVector(delta) then return end
    local depth = SP.PlaneDistance(portal, start)
    local approach = delta:Dot(portal:GetUp())
    local radius = math.max(leading_radius or 0, 0)
    if approach >= -1e-7 or depth < -0.1 or depth + approach > radius then return end
    local fraction = math.Clamp((radius - depth) / approach, 0, 1)
    local center = start + delta * fraction
    local aperture = center - portal:GetUp() * SP.PlaneDistance(portal, center)
    if not SP.InAperture(portal, aperture, margin or 0) then return end
    local exit = portal:GetExitPortal()
    if not SP.IsUsableLink(portal, exit) then return end
    local mapped = SP.TransformPortal(portal, exit, aperture)
    if not SP.InAperture(exit, mapped, margin or 0) then return end
    return {entry=portal, exit=exit, fraction=fraction, point=aperture, center=center, mapped=mapped}
end
function SP.FirstCrossing(start, delta, feature, margin, radius, excluded)
    local best
    for _, portal in ipairs(SP.Portals) do
        local exit = SP.IsPortal(portal) and portal:GetExitPortal()
        if portal ~= excluded and SP.IsUsableLink(portal, exit)
            and (not feature or SP.LinkAllows(portal, exit, feature)) then
            local hit = SP.PlaneCrossing(portal, start, delta, margin, radius)
            if hit and (not best or hit.fraction < best.fraction
                or (hit.fraction == best.fraction and portal:EntIndex() < best.entry:EntIndex())) then best = hit end
        end
    end
    return best
end
function SP.EntityCorners(ent, position, angle)
    local lo, hi, points = ent:OBBMins(), ent:OBBMaxs(), {}
    for x=0,1 do for y=0,1 do for z=0,1 do
        local p = Vector(x==0 and lo.x or hi.x, y==0 and lo.y or hi.y, z==0 and lo.z or hi.z)
        if position then p = LocalToWorld(p, angle_zero, position, angle or ent:GetAngles())
        else p = ent:LocalToWorld(p) end
        points[#points+1] = p
    end end end
    return points
end
function SP.PortalOBB(portal, ent, position, angle)
    local points = SP.EntityCorners(ent, position, angle)
    local local_points, lo, hi = {}, Vector(math.huge,math.huge,math.huge), Vector(-math.huge,-math.huge,-math.huge)
    for i, point in ipairs(points) do
        local p = portal:WorldToLocal(point)
        local_points[i] = p
        for axis=1,3 do lo[axis]=math.min(lo[axis],p[axis]) hi[axis]=math.max(hi[axis],p[axis]) end
    end
    local vertices = SP.ApertureVertices(portal)
    local aperture_lo, aperture_hi = SP.GetApertureBounds(portal:GetSize(),portal:GetSides())
    if not aperture_lo then return {overlap=false, fits=false, lo=lo, hi=hi, points=points} end
    local overlap = hi.x >= aperture_lo.x and lo.x <= aperture_hi.x and hi.y >= aperture_lo.y and lo.y <= aperture_hi.y
    local fits = true
    for i,a in ipairs(vertices) do
        local b=vertices[i % #vertices+1]
        local minimum,maximum=math.huge,-math.huge
        for _,p in ipairs(local_points) do
            local d=(b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x)
            minimum,maximum=math.min(minimum,d),math.max(maximum,d)
        end
        if minimum>1e-5 then overlap=false end
        if maximum>1e-5 then fits=false end
    end
    return {overlap=overlap, fits=fits, lo=lo, hi=hi, points=points,
        straddling=lo.z<=0 and hi.z>=0, fully_front=lo.z>0.1, fully_back=hi.z< -0.1}
end
-- A straight ray unfolded through one aperture. Each physical segment receives
-- its own visibility test; a nearby wall does not become transparent globally.
function SP.PortalSight(entry, exit, source, target, source_entity, target_entity)
    if not SP.IsUsableLink(entry,exit) or SP.PlaneDistance(entry,source)<0
        or SP.PlaneDistance(exit,target)<0 then return end
    local virtual = SP.TransformPortal(exit,entry,target)
    local crossing = SP.PlaneCrossing(entry,source,virtual-source)
    if not crossing then return end
    local raw = SP.RawTraceLine or SP.TraceLine or util.TraceLine
    local first = raw({start=source,endpos=crossing.point+entry:GetUp()*0.05,
        filter=function(ent) return ent~=source_entity and ent~=entry and ent~=target_entity end,
        mask=MASK_SOLID,SeamlessIgnore=true})
    if first.StartSolid or first.AllSolid or (first.Hit and first.Fraction<0.999) then return end
    local from = crossing.mapped + exit:GetUp()*0.05
    local last = raw({start=from,endpos=target,
        filter=function(ent) return ent~=target_entity and ent~=exit and ent~=source_entity end,
        mask=MASK_SOLID,SeamlessIgnore=true})
    if last.StartSolid or last.AllSolid or (last.Hit and last.Fraction<0.999) then return end
    crossing.virtual=virtual
    crossing.distance=source:Distance(crossing.point)+from:Distance(target)
    return crossing
end
function SP.CopyDamage(info)
    local out = DamageInfo()
    for _,name in ipairs({"Damage","BaseDamage","MaxDamage","DamageBonus","DamageCustom","DamageType",
        "Attacker","Inflictor","AmmoType","ReportedPosition","DamagePosition","DamageForce"}) do
        local get,set=info["Get"..name],out["Set"..name]
        if get and set then set(out,get(info)) end
    end
    return out
end
SP.FieldCounters = SP.FieldCounters or {}
function SP.CountField(name, amount)
    SP.FieldCounters[name]=(SP.FieldCounters[name] or 0)+(amount or 1)
end
