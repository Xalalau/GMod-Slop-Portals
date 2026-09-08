-- One geometry contract for visual aperture, traces and transport preflight.
local SP = SeamlessPortals
function SP.ApertureVertices(portal)
    local size, sides = portal:GetSize(), portal:GetSides()
    if not SP.ValidateSize(size) or not SP.ValidateSides(sides) then return {} end
    local result, offset = {}, math.rad(sides * 90 + (sides % 4 ~= 0 and 0 or 45))
    for i = 1, sides do
        local angle = math.rad(i * 360 / sides) + offset
        result[i] = Vector(math.sin(angle) * size.x / math.sqrt(2), math.cos(angle) * size.y / math.sqrt(2), 0)
    end
    return result -- clockwise, viewed from the portal front
end
local function edge_distance(a, b, p)
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
end
function SP.InApertureLocal(portal, p, margin)
    local vertices = SP.ApertureVertices(portal)
    if #vertices < 3 then return false end
    for i, a in ipairs(vertices) do
        local b = vertices[i % #vertices + 1]
        if edge_distance(a, b, p) > -(margin or 0) * (b-a):Length() + 1e-5 then return false end
    end
    return true
end
function SP.InAperture(portal, world, margin)
    return SP.InApertureLocal(portal, portal:WorldToLocal(world), margin)
end
function SP.ClosestAperturePoint(portal, world)
    local p = portal:WorldToLocal(world)
    p.z = 0
    if SP.InApertureLocal(portal, p) then return portal:LocalToWorld(p) end
    local best, distance = nil, math.huge
    local vertices = SP.ApertureVertices(portal)
    for i, a in ipairs(vertices) do
        local ab = vertices[i % #vertices + 1] - a
        local q = a + ab * math.Clamp((p-a):Dot(ab) / ab:LengthSqr(), 0, 1)
        local d = q:DistToSqr(p)
        if d < distance then best, distance = q, d end
    end
    return portal:LocalToWorld(best or vector_origin)
end
-- Disjoint convex pieces of the bounding rectangle outside the aperture.
-- Splitting the remaining inside polygon at each edge avoids overlapping fans.
function SP.ApertureBorderPieces(portal)
    local lo, hi = SP.GetApertureBounds(portal:GetSize(), portal:GetSides())
    if not lo then return {} end
    local remaining = {Vector(lo.x,lo.y,0), Vector(lo.x,hi.y,0), Vector(hi.x,hi.y,0), Vector(hi.x,lo.y,0)}
    local pieces, aperture = {}, SP.ApertureVertices(portal)
    for i, a in ipairs(aperture) do
        local b, inside, outside = aperture[i % #aperture + 1], {}, {}
        for j, p in ipairs(remaining) do
            local q = remaining[j % #remaining + 1]
            local dp, dq = edge_distance(a,b,p), edge_distance(a,b,q)
            -- Boundary vertices belong to both closed half-planes. Omitting
            -- them from the outside polygon loses triangle corners at tangencies.
            if dp <= 1e-7 then inside[#inside+1] = p end
            if dp >= -1e-7 then outside[#outside+1] = p end
            if (dp < 0 and dq > 0) or (dp > 0 and dq < 0) then
                local intersection = p + (q-p) * (dp / (dp-dq))
                inside[#inside+1], outside[#outside+1] = intersection, intersection
            end
        end
        if #outside >= 3 then pieces[#pieces+1] = outside end
        remaining = inside
        if #remaining == 0 then break end
    end
    return pieces
end
function SP.FiniteVector(v)
    return isvector(v) and SP.IsFinite(v.x) and SP.IsFinite(v.y) and SP.IsFinite(v.z)
end
