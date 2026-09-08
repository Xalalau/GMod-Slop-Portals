-- sv_init.lua
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("sh_init.lua")

include("sh_init.lua")

-- dupe/save support
local function set_dupe_link(_, ent, data)
	if CLIENT then return end

	ent.SEAMLESS_PORTALS_DUPE_LINK = table.Merge(ent.SEAMLESS_PORTALS_DUPE_LINK or {}, data, true)
	duplicator.StoreEntityModifier(ent, "seamless_portals_dupe_link", ent.SEAMLESS_PORTALS_DUPE_LINK)
end

duplicator.RegisterEntityModifier("seamless_portals_dupe_link", set_dupe_link)

function ENT:PostEntityPaste(_, _, created)
	local dupelink = self.SEAMLESS_PORTALS_DUPE_LINK
	if !dupelink then return end

	local portal_exit = created[dupelink.exit_id]

	if IsValid(portal_exit) then
		if dupelink.directed then self:SetDirectedExitPortal(portal_exit) else self:LinkPortal(portal_exit) end
	end

	if dupelink.exit_remove then
		self:SetRemoveExit(true)
	end
end


function ENT:DiscardTraversalState()
    local cutout = self.SEAMLESS_PORTALS_CUTOUT
    self.SEAMLESS_PORTALS_CUTOUT = nil
    -- Restore admitted props now, not in the deferred OnRemove callback.
    if IsValid(cutout) and cutout.Deactivate then cutout:Deactivate() end
    SafeRemoveEntity(cutout)
end

function ENT:UnlinkPortal()
    local exit = self:GetExitPortal()
    self:DiscardTraversalState()
    self:SetExitPortal(NULL)
    set_dupe_link(self:GetCreator(), self, {exit_id = -1, directed = false})
    if SeamlessPortals.IsPortal(exit) and exit ~= self and exit:GetExitPortal() == self then
        exit:DiscardTraversalState()
        exit:SetExitPortal(NULL)
        set_dupe_link(exit:GetCreator(), exit, {exit_id = -1, directed = false})
    end
    return true
end

function ENT:LinkPortal(exit)
    if not SeamlessPortals.IsUsableLink(self, exit) then return false end
    if self:GetExitPortal() == exit and exit:GetExitPortal() == self then return true end
    self:UnlinkPortal()
    if exit ~= self then exit:UnlinkPortal() end
    self:SetExitPortal(exit)
    set_dupe_link(self:GetCreator(), self, {exit_id = exit:EntIndex(), directed = false})
    if exit ~= self then
        exit:SetExitPortal(self)
        set_dupe_link(exit:GetCreator(), exit, {exit_id = self:EntIndex(), directed = false})
    end
    return true
end

function ENT:SetRemoveExit(bool)
	bool = bool and true or false

	self:SetRemoveExitInternal(bool)
	set_dupe_link(self:GetCreator(), self, {exit_remove = bool})
end



-- Hammer links intentionally remain directed; do not silently force reciprocity.
function ENT:SetDirectedExitPortal(exit)
    if not SeamlessPortals.IsUsableLink(self, exit) then return false end
    self:UnlinkPortal()
    self:SetExitPortal(exit)
    set_dupe_link(self:GetCreator(), self, {exit_id = exit:EntIndex(), directed = true})
    return true
end
function ENT:LinkNamedPortal(name)
    local targets = ents.FindByName(name)
    if #targets ~= 1 or not SeamlessPortals.IsPortal(targets[1]) then
        ErrorNoHalt("[Seamless Portals] Link target must uniquely name a portal: " .. tostring(name) .. "\n")
        return false
    end
    return self:SetDirectedExitPortal(targets[1])
end

local outputs = {
	["OnTeleportFrom"] = true,
	["OnTeleportTo"]   = true
}

