AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.Category          = "Seamless Portals"
ENT.PrintName         = "Physics Prop"
ENT.Author            = "Meetric"
ENT.Purpose           = ""
ENT.Instructions      = ""
ENT.DisableDuplicator = true

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "Child")
    self:NetworkVar("Entity", 1, "Portal1")
    self:NetworkVar("Entity", 2, "Portal2")
end

-- Only the clone that installed this clip plane may release it.
function ENT:ReleaseChildClip()
    local child = self.SEAMLESS_PORTALS_CLIPPED_CHILD or self:GetChild()
    if IsValid(child) and child.SEAMLESS_PORTALS_CLIP_OWNER == self then
        child.SEAMLESS_PORTALS_CLIP_OWNER = nil
        child:SetRenderClipPlaneEnabled(false)
    end
    self.SEAMLESS_PORTALS_CLIPPED_CHILD = nil
end

function ENT:Think()
    if self.SEAMLESS_PORTALS_RETIRED then return end
	local child, p1, p2 = self:GetChild(), self:GetPortal1(), self:GetPortal2()
	if not IsValid(child) or not SeamlessPortals.IsUsableLink(p1, p2) then
		if CLIENT then self:ReleaseChildClip() end
		if SERVER then SafeRemoveEntity(self) end
		return
	end
	if SERVER then
		if not self:VerletWeld(self, self:GetChild()) then
            local cutout = child.SEAMLESS_PORTALS_CUTOUT
            if IsValid(cutout) then cutout:RemoveEntity(child) else SafeRemoveEntity(self) end
            return
        end
		self:UpdateLightingOrigin()
        local destination=p2.SEAMLESS_PORTALS_CUTOUT
        local footprint=SeamlessPortals.PortalOBB(p2,self)
        local owner=self.SEAMLESS_PORTALS_PROXY_CUTOUT
        if footprint.fully_front then
            if IsValid(owner) then owner:RemoveProxy(self) end
        elseif IsValid(destination) and destination.SEAMLESS_PORTALS_READY then
            if IsValid(owner) and owner~=destination then owner:RemoveProxy(self) end
            if not destination:AddProxy(self) then SafeRemoveEntity(self) return end
        end
        self:NextThink(CurTime())
        return true
	end

	local child = self:GetChild()
	if !IsValid(child) then return end

	local portal1 = self:GetPortal1()
	local portal2 = self:GetPortal2()
	local new_pos, new_ang = SeamlessPortals.TransformPortal(portal1, portal2, child:GetPos(), child:GetAngles())
    self:SetRenderOrigin(new_pos)
    self:SetRenderAngles(new_ang)

    local clip_up1 = portal1:GetUp()
    local clip_pos1 = portal1:GetPos()
    -- Clip at the visible front plane, not behind the decorative slab.
    if self.SEAMLESS_PORTALS_CLIPPED_CHILD ~= child then self:ReleaseChildClip() end
    self.SEAMLESS_PORTALS_CLIPPED_CHILD = child
    child.SEAMLESS_PORTALS_CLIP_OWNER = self
    child:SetRenderClipPlaneEnabled(true)
	child:SetRenderClipPlane(clip_up1, clip_up1:Dot(clip_pos1))

	local clip_up2 = portal2:GetUp()
    local clip_pos2 = portal2:GetPos()
    -- The emerged proxy uses the same z=0 crossing plane.
    self:SetRenderClipPlaneEnabled(true)
	self:SetRenderClipPlane(clip_up2, clip_up2:Dot(clip_pos2))

	self:SetNextClientThink(CurTime())
	return true
end

