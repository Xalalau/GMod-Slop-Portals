SeamlessPortals = SeamlessPortals or {}
SeamlessPortals.Portals = SeamlessPortals.Portals or {}
local SP = SeamlessPortals
SP.Version = "2026.09.08-field-rc3-preview"
SP.AppliedProposalCount = 56
SP.CustomProposalCount = 15
SP.PatchSeriesCount = 94
SP.FieldFixProposalCount = 11
SP.FieldPackagingPatchCount = 1
SP.BuildStatus = "PREVIEW_INCOMPLETE"
SP.Limits = {MinSize = 1, MaxSize = 1000, MinSides = 3, MaxSides = 100}
function SP.IsFinite(value)
    return isnumber(value) and value == value and value > -math.huge and value < math.huge
end
function SP.ValidateSize(size)
    if not isvector(size) then return false end
    for i = 1, 3 do
        if not SP.IsFinite(size[i]) or size[i] < SP.Limits.MinSize or size[i] > SP.Limits.MaxSize then
            return false
        end
    end
    return true
end
function SP.ValidateSides(sides)
    return SP.IsFinite(sides) and sides == math.floor(sides)
        and sides >= SP.Limits.MinSides and sides <= SP.Limits.MaxSides
end
-- Remove() is deferred by the engine. Marked entities cannot accept new work.
function SP.IsLiveEntity(ent)
    return IsValid(ent) and not (ent.IsMarkedForDeletion and ent:IsMarkedForDeletion())
end
function SP.IsPortal(ent)
    return SP.IsLiveEntity(ent) and ent:GetClass() == "seamless_portal"
end

