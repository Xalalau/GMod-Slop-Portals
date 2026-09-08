ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.Category     = "Seamless Portals"
ENT.PrintName    = "Seamless Portal"
ENT.Author       = "Mee"
ENT.Purpose      = "Seamlessly connects two locations"
ENT.Instructions = ""
ENT.Spawnable    = true
ENT.RenderGroup  = RENDERGROUP_OPAQUE

AddCSLuaFile("seamless_portals/core.lua")
include("seamless_portals/core.lua")

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "ExitPortal")
	self:NetworkVar("Vector", 0, "SizeInternal")
	self:NetworkVar("Vector", 1, "Size")
	self:NetworkVar("Bool", 0, "DisableBackface")
	self:NetworkVar("Bool", 1, "RemoveExitInternal")
	self:NetworkVar("Int", 0, "Sides")
	self:NetworkVar("Int", 1, "ConfigurationRevision")

	-- Wrap generated setters: reject invalid requests without publishing them.
    local raw_size, raw_sides = self.SetSize, self.SetSides
    self.SetSize = function(ent, value)
        if not SeamlessPortals.ValidateSize(value) then return false end
        local exit = ent:GetExitPortal()
        if not ent.SEAMLESS_PORTALS_CONFIGURING_PAIR and SeamlessPortals.IsPortal(exit)
            and not SeamlessPortals.AspectCompatibleSize(value, exit:GetSize()) then return false end
        raw_size(ent, Vector(value))
        SeamlessPortals.LinkedRegistryDirty = true
        return true
    end
    self.SetSides = function(ent, value)
        if not SeamlessPortals.ValidateSides(value) then return false end
        raw_sides(ent, value)
        return true
    end

	self.SEAMLESS_PORTALS_GEOMETRY_DIRTY = true
	local function dirty(ent, _, old, new)
		if old ~= new then ent.SEAMLESS_PORTALS_GEOMETRY_DIRTY = true end
	end
	self:NetworkVarNotify("Size", dirty)
	self:NetworkVarNotify("Sides", dirty)
	self:NetworkVarNotify("ExitPortal", function() SeamlessPortals.LinkedRegistryDirty = true end)
end

-- So the size is in source units (remember we are using sine/cosine)
local size_mult = Vector(math.sqrt(2) / 2, math.sqrt(2) / 2, 1)