function ENT:KeyValue(key, value)
	self.SEAMLESS_PORTALS_MAP_FORMAT = self.SEAMLESS_PORTALS_MAP_FORMAT or 0

	local feature_keys = {disablePropTeleport = {"props", true}, disablePlayerTeleport = {"players", true},
        disableSoundTransfer = {"sound", true}, disableDamageTransfer = {"damage", true}, enableFunneling = {"funnel", false}}
    local feature = feature_keys[key]
    if feature then
        local enabled = value == "1" or value == "true"
        if feature[2] then enabled = not enabled end
        SeamlessPortals.SetFeature(self, feature[1], enabled)
    elseif key == "link" then
		timer.Simple(0, function()
            if IsValid(self) then self:LinkNamedPortal(value) end
        end)
	elseif key == "backface" then
		self:SetDisableBackface(value == "1")
	elseif key == "size" then
		local size = string.Split(value, " ")
		self:SetSize(Vector(size[2], size[1], size[3]))
	elseif key == "sides" then
		self:SetSides(tonumber(value) or 4)
	elseif key == "version" then
		self.SEAMLESS_PORTALS_MAP_FORMAT = tonumber(value) or 0
	elseif outputs[key] then
		self:StoreOutput(key, value)
	end
end

function ENT:AcceptInput(input, activator, caller, data)
	local inputs = {EnablePropTeleport = {"props", true}, DisablePropTeleport = {"props", false},
        EnableSoundTransfer = {"sound", true}, DisableSoundTransfer = {"sound", false},
        EnableDamageTransfer = {"damage", true}, DisableDamageTransfer = {"damage", false},
        EnableFunneling = {"funnel", true}, DisableFunneling = {"funnel", false},
        EnablePlayerTeleport = {"players", true}, DisablePlayerTeleport = {"players", false}}
    if inputs[input] then return SeamlessPortals.SetFeature(self, unpack(inputs[input])) end
    if input == "Link" then
		self:LinkNamedPortal(data)
	end
end

function ENT:Initialize()
	self:SetModel("models/hunter/plates/plate2x2.mdl")
	self:SetCollisionGroup(COLLISION_GROUP_WORLD) -- no collide
	self:DrawShadow(false)
    -- Witness native RadiusDamage without becoming a destructible portal.
    self:SetSaveValue("m_takedamage", DAMAGE_YES or 2)

	-- defaults and portal format conversion. welcome to tech debt hell
	local map_format = self.SEAMLESS_PORTALS_MAP_FORMAT
	if map_format then
		if map_format == 0 then
			self:SetSize(self:GetSize() * 0.999)
		end

		if map_format != 1 then
			self:SetAngles(self:GetAngles() + Angle(90, 0, 0))
		end
	end

	local sides = self:GetSides()
	if sides <= 0 then
		self:SetSides(4)
	end

	local size_internal = self:GetSizeInternal()
	if !size_internal:IsZero() then
		size_internal:Mul(Vector(2, 2, 1))
		self:SetSize(size_internal)
	end

	local size = self:GetSize()
	if size:IsZero() then
		self:SetSize(Vector(100, 100, 8))
	end

	-- Reject runtime edits; recover only unconfigured/legacy initial state here.
	if not SeamlessPortals.ValidateSize(self:GetSize()) then self:SetSize(Vector(100, 100, 8)) end
	if not SeamlessPortals.ValidateSides(self:GetSides()) then self:SetSides(4) end

	self.SEAMLESS_PORTALS_INITIALIZED = true
	if not self:ReconcileGeometry() then SafeRemoveEntity(self) return end

	table.insert(SeamlessPortals.Portals, self)
end


function ENT:OnRemove()
    local exit = self:GetExitPortal()
    local remove_exit = self:GetRemoveExit() and SeamlessPortals.IsPortal(exit) and exit ~= self
        and exit:GetExitPortal() == self
    self:UnlinkPortal()
    if remove_exit then SafeRemoveEntity(exit) end
    table.RemoveByValue(SeamlessPortals.Portals, self)
    SeamlessPortals.LinkedRegistryDirty = true
end