if SERVER then
	function ENT:UpdateLightingOrigin()
		local child=self:GetChild()
		local record=IsValid(child) and child.SEAMLESS_PORTALS_CARRY
		-- A fully emerged held prop uses the light in its visible room.
		local remote=record and SeamlessPortals.IsPortal(record.entry)
			and SeamlessPortals.PortalOBB(record.entry,child).fully_back
		local origin=remote and self or child
		if IsValid(origin) and self.SEAMLESS_PORTALS_LIGHT_ORIGIN~=origin then
			self:SetLightingOriginEntity(origin)
			self.SEAMLESS_PORTALS_LIGHT_ORIGIN=origin
		end
	end
	local function transform_portal_local(portal1, portal2, dir)
		return SeamlessPortals.TransformDirection(portal1, portal2, dir, true)
	end

	local function abs_ratio(scale1, scale2)
		if scale1 > scale2 then
			return scale1 / scale2
		end

		return scale2 / scale1
	end


    local function set_model_scale_checked(ent, scale)
        if not SeamlessPortals.IsFinite(scale) or scale <= 0 then return nil end
        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then return nil end
        local old_scale = ent:GetModelScale()
        if not SeamlessPortals.IsFinite(old_scale) or old_scale <= 0 then return nil end
        if math.abs(scale - old_scale) <= math.max(scale, old_scale) * 0.0001 then return phys end
        local convexes = phys:GetMeshConvexes()
        if not istable(convexes) then return nil end
        local total = 0
        for _, convex in ipairs(convexes) do
            total = total + #convex
            if #convex >= 2000 or total > 16000 then return nil end
        end
        local velocity, angular = phys:GetVelocity(), phys:GetAngleVelocity()
        local motion, material, mass = phys:IsMotionEnabled(), phys:GetMaterial(), phys:GetMass()
        local linear_damping, angular_damping = phys:GetDamping()
        local solid = ent:GetSolid()
        ent:SetModelScale(scale, 0)
        if not ent:PhysicsInit(solid) then
            -- PhysicsInit retains the old object when creation fails; revert visual scale.
            ent:SetModelScale(old_scale, 0)
            return nil
        end
        -- PhysicsInit creates model physics; Activate applies SetModelScale to
        -- supported prop/anim collision models. Reacquire after both operations.
        ent:Activate()
        phys = ent:GetPhysicsObject()
        if not IsValid(phys) then ent:SetModelScale(old_scale, 0) return nil end
        phys:SetMaterial(material)
        phys:SetDamping(linear_damping, angular_damping)
        -- Explicit compatibility policy: relative area scaling, not a density model.
        phys:SetMass(math.Clamp(mass * (scale / old_scale) ^ 2, 1, 50000))
        phys:EnableMotion(motion)
        phys:SetVelocity(velocity)
        phys:SetAngleVelocity(angular)
        return phys
    end

    function ENT:PrepareTransfer(child)
        local transaction = {child = child, child_scale = child:GetModelScale(), clone_scale = self:GetModelScale()}
        local target_scale = transaction.clone_scale
        local reverse_scale = target_scale * self:GetPortal1():GetSize()[1] / self:GetPortal2():GetSize()[1]
        if not set_model_scale_checked(child, target_scale) then return nil end
        if not set_model_scale_checked(self, reverse_scale) then
            set_model_scale_checked(child, transaction.child_scale)
            return nil
        end
        return transaction
    end
    function ENT:RollbackTransfer(transaction)
        if IsValid(transaction.child) then set_model_scale_checked(transaction.child, transaction.child_scale) end
        if IsValid(self) then set_model_scale_checked(self, transaction.clone_scale) end
    end

	-- 2 way coupling
	function ENT:VerletWeld(e1, e2, setpos, skip_scale)
		if not IsValid(e1) or not IsValid(e2) or not SeamlessPortals.IsUsableLink(self:GetPortal1(), self:GetPortal2()) then return false end
		local portal1 = self:GetPortal1()
		local portal2 = self:GetPortal2()

		local e1_phys = e1:GetPhysicsObject()
		local e2_phys = e2:GetPhysicsObject()
		if !IsValid(e1_phys) or !IsValid(e2_phys) then return end

        -- A held/constrained source is authoritative. Do not resize or feed proxy
        -- correction forces into a native grab controller or a welded assembly.
        if e2:IsPlayerHolding() or SeamlessPortals.HasTrackedHold(e2)
            or e2.SEAMLESS_PORTALS_CARRY or constraint.HasConstraints(e2) then
            local pos, ang = SeamlessPortals.TransformPortal(portal1,portal2,e2:GetPos(),e2:GetAngles())
            if SeamlessPortals.ClampHeldProxy then pos,ang=SeamlessPortals.ClampHeldProxy(e1,e2,portal1,portal2,pos,ang) end
            local scale = e2:GetModelScale()*portal2:GetSize().x/portal1:GetSize().x
            if math.abs(e1:GetModelScale()-scale)>0.0001 then
                e1_phys = set_model_scale_checked(e1,scale)
                if not IsValid(e1_phys) then return false end
            end
            e1:SetPos(pos) e1:SetAngles(ang)
            e1_phys:SetPos(pos,true) e1_phys:SetAngles(ang)
            e1_phys:EnableMotion(e2_phys:IsMotionEnabled())
            e1_phys:SetVelocity(transform_portal_local(portal1,portal2,e2_phys:GetVelocity()))
            e1_phys:SetAngleVelocity(e2_phys:GetAngleVelocity())
            return true
        end
		local motion = e2_phys:IsMotionEnabled()
		if not setpos and not motion and self.SEAMLESS_PORTALS_FROZEN_POSE then
			local pose = self.SEAMLESS_PORTALS_FROZEN_POSE
			if pose.pos == e2:GetPos() and pose.ang == e2:GetAngles()
				and pose.clone_pos == e1:GetPos() and pose.clone_ang == e1:GetAngles()
				and pose.scale1 == e1:GetModelScale() and pose.scale2 == e2:GetModelScale()
				and pose.phys1 == e1_phys and pose.phys2 == e2_phys and not e1_phys:IsMotionEnabled()
				and SeamlessPortals.SameGeometry(pose.portals, SeamlessPortals.CaptureGeometry(portal1)) then return true end
		end
		self.SEAMLESS_PORTALS_FROZEN_POSE = nil
		e1_phys:EnableMotion(motion)

		local e2_vel = e2_phys:GetVelocity()
		local e2_angvel = e2_phys:GetAngleVelocity()

		if setpos or !motion then
			local e1_pos, e1_ang = SeamlessPortals.TransformPortal(portal1, portal2, e2:GetPos(), e2:GetAngles())
			local e1_vel = transform_portal_local(portal1, portal2, e2_vel)

			-- scaling
			if setpos and not skip_scale then
				local e2_scale = e1:GetModelScale()
				if abs_ratio(e2_scale, e2:GetModelScale()) > 1.0001 then -- small numerical tolerance only
					e2_phys = set_model_scale_checked(e2, e2_scale)
					if not IsValid(e2_phys) then return false end
					e2_phys:SetVelocity(e2_vel)
					e2_phys:SetAngleVelocity(e2_angvel)
				end

				local e1_scale = e2_scale * (portal2:GetSize()[1] / portal1:GetSize()[1])
				if abs_ratio(e1_scale, e1:GetModelScale()) > 1.0001 then
					e1_phys = set_model_scale_checked(e1, e1_scale)
					if not IsValid(e1_phys) then return false end
				end
			end

			e1:SetPos(e1_pos)
			e1:SetAngles(e1_ang)
			e1_phys:SetVelocity(e1_vel)
			e1_phys:SetAngleVelocity(e2_angvel) -- already in local frame, no transform needed
			if not motion then
				self.SEAMLESS_PORTALS_FROZEN_POSE = {pos = Vector(e2:GetPos()), ang = Angle(e2:GetAngles()),
					clone_pos = Vector(e1:GetPos()), clone_ang = Angle(e1:GetAngles()),
					scale1 = e1:GetModelScale(), scale2 = e2:GetModelScale(), phys1 = e1_phys, phys2 = e2_phys,
					portals = SeamlessPortals.CaptureGeometry(portal1)}
			end

			return true
		end

		local e1_pos, e1_ang = SeamlessPortals.TransformPortal(portal2, portal1, e1_phys:GetPos(), e1_phys:GetAngles())

		local pos_delta = (e2_phys:GetPos() - e1_pos)
		local ang_delta = e2:WorldToLocalAngles(e1_ang)
		ang_delta = Vector(ang_delta[3], ang_delta[1], ang_delta[2])

		local bounding_diameter = e1:BoundingRadius() * 2
		local e1_percentage_through = math.Clamp((e1_pos - portal1:GetPos()):Dot(portal1:GetUp()) / bounding_diameter + 0.5, 0.5, 0.9)
		local e2_percentage_through = 1 - e1_percentage_through

		local e1_vel = transform_portal_local(portal2, portal1, e1_phys:GetVelocity())
		local e1_angvel = e1_phys:GetAngleVelocity() -- already in local frame
		local vel_average = (e2_vel * e1_percentage_through + e1_vel * e2_percentage_through)
		local angvel_average = (e2_angvel * e1_percentage_through + e1_angvel * e2_percentage_through)

		local pos_delta_frametime = pos_delta / (FrameTime() * 2)
		local e1_phys_vel = (vel_average + pos_delta_frametime * e1_percentage_through)
		local e2_phys_vel = (vel_average - pos_delta_frametime * e2_percentage_through)
		e1_phys_vel = transform_portal_local(portal1, portal2, e1_phys_vel)

		local ang_delta_frametime = ang_delta / (FrameTime() * 2)
		local e1_phys_angvel = (angvel_average - ang_delta_frametime * e1_percentage_through)
		local e2_phys_angvel = (angvel_average + ang_delta_frametime * e2_percentage_through)

		e1_phys:SetVelocity(e1_phys_vel)
	    e1_phys:SetAngleVelocity(e1_phys_angvel)

	    e2_phys:SetVelocity(e2_phys_vel)
	    e2_phys:SetAngleVelocity(e2_phys_angvel)
		return true
	end

	function ENT:Initialize()
		local child = self:GetChild()
		local portal1 = self:GetPortal1()
		local portal2 = self:GetPortal2()

		if not IsValid(child) or not SeamlessPortals.IsUsableLink(portal1, portal2)
			or not IsValid(child:GetPhysicsObject()) then SafeRemoveEntity(self) return end
		self:SetCollisionGroup(child:GetCollisionGroup())
		self:SetColor(child:GetColor())
		self:SetModel(child:GetModel())
		self:SetMaterial(child:GetMaterial())
		self:SetSkin(child:GetSkin())
		self:SetSolid(child:GetSolid())
		self:SetMoveType(child:GetMoveType())
		self:SetModelScale(1, 0)
		if not self:PhysicsInit(child:GetSolid()) or not IsValid(self:GetPhysicsObject()) then SafeRemoveEntity(self) return end
        if not set_model_scale_checked(self, child:GetModelScale()) then SafeRemoveEntity(self) return end
		self:UpdateLightingOrigin()
		self:GetPhysicsObject():SetMass(child:GetPhysicsObject():GetMass())
		if not self:VerletWeld(self, child, true) then SafeRemoveEntity(self) return end
		child:DeleteOnRemove(self)
		portal1:DeleteOnRemove(self)
		portal2:DeleteOnRemove(self)
		-- The exit cutout owns temporary world exclusion; no permanent NoCollide constraint.
	end

	function ENT:OnTakeDamage(damage)
        local child,p1,p2=self:GetChild(),self:GetPortal1(),self:GetPortal2()
        local enabled=GetConVar("seamless_portals_damage")
        if not IsValid(child) or not SeamlessPortals.LinkAllows(p1,p2,"damage") or (enabled and not enabled:GetBool()) then return end
        local position=SeamlessPortals.TransformPortal(p2,p1,damage:GetDamagePosition())
        local force=SeamlessPortals.TransformDirection(p2,p1,damage:GetDamageForce(),false)
        local forwarded=SeamlessPortals.CopyDamage(damage)
        forwarded:SetDamagePosition(position)
        forwarded:SetDamageForce(force)
        if SeamlessPortals.ForwardedProxyDamage then SeamlessPortals.ForwardedProxyDamage[forwarded]=true end
        local ok,err=xpcall(function() child:TakeDamageInfo(forwarded) end,debug.traceback)
        if SeamlessPortals.ForwardedProxyDamage then SeamlessPortals.ForwardedProxyDamage[forwarded]=nil end
        if not ok then ErrorNoHalt("[Seamless Portals] Proxy damage: "..tostring(err).."\n") end
    end

    function ENT:OnRemove()
        local owner=self.SEAMLESS_PORTALS_PROXY_CUTOUT
        if IsValid(owner) then owner:RemoveProxy(self) end
        local child=self:GetChild()
        if IsValid(child) and child.SEAMLESS_PORTALS_CLONE==self then child.SEAMLESS_PORTALS_CLONE=nil end
    end
else
    function ENT:OnRemove()
        self:ReleaseChildClip()
	end
end

function ENT:CanTool()
    return false
end