-- Scale the phys mesh
function ENT:UpdatePhysmesh(size, sides)
	size = size or self:GetSize()
	sides = sides or self:GetSides()
	if not SeamlessPortals.ValidateSize(size) or not SeamlessPortals.ValidateSides(sides) then return false end
	size = size * size_mult

	local finalMesh = {}
	local ang_mul = 360 / sides
	local ang_pick = sides % 4 != 0 and 0 or 45
	local rad_offset = math.rad(sides * 90 + ang_pick)
	for side = 1, sides do
		local sidea = math.rad(side * ang_mul) + rad_offset
		local sidex, sidey = math.sin(sidea), math.cos(sidea)
		local side1 = Vector(sidex, sidey, -1) side1:Mul(size)
		local side2 = Vector(sidex, sidey,  0) side2:Mul(size)
		table.insert(finalMesh, side1)
		table.insert(finalMesh, side2)
	end
	self:SetSolid(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	if !self:PhysicsInitConvex(finalMesh) then
		print("[Seamless Portals]: WARNING! TRIED TO CREATE PORTAL WITH INVALID SIZE")
		return
	end
	self:EnableCustomCollisions(true)

	if CLIENT then
		--self:MakePhysicsObjectAShadow(false, false)
		local mins, maxs = SeamlessPortals.GetApertureBounds(self:GetSize(), sides)
		if mins then self:SetRenderBounds(mins, maxs) end
	end

	local phys = self:GetPhysicsObject()
	if not IsValid(phys) then return false end
	phys:EnableMotion(false)
	phys:SetMaterial("glass")
	phys:SetMass(250)
	return true
end

SeamlessPortals.Portals = SeamlessPortals.Portals or {}
SeamlessPortals.TransformPortal = function(a, b, pos, ang)
	if !IsValid(a) or !IsValid(b) then return Vector(), Angle() end
	local editedPos = nil
	local editedAng = nil

	if pos then
		editedPos = a:WorldToLocal(pos) * (b:GetSize()[1] / a:GetSize()[1])
		editedPos = b:LocalToWorld(Vector(editedPos[1], -editedPos[2], -editedPos[3]))
		--editedPos = editedPos + b:GetUp() * 0.01 -- So you don't become trapped
	end

	if ang then
		local localAng = a:WorldToLocalAngles(ang)
		editedAng = b:LocalToWorldAngles(Angle(-localAng[1], -localAng[2], localAng[3] + 180))
	end

	-- Mirror portal
	if a == b then
		if pos then
			editedPos = a:LocalToWorld(a:WorldToLocal(pos) * Vector(1, 1, -1))
		end

		if ang then
			local localAng = a:WorldToLocalAngles(ang)
			editedAng = a:LocalToWorldAngles(Angle(-localAng[1], localAng[2], -localAng[3] + 180))
		end
	end

	return editedPos or Vector(), editedAng or Angle()
end

-- Only render the portals that are in the frustum, or should be rendered
SeamlessPortals.ShouldRender = function(portal, eyePos, eyeAngle, distance)
  if portal:IsDormant() or not SeamlessPortals.IsUsableLink(portal, portal:GetExitPortal()) then return false end
	local portalPos, portalUp, exitSize = portal:GetPos(), portal:GetUp(), portal:GetSize()
	local max, eye = math.max(exitSize[1], exitSize[2]), (eyePos - portalPos)
	-- (eyePos - portalPos):Dot(portalUp) > (-10 * max) -- true if behind the portal, false otherwise
	-- eyePos:DistToSqr(portalPos) < distance^2 * max -- true if close enough
	-- (eyePos - portalPos):Dot(eyeAngle:Forward()) < 50 * max -- true if looking at the portal, false otherwise
	if(eye:Dot(portalUp) <= -exitSize[3]) then return false end -- First condition is not met so bail put
	if(eye:LengthSqr() >= distance^2 * max) then return false end -- Second condition is not met so bail put
	return (eye:Dot(eyeAngle:Forward()) < max) -- Decides the return value of the function
end

-- Notifications may precede assignment or be absent during initial replication.
function ENT:ReconcileGeometry()
    local size, sides = self:GetSize(), self:GetSides()
    if not SeamlessPortals.ValidateSize(size) or not SeamlessPortals.ValidateSides(sides) then
        self.SEAMLESS_PORTALS_GEOMETRY_FAILED = true
        return false
    end
    if self.SEAMLESS_PORTALS_GEOMETRY_DIRTY or self.SEAMLESS_PORTALS_BUILT_SIZE ~= size
        or self.SEAMLESS_PORTALS_BUILT_SIDES ~= sides or not IsValid(self:GetPhysicsObject()) then
        if not self:UpdatePhysmesh(size, sides) then
            self.SEAMLESS_PORTALS_GEOMETRY_FAILED = true
            return false
        end
        self.SEAMLESS_PORTALS_BUILT_SIZE = Vector(size)
        self.SEAMLESS_PORTALS_BUILT_SIDES = sides
        self.SEAMLESS_PORTALS_BUILT_REVISION = self:GetConfigurationRevision()
        self.SEAMLESS_PORTALS_GEOMETRY_DIRTY = false
    end
    self.SEAMLESS_PORTALS_GEOMETRY_FAILED = false
    return true
end

function ENT:GetRemoveExit()
    return self:GetRemoveExitInternal()
end

function ENT:Configure(size, sides, disable_backface)
    if CLIENT then return false end
    if not SeamlessPortals.ValidateSize(size) or not SeamlessPortals.ValidateSides(sides)
        or not isbool(disable_backface) then return false end
    local exit = self:GetExitPortal()
    if not self.SEAMLESS_PORTALS_CONFIGURING_PAIR and SeamlessPortals.IsPortal(exit)
        and not SeamlessPortals.AspectCompatibleSize(size, exit:GetSize()) then return false end
    if not self:SetSize(size) or not self:SetSides(sides) then return false end
    self:SetDisableBackface(disable_backface)
    self:SetConfigurationRevision((self:GetConfigurationRevision() + 1) % 2147483647)
    self.SEAMLESS_PORTALS_GEOMETRY_DIRTY = true
    self:NextThink(CurTime())
    return true
end

-- Custom-compatible public accessors; the NW keys remain compatible with map code.
function ENT:GetDisablePropTeleport() return not SeamlessPortals.FeatureEnabled(self, "props") end
function ENT:SetDisablePropTeleport(value) return SeamlessPortals.SetFeature(self, "props", not value) end
function ENT:GetEnableFunneling() return SeamlessPortals.FeatureEnabled(self, "funnel") end
function ENT:SetEnableFunneling(value) return SeamlessPortals.SetFeature(self, "funnel", value) end
function ENT:AddPlyUsageCallback(id, callback)
    if not SERVER or not isstring(id) or not isfunction(callback) then return false end
    self.SEAMLESS_PORTALS_USAGE_CALLBACKS = self.SEAMLESS_PORTALS_USAGE_CALLBACKS or {}
    self.SEAMLESS_PORTALS_USAGE_CALLBACKS[id] = callback
    return true
end
function ENT:RemovePlyUsageCallback(id)
    if self.SEAMLESS_PORTALS_USAGE_CALLBACKS then self.SEAMLESS_PORTALS_USAGE_CALLBACKS[id] = nil end
end
function ENT:RunPlyUsageCallbacks(ply, phase, other)
    local snapshot = {}
    for id, callback in pairs(self.SEAMLESS_PORTALS_USAGE_CALLBACKS or {}) do
        snapshot[#snapshot + 1] = {id, callback}
    end
    table.sort(snapshot, function(a, b) return a[1] < b[1] end)
    for _, item in ipairs(snapshot) do
        if not IsValid(self) or not IsValid(ply) then break end
        local ok, err = xpcall(function() item[2](ply, self, phase, other) end, debug.traceback)
        if not ok then ErrorNoHalt("[Seamless Portals] callback " .. item[1] .. ": " .. tostring(err) .. "\n") end
    end
end