function ENT:SpawnFunction(ply, tr)
	local portal1 = ents.Create("seamless_portal")
	if not SeamlessPortals.IsLiveEntity(portal1) then return end

	portal1:SetPos(tr.HitPos + tr.HitNormal * 160.1)
	portal1:SetAngles(tr.HitNormal:AngleEx(Vector(0, 0, -1)))
	portal1:SetCreator(ply)
	portal1:Spawn()

	local portal2 = ents.Create("seamless_portal")
	if not SeamlessPortals.IsLiveEntity(portal2) then SafeRemoveEntity(portal1) return end

	portal2:SetPos(tr.HitPos + tr.HitNormal * 50.1)
	portal2:SetAngles(tr.HitNormal:AngleEx(Vector(0, 0, -1)))
	portal2:SetCreator(ply)
	portal2:Spawn()

	if CPPI then portal2:CPPISetOwner(ply) end

	portal1:LinkPortal(portal2)
	portal2:LinkPortal(portal1)

	portal1:SetRemoveExit(true)
	portal2:SetRemoveExit(true)

	return portal1
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end


function ENT:UpdateCutout(recursive)
    local exit = self:GetExitPortal()
    -- Clone transfer assumes a reciprocal pair; directed map links still work
    -- for players, rendering and traces, but never borrow an unrelated cutout.
    if not SeamlessPortals.SupportsPropTraversal(self, exit) or exit:GetExitPortal() ~= self then
        self:DiscardTraversalState()
        return false
    end
    local snapshot = SeamlessPortals.CaptureGeometry(self)
    local old = self.SEAMLESS_PORTALS_CUTOUT
    if not SeamlessPortals.IsLiveEntity(old) or not old.SEAMLESS_PORTALS_READY
        or old.SEAMLESS_PORTALS_MESH_REVISION ~= SeamlessPortals.CutoutMeshRevision
        or not SeamlessPortals.SameGeometry(old.SEAMLESS_PORTALS_GEOMETRY, snapshot) then
        -- A stale shape is never retained as a collision-disabled crossing region.
        self:DiscardTraversalState()
        local cutout = ents.Create("seamless_portal_cutout")
        if not SeamlessPortals.IsLiveEntity(cutout) then return false end
        cutout:SetPortal(self)
        cutout:SetPos(self:GetPos())
        cutout:SetAngles(self:GetAngles())
        cutout:Spawn()
        if not SeamlessPortals.IsLiveEntity(cutout) then return false end
        cutout:GeneratePhysmesh(exit, self)
        cutout:GeneratePhysmesh(self)
        if not cutout:CreatePhysmesh() then SafeRemoveEntity(cutout) return false end
        cutout.SEAMLESS_PORTALS_GEOMETRY = snapshot
        cutout.SEAMLESS_PORTALS_READY = true
        self:DeleteOnRemove(cutout)
        self.SEAMLESS_PORTALS_CUTOUT = cutout
    end
    if not recursive then
        local ready = exit:UpdateCutout(true)
        if not ready then self:DiscardTraversalState() end
        return ready
    end
    return true
end