function SP.CaptureGeometry(portal)
    local exit = portal:GetExitPortal()
    if not SP.IsPortal(exit) then return nil end
    local values = {portal, exit}
    for _, ent in ipairs({portal, exit}) do
        local p, a, s = ent:GetPos(), ent:GetAngles(), ent:GetSize()
        for i = 1, 3 do values[#values + 1] = p[i] end
        for i = 1, 3 do values[#values + 1] = a[i] end
        for i = 1, 3 do values[#values + 1] = s[i] end
        values[#values + 1] = ent:GetSides()
    end
    return values
end
function SP.SameGeometry(a, b)
    if not a or not b or #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- Physical cutouts use the same convex polygon as rendering (C02).
function SP.SupportsPropTraversal(entry, exit)
    return SP.IsPortal(entry) and SP.IsPortal(exit) and entry ~= exit
        and SP.ValidateSides(entry:GetSides()) and SP.ValidateSides(exit:GetSides())
        and (not SP.IsUsableLink or SP.IsUsableLink(entry, exit))
        and (not SP.LinkAllows or SP.LinkAllows(entry, exit, "props"))
end
function SP.GetApertureBounds(size, sides)
    if not SP.ValidateSize(size) or not SP.ValidateSides(sides) then return nil end
    local lo, hi = Vector(math.huge, math.huge, -size[3]), Vector(-math.huge, -math.huge, 0)
    local offset = math.rad(sides * 90 + (sides % 4 ~= 0 and 0 or 45))
    for side = 1, sides do
        local angle = math.rad(side * 360 / sides) + offset
        local x, y = math.sin(angle) * size[1] / math.sqrt(2), math.cos(angle) * size[2] / math.sqrt(2)
        lo[1], lo[2] = math.min(lo[1], x), math.min(lo[2], y)
        hi[1], hi[2] = math.max(hi[1], x), math.max(hi[2], y)
    end
    return lo, hi
end

function SP.ComposeTraceFilter(original, whitelist, excluded)
    return function(ent)
        if ent == excluded then return false end
        if isfunction(original) then return original(ent) end
        local matched = false
        if IsEntity(original) then
            matched = ent == original
        elseif isstring(original) then
            matched = ent:GetClass() == original
        elseif istable(original) then
            for _, value in pairs(original) do
                if ent == value or (isstring(value) and ent:GetClass() == value) then matched = true break end
            end
            if whitelist then return matched end
        end
        return not matched
    end
end

function SP.AspectCompatibleSize(a, b)
    if not SP.ValidateSize(a) or not SP.ValidateSize(b) then return false end
    local ax, bx = a[2] / a[1], b[2] / b[1]
    return math.abs(ax - bx) <= 0.0001 * math.max(ax, bx)
end
function SP.IsUsableLink(entry, exit)
    return SP.IsPortal(entry) and SP.IsPortal(exit)
        and not entry.SEAMLESS_PORTALS_GEOMETRY_FAILED and not exit.SEAMLESS_PORTALS_GEOMETRY_FAILED
        and entry.GetSize
        and SP.AspectCompatibleSize(entry:GetSize(), exit:GetSize())
end

-- Server Lua transaction; network properties still arrive under engine replication rules.
function SP.ConfigurePair(a, config_a, b, config_b)
    if CLIENT or not SP.IsPortal(a) or not SP.IsPortal(b) or a == b then return false end
    if a:GetExitPortal() ~= b or b:GetExitPortal() ~= a then return false end
    if not istable(config_a) or not istable(config_b) then return false end
    for _, config in ipairs({config_a, config_b}) do
        if not istable(config) or not SP.ValidateSize(config.size) or not SP.ValidateSides(config.sides)
            or not isbool(config.disable_backface) then return false end
    end
    if not SP.AspectCompatibleSize(config_a.size, config_b.size) then return false end
    local old_a = {a:GetSize(), a:GetSides(), a:GetDisableBackface()}
    local old_b = {b:GetSize(), b:GetSides(), b:GetDisableBackface()}
    a.SEAMLESS_PORTALS_CONFIGURING_PAIR, b.SEAMLESS_PORTALS_CONFIGURING_PAIR = true, true
    local ok, err = xpcall(function()
        assert(a:Configure(config_a.size, config_a.sides, config_a.disable_backface))
        assert(b:Configure(config_b.size, config_b.sides, config_b.disable_backface))
    end, debug.traceback)
    if not ok then
        pcall(function() a:Configure(unpack(old_a)) end)
        pcall(function() b:Configure(unpack(old_b)) end)
    end
    a.SEAMLESS_PORTALS_CONFIGURING_PAIR, b.SEAMLESS_PORTALS_CONFIGURING_PAIR = nil, nil
    if not ok then ErrorNoHalt("[Seamless Portals] ConfigurePair failed: " .. tostring(err) .. "\n") end
    return ok
end

-- Angle:Right is negative local Y in Source's basis convention.
function SP.TransformDirection(entry, exit, direction, scale)
    if not SP.IsUsableLink(entry, exit) then return nil end
    local up = entry:GetUp()
    if entry == exit then return direction - up * (2 * direction:Dot(up)) end
    local x = direction:Dot(entry:GetForward())
    local y = -direction:Dot(entry:GetRight())
    local z = direction:Dot(up)
    local result = exit:GetForward() * x + exit:GetRight() * y - exit:GetUp() * z
    if scale ~= false then result:Mul(exit:GetSize()[1] / entry:GetSize()[1]) end
    return result
end

SP.LinkedRegistryDirty = true
function SP.RefreshLinkedRegistry()
    local count = 0
    for _, portal in ipairs(SP.Portals) do
        if SP.IsPortal(portal) and SP.IsUsableLink(portal, portal:GetExitPortal()) then count = count + 1 end
    end
    SP.LinkedPortalCount, SP.LinkedRegistryDirty = count, false
end
function SP.HasTraversablePortals()
    if SP.LinkedRegistryDirty then SP.RefreshLinkedRegistry() end
    return (SP.LinkedPortalCount or 0) > 0
end
hook.Add("Think", "seamless_portals_link_registry", SP.RefreshLinkedRegistry)

if SERVER then AddCSLuaFile("seamless_portals/client_config.lua") else include("seamless_portals/client_config.lua") end

AddCSLuaFile("seamless_portals/features.lua")
include("seamless_portals/features.lua")

if SERVER then AddCSLuaFile("seamless_portals/aperture.lua") end
include("seamless_portals/aperture.lua")
AddCSLuaFile("seamless_portals/crossing.lua")
include("seamless_portals/crossing.lua")