-- Prop and object teleporting
function ENT:Think()
	if not self:ReconcileGeometry() then self:DiscardTraversalState() return end
	local exit_portal = self:GetExitPortal()
	if !IsValid(exit_portal) or self == exit_portal then
		self:DiscardTraversalState()
		return
	end

	if not self:UpdateCutout() then return end
	local ready_cutout = self.SEAMLESS_PORTALS_CUTOUT
	if not IsValid(ready_cutout) then return end
	if next(ready_cutout.ENTITIES) == nil then
		-- Keep cutout admission at tick frequency; avoid all clone/transfer setup when idle.
		self:NextThink(CurTime())
		return true
	end

	local exit_pos = exit_portal:GetPos()
	local self_pos = self:GetPos()
	local self_up = self:GetUp()
	local cutout = self.SEAMLESS_PORTALS_CUTOUT
	local exit_cutout = exit_portal.SEAMLESS_PORTALS_CUTOUT
	local exit_cutout_valid = IsValid(exit_cutout)
	for ent, _ in pairs(cutout.ENTITIES) do
		if !IsValid(ent) then continue end

		local phys = ent:GetPhysicsObject()
		if !IsValid(phys) then continue end

		local clone = ent.SEAMLESS_PORTALS_CLONE
		if not SeamlessPortals.IsLiveEntity(clone) then
			clone = ents.Create("seamless_portal_clone")
			if not SeamlessPortals.IsLiveEntity(clone) then cutout:RemoveEntity(ent) continue end
			clone:SetChild(ent)
			clone:SetPortal1(self)
			clone:SetPortal2(exit_portal)
			clone:Spawn()
			if not SeamlessPortals.IsLiveEntity(clone) or not IsValid(clone:GetPhysicsObject()) then SafeRemoveEntity(clone) cutout:RemoveEntity(ent) continue end
			ent.SEAMLESS_PORTALS_CLONE = clone
			clone.SEAMLESS_PORTALS_CUTOUT = exit_cutout
            if not exit_cutout:AddProxy(clone) then cutout:RemoveEntity(ent) continue end
		end

		if ent:IsPlayerHolding() or SeamlessPortals.HasTrackedHold(ent)
            or clone:IsPlayerHolding()
            or (SeamlessPortals.CarryKeepsAdmission and SeamlessPortals.CarryKeepsAdmission(ent,self)) then continue end

		local ent_pos = ent:GetPos()
		local ent_pos_center = ent:LocalToWorld(ent:OBBCenter())
		if (ent_pos_center - self_pos):Dot(self_up) >= -0.05 then continue end

		if not exit_cutout_valid or not exit_cutout.SEAMLESS_PORTALS_READY then cutout:RemoveEntity(ent) continue end
        if ent.SEAMLESS_PORTALS_LAST_TRANSFER == engine.TickCount() then continue end
        if constraint.HasConstraints(ent) then
            local plan, reason = SeamlessPortals.PlanTransport(ent, self, exit_portal)
            if plan then
                local ok
                ok, reason = SeamlessPortals.CommitTransport(plan)
                if ok then SeamlessPortals.NotifyTransport(plan, "assembly") end
            end
            if reason then ent.SEAMLESS_PORTALS_TRANSPORT_BLOCKED = reason end
            continue
        end
		local transaction = clone:PrepareTransfer(ent)
		if not transaction then cutout:RemoveEntity(ent) continue end
		phys = ent:GetPhysicsObject()
		if not IsValid(phys) then clone:RollbackTransfer(transaction) cutout:RemoveEntity(ent) continue end
		local new_pos, new_ang = SeamlessPortals.TransformPortal(self, exit_portal, ent_pos, ent:GetAngles())
		local new_vel = SeamlessPortals.TransformDirection(self, exit_portal, phys:GetVelocity(), true)

		cutout:RemoveEntity(ent, true)
		if not exit_cutout:AddEntity(ent) then
			clone:RollbackTransfer(transaction)
			SafeRemoveEntity(clone)
			continue
		end

		ent:SetPos(new_pos) -- avoid physobj lerp
		ent:SetAngles(new_ang)
		phys:SetVelocity(new_vel)
		if IsValid(clone.SEAMLESS_PORTALS_PROXY_CUTOUT) then clone.SEAMLESS_PORTALS_PROXY_CUTOUT:RemoveProxy(clone) end
        clone:SetPortal1(exit_portal)
		clone:SetPortal2(self)
        if not cutout:AddProxy(clone) then exit_cutout:RemoveEntity(ent) continue end
		if not clone:VerletWeld(clone, ent, true, true) then
			exit_cutout:RemoveEntity(ent)
			continue
		end
		-- Outputs describe a completed transfer, not admission into a cutout.
		ent.SEAMLESS_PORTALS_LAST_TRANSFER = engine.TickCount()
        self:TriggerOutput("OnTeleportFrom", ent)
		if IsValid(exit_portal) and IsValid(ent) then exit_portal:TriggerOutput("OnTeleportTo", ent) end
		if not SeamlessPortals.IsLiveEntity(ent) then continue end

        -- Small objects are not disposable. Preserve ownership and contents.
	end

	self:NextThink(CurTime())
	return true
end

-- RadiusDamage reaches this even when no ordinary entity is near the source.
function ENT:OnTakeDamage(info)
    if SeamlessPortals.ObserveNativeBlast then SeamlessPortals.ObserveNativeBlast(self,info,false) end
end

function ENT:OnTraceAttack(info,direction,trace)
    if SeamlessPortals.RelayPortalMelee then SeamlessPortals.RelayPortalMelee(self,info,direction,trace) end
    info:SetDamage(0)
end
