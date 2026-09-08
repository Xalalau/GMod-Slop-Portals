ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.Category          = "Seamless Portals"
ENT.PrintName         = "Cutout"
ENT.Author            = "Meetric"
ENT.Purpose           = ""
ENT.Instructions      = ""
ENT.DisableDuplicator = true
ENT.ENTITIES          = {}
ENT.VERTICES          = {}

SeamlessPortals.CutoutMeshRevision = 1

-- SERVER only entity
-- physically cuts a hole in the world,
-- code reused from Earthbending

-- tris are in the format {pos1, pos2, pos3, ...}
-- code based on Glass: Rewrite
local function cut_concave(tris, plane_pos, plane_dir)
	plane_dir = plane_dir:GetNormalized()

	local split_tris = {}
	local intersect = util.IntersectRayWithPlane

	local function inside(p)
		return (p - plane_pos):Dot(plane_dir) >= 0
	end

	-- sutherland-hodgman
	local function clip(poly)
		local result = {}

		for i = 1, #poly do
			local a = poly[i] -- current
			local b = poly[i % #poly + 1] -- previous
			local a_in = inside(a)
			local b_in = inside(b)

			if a_in and b_in then
				result[#result + 1] = b
			elseif a_in then
				result[#result + 1] = intersect(a, b - a, plane_pos, plane_dir) or b
			elseif b_in then
				result[#result + 1] = intersect(a, b - a, plane_pos, plane_dir) or b
				result[#result + 1] = b
			end
		end

		return result
	end

	for i = 1, #tris, 3 do
		local poly = clip({
			tris[i    ],
			tris[i + 1],
			tris[i + 2]
		})

		for j = 2, #poly - 1 do
			split_tris[#split_tris + 1] = poly[1    ]
			split_tris[#split_tris + 1] = poly[j    ]
			split_tris[#split_tris + 1] = poly[j + 1]
		end
	end

	return split_tris
end

-- __eq vector comparisons are too precise
local function vector_equal(v0, v1)
    return (v0 - v1):LengthSqr() < 1e-3
end

local function trace_local(self, start_pos, end_pos)
	local tr_table = {
        start = self:LocalToWorld(start_pos),
        endpos = self:LocalToWorld(end_pos),
        mask = MASK_SOLID_BRUSHONLY,
        filter = function() return false end, -- exclude entities; world is traced separately
    }

    local tr = SeamlessPortals.TraceLine(tr_table)

	if tr.Fraction == 1 and tr.StartSolid then
		return start_pos
	end

    return self:WorldToLocal(tr.HitPos)
end

function ENT:SetPortal(portal)
	self.SEAMLESS_PORTALS_CUTOUT_PORTAL = portal
end

function ENT:GetPortal()
	return self.SEAMLESS_PORTALS_CUTOUT_PORTAL
end

function ENT:Initialize()
	self.ENTITIES, self.VERTICES, self.PROXIES = {}, {}, {}
	self.SEAMLESS_PORTALS_READY = false
    self:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) -- props only
    self:SetTrigger(true)
end

-- approximates the world surface with a hole cut into it
function ENT:GeneratePhysmesh(portal, exit_portal)
	local size = portal:GetSize()
	local offset = size / 2
	local aperture_min, aperture_max = SeamlessPortals.GetApertureBounds(size, portal:GetSides())

	if exit_portal then self.VERTICES = {} end
	local vertices = {}

	local function pos_local(x, y, z)
		-- These surface probes extend past the aperture. GMod Lerp clamps to
		-- [0, 1], which misses floors even slightly below the portal's bottom.
		return Vector(aperture_min.x + x * (aperture_max.x - aperture_min.x),
			aperture_min.y + y * (aperture_max.y - aperture_min.y), z - size[3])
	end

	local inset = -2
	local pos00 = pos_local(0, 0, inset)
	local pos10 = pos_local(1, 0, inset)
	local pos01 = pos_local(0, 1, inset)
	local pos11 = pos_local(1, 1, inset)

	local function generate_tri(pos0, pos1, pos2)
		-- check for degen triangles
		if vector_equal(pos0, pos1) or vector_equal(pos0, pos2) or vector_equal(pos1, pos2) then return end

		local len = #vertices
		vertices[len + 1] = pos0
		vertices[len + 2] = pos1
		vertices[len + 3] = pos2
	end

	local function generate_quad(pos0, pos1, pos2, pos3)
		-- check for degen triangles
		if vector_equal(pos0, pos1) or vector_equal(pos0, pos3) or vector_equal(pos1, pos3) then return end
		if vector_equal(pos3, pos2) or vector_equal(pos3, pos0) or vector_equal(pos2, pos0) then return end

		local len = #vertices
		vertices[len + 1] = pos0
		vertices[len + 2] = pos1
		vertices[len + 3] = pos3
		vertices[len + 4] = pos3
		vertices[len + 5] = pos2
		vertices[len + 6] = pos0
	end

	local function trace_local_generate_quad(start_pos, end_pos)
		local tr = SeamlessPortals.TraceLine({
			start = portal:LocalToWorld(start_pos),
			endpos = portal:LocalToWorld(end_pos),
			mask = MASK_SOLID_BRUSHONLY,
        filter = function() return false end, -- exclude entities; world is traced separately
		})

		if !tr.Hit then return nil end

		tr.HitAngle = portal:WorldToLocalAngles(tr.HitNormal:Angle())
		tr.HitPos = portal:WorldToLocal(tr.HitPos)

		local right = tr.HitAngle:Right() * math.max(size[1], size[2]) * 1.5
		local front = tr.HitAngle:Up() * math.max(size[1], size[2]) * 1.5
		generate_quad(tr.HitPos - front + right, tr.HitPos + front + right, tr.HitPos - front - right, tr.HitPos + front - right)
	end

    -- ground quads
    trace_local_generate_quad(pos_local(0.5, 0.5, offset[3]), pos_local(2.5, 0.5, offset[3]))
    trace_local_generate_quad(pos_local(0.5, 0.5, offset[3]), pos_local(-1.5, 0.5, offset[3]))
    trace_local_generate_quad(pos_local(0.5, 0.5, offset[3]), pos_local(0.5, 2.5, offset[3]))
    trace_local_generate_quad(pos_local(0.5, 0.5, offset[3]), pos_local(0.5, -1.5, offset[3]))
	trace_local_generate_quad(pos_local(0.5, 0.5, offset[3]), pos_local(0.5, 0.5, offset[1] * 3))

	-- inner quads
	if !exit_portal then
		local pos00_z = Vector(pos00[1], pos00[2])
		local pos01_z = Vector(pos01[1], pos01[2])
		local pos10_z = Vector(pos10[1], pos10[2])
		local pos11_z = Vector(pos11[1], pos11[2])
	    generate_quad(pos00_z, pos00_z * 1.1, pos01_z, pos01_z * 1.1)
	    generate_quad(pos10_z, pos10_z * 1.1, pos00_z, pos00_z * 1.1)
	    generate_quad(pos11_z, pos11_z * 1.1, pos10_z, pos10_z * 1.1)
	    generate_quad(pos01_z, pos01_z * 1.1, pos11_z, pos11_z * 1.1)
    end

	if #vertices <= 0 then return end

	vertices = cut_concave(vertices, vector_origin, Vector(0, 0, 1))
    -- Without surrounding world surfaces a rectangular cutout previously became
    -- empty, so admission was permanently disabled. Build only the outside rim.
    local aperture = SeamlessPortals.ApertureVertices(portal)
    for i,a in ipairs(aperture) do
        local b=aperture[i % #aperture+1]
        local edge=b-a
        local outward=Vector(-edge.y,edge.x,0):GetNormalized()*1.5
        local top={a,b,b+outward,a+outward}
        local down=Vector(0,0,-math.max(size.z,1))
        for j=2,3 do
            generate_tri(top[1],top[j+1],top[j])
            generate_tri(top[1]+down,top[j]+down,top[j+1]+down)
        end
        for j,p in ipairs(top) do
            local q=top[j % 4+1]
            generate_tri(p,q,p+down)
            generate_tri(q,q+down,p+down)
        end
    end

    -- Close the corners of the bounding rectangle with actual polygon borders.
    -- These prisms replace the rectangular-only restriction, including gun portals.
    for _, poly in ipairs(SeamlessPortals.ApertureBorderPieces(portal)) do
        local depth = Vector(0, 0, -size.z - 2)
        for i = 2, #poly - 1 do
            generate_tri(poly[1], poly[i+1], poly[i])
            generate_tri(poly[1]+depth, poly[i]+depth, poly[i+1]+depth)
        end
        for i, a in ipairs(poly) do
            local b = poly[i % #poly + 1]
            generate_quad(a, b, a+depth, b+depth)
        end
    end
	if exit_portal then -- invert cut
		local ratio = exit_portal:GetSize()[1] / portal:GetSize()[1]
		local negated_verts = {}
		for _, v in ipairs(vertices) do
			if !negated_verts[v] then
				v[2] = -v[2]
				v[3] = -v[3]
				v:Mul(ratio)
				negated_verts[v] = true
			end
		end
	else
		--    f0 f1
		-- l1 01 11 r1
		-- l0 00 10 r0
		--    b0 b1
		local front0 = trace_local(portal, pos01 + Vector(0, 100, -inset), pos01)
		local front1 = trace_local(portal, pos11 + Vector(0, 100, -inset), pos11)
		local back0  = trace_local(portal, pos00 - Vector(0, 100, -inset), pos00)
		local back1  = trace_local(portal, pos10 - Vector(0, 100, -inset), pos10)
		local right0 = trace_local(portal, pos10 + Vector(100, 0, -inset), pos10)
		local right1 = trace_local(portal, pos11 + Vector(100, 0, -inset), pos11)
		local left0  = trace_local(portal, pos00 - Vector(100, 0, -inset), pos00)
		local left1  = trace_local(portal, pos01 - Vector(100, 0, -inset), pos01)

		-- corner triangles
		generate_tri(left0, pos00, back0)
		generate_tri(back1, pos10, right0)
		generate_tri(right1, pos11, front1)
		generate_tri(front0, pos01, left1)

		-- edge quads
		generate_quad(pos00, left0, pos01, left1)
		generate_quad(pos10, back1, pos00, back0)
		generate_quad(pos10, pos11, right0, right1)
		generate_quad(front1, pos11, front0, pos01)
    end
	--[[
	for i = 1, #vertices, 3 do
		debugoverlay.Triangle(
			self:LocalToWorld(vertices[i]), self:LocalToWorld(vertices[i + 1]), self:LocalToWorld(vertices[i + 2]),
			0.5, Color(255, 255, 255, 5), false
		)
	end]]

    for _, v in ipairs(vertices) do
    	table.insert(self.VERTICES, v)
    end
end

function ENT:CreatePhysmesh()
	local clean = {}
	for i = 1, #self.VERTICES - 2, 3 do
		local a, b, c = self.VERTICES[i], self.VERTICES[i + 1], self.VERTICES[i + 2]
		local finite = true
		for _, v in ipairs({a, b, c}) do
			for axis = 1, 3 do if not SeamlessPortals.IsFinite(v[axis]) then finite = false end end
		end
		if finite and (b - a):Cross(c - a):LengthSqr() > 1e-8 then
			clean[#clean + 1], clean[#clean + 2], clean[#clean + 3] = a, b, c
		end
	end
	if #clean == 0 or #clean > 24000 then return false end
	self.VERTICES = clean
	self:SetSolid(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_NONE)
	if #self.VERTICES < 3 or #self.VERTICES % 3 ~= 0 then return false end
	if not self:PhysicsFromMesh(self.VERTICES) then return false end
	self:EnableCustomCollisions(true)

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:EnableMotion(false)
		phys:SetPos(self:GetPos())
		phys:SetAngles(self:GetAngles())
		self.SEAMLESS_PORTALS_MESH_REVISION = SeamlessPortals.CutoutMeshRevision
		return true
	end
	return false
end

local allowed_classes = {
	["prop_physics"] = true,
	["prop_vehicle_airboat"] = true,
	["prop_vehicle_prisoner_pod"] = true,
	-- Native projectiles have a separate swept crossing adapter (F06).
    ["prop_physics_multiplayer"] = true,
    ["npc_rollermine"] = true,
}

function ENT:Think()
    local SP=SeamlessPortals
    local portal=self:GetPortal()
    if not SP.IsPortal(portal) or not self.SEAMLESS_PORTALS_READY then return end
    if not SP.SameGeometry(self.SEAMLESS_PORTALS_GEOMETRY,SP.CaptureGeometry(portal)) then self:Deactivate() return end
    local lo,hi=SP.GetApertureBounds(portal:GetSize(),portal:GetSides())
    lo=Vector(lo.x-128,lo.y-128,-portal:GetSize().z-128)
    hi=Vector(hi.x+128,hi.y+128,128)
    local mins,maxs=self:GetRotatedAABB(lo,hi)
    mins:Add(self:GetPos()) maxs:Add(self:GetPos())
    local candidates={}
    for _,ent in ipairs(ents.FindInBox(mins,maxs)) do candidates[ent]=true end
    -- Retained handles may be far behind a thin portal. They are not discarded
    -- just because their entity origin left its decorative slab.
    for ent in pairs(self.ENTITIES) do candidates[ent]=true end
    local release={}
    self.SEAMLESS_PORTALS_TRACK=self.SEAMLESS_PORTALS_TRACK or {}
    for ent in pairs(candidates) do
        if not SP.IsLiveEntity(ent) then
            release[#release+1]=ent
        elseif allowed_classes[ent:GetClass()] then
            local phys=ent:GetPhysicsObject()
            local fp=SP.PortalOBB(portal,ent)
            local kept=SP.CarryKeepsAdmission and SP.CarryKeepsAdmission(ent,portal)
            local velocity=IsValid(phys) and phys:GetVelocity() or vector_origin
            local lead=math.min(128,8+velocity:Length()*engine.TickInterval())
            local near=fp.overlap and fp.lo.z<=lead and fp.hi.z>=-portal:GetSize().z-32
            local track=self.SEAMLESS_PORTALS_TRACK[ent]
            if self.ENTITIES[ent] then
                if kept or near then
                    self.SEAMLESS_PORTALS_TRACK[ent]=track or {front_seen=true}
                    self.SEAMLESS_PORTALS_TRACK[ent].misses=0
                else
                    track=track or {front_seen=true,misses=0}
                    track.misses=(track.misses or 0)+1
                    self.SEAMLESS_PORTALS_TRACK[ent]=track
                    if track.misses>=2 then release[#release+1]=ent end
                end
            elseif near and fp.hi.z>=0 and (kept or velocity:Dot(portal:GetUp())<0) then
                if self:AddEntity(ent) then self.SEAMLESS_PORTALS_TRACK[ent]={front_seen=true,misses=0} end
            end
        end
    end
    for _,ent in ipairs(release) do self:RemoveEntity(ent) end
    self:NextThink(CurTime())
    return true
end


local logic_collision_pair
local function get_collision_pair()
    if SeamlessPortals.IsLiveEntity(logic_collision_pair) then return logic_collision_pair end
    local helper = ents.Create("logic_collision_pair")
    if not SeamlessPortals.IsLiveEntity(helper) then return nil end
    helper:Spawn()
    if not SeamlessPortals.IsLiveEntity(helper) then return nil end
    logic_collision_pair = helper
    return helper
end
hook.Add("PostCleanupMap", "seamless_portals_collision_helper", function()
    logic_collision_pair = nil -- recreated only when a collision operation needs it
end)
hook.Add("ShutDown", "seamless_portals_collision_helper", function()
    SafeRemoveEntity(logic_collision_pair)
    logic_collision_pair = nil
end)

local function set_collision(ent, ent2, enable)
	if not IsValid(ent) or (not IsValid(ent2) and ent2 ~= game.GetWorld()) then return false end
	local helper = get_collision_pair()
	if not helper then return false end

	local ent_phys = ent:GetPhysicsObject()
	local ent2_phys = ent2:GetPhysicsObject()
	if not IsValid(ent_phys) or not IsValid(ent2_phys) then return false end

	helper:SetPhysConstraintObjects(ent_phys, ent2_phys)
	helper:Activate()
	-- The native helper caches its last input, even after changing objects.
	-- Repeated enables must also restore pairs disabled on an earlier crossing.
	if not helper:SetSaveValue("m_succeeded", false) then return false end
	helper:Input(enable and "EnableCollisions" or "DisableCollisions")

	if IsValid(ent_phys) then
		ent_phys:RecheckCollisionFilter()
	end
	return true
end

SeamlessPortals.SetCollisionPair = set_collision

-- A failed restoration is retried independently of the removed cutout's lifetime.
-- This is best-effort recovery, not an observation of native collision state.
local restore_pending = setmetatable({}, {__mode = "k"})
local function restore_world_collision(ent)
    if not IsValid(ent) then restore_pending[ent] = nil return false end
    if set_collision(ent, game.GetWorld(), true) then
        restore_pending[ent] = nil
        return true
    end
    restore_pending[ent] = true
    return false
end
hook.Add("Think", "seamless_portals_restore_collision", function()
    for ent in pairs(restore_pending) do
        if not IsValid(ent) or ent.SEAMLESS_PORTALS_CUTOUT ~= nil then
            restore_pending[ent] = nil
        else
            restore_world_collision(ent)
        end
    end
end)

-- Proxy ownership is separate from source ownership. A proxy must never enter
-- the ordinary teleport loop as if it were another real prop.
function ENT:AddProxy(clone)
    if not self.SEAMLESS_PORTALS_READY or not IsValid(clone) then return false end
    self.PROXIES=self.PROXIES or {}
    if self.PROXIES[clone] then return true end
    if not set_collision(clone,self,true) then return false end
    if not set_collision(clone,game.GetWorld(),false) then set_collision(clone,self,false) return false end
    self.PROXIES[clone]=true
    clone.SEAMLESS_PORTALS_PROXY_CUTOUT=self
    return true
end
function ENT:RemoveProxy(clone)
    if self.PROXIES then self.PROXIES[clone]=nil end
    if not IsValid(clone) or clone.SEAMLESS_PORTALS_PROXY_CUTOUT~=self then return end
    clone.SEAMLESS_PORTALS_PROXY_CUTOUT=nil
    set_collision(clone,self,false)
    restore_world_collision(clone)
end

function ENT:AddEntity(ent)
    if not SeamlessPortals.IsLiveEntity(self) or not SeamlessPortals.IsLiveEntity(ent)
        or not self.SEAMLESS_PORTALS_READY or self.SEAMLESS_PORTALS_DEACTIVATING then return false end
	if self.ENTITIES[ent] then return ent.SEAMLESS_PORTALS_CUTOUT == self end
	if ent.SEAMLESS_PORTALS_CUTOUT then return false end
	if ent:GetClass()=="npc_rollermine" then
        local portal=self:GetPortal()
        local exit=SeamlessPortals.IsPortal(portal) and portal:GetExitPortal()
        if not SeamlessPortals.IsUsableLink(portal,exit) then return false end
        local width,exit_width=portal:GetSize().x,exit:GetSize().x
        -- Rescaling rebuilds physics and would destroy the native mine controller.
        if math.abs(width-exit_width)>math.max(width,exit_width)*0.0001 then return false end
    end
	if constraint.HasConstraints(ent) and SeamlessPortals.CollectTransportGroup then
        local group = SeamlessPortals.CollectTransportGroup(ent, SeamlessPortals.HeldBy and SeamlessPortals.HeldBy(ent), true)
        if not group then return false end
    end


    if not IsValid(ent:GetPhysicsObject()) or not IsValid(self:GetPhysicsObject()) then return false end
    if not set_collision(ent, self, true) then return false end
    if not set_collision(ent, game.GetWorld(), false) then
        set_collision(ent, self, false)
        restore_world_collision(ent)
        return false
    end
    restore_pending[ent] = nil
    self.ENTITIES[ent] = true
    ent.SEAMLESS_PORTALS_CUTOUT = self
    if ent.SetNWEntity then ent:SetNWEntity("seamless_portals_clip_entry",self:GetPortal()) end
    return true
end

function ENT:RemoveEntity(ent, keep_clone)
    self.ENTITIES[ent] = nil
    if self.SEAMLESS_PORTALS_TRACK then self.SEAMLESS_PORTALS_TRACK[ent]=nil end
    if not IsValid(ent) then return end
    if ent.SEAMLESS_PORTALS_CUTOUT ~= self then return end
    if not keep_clone then
        local clone = ent.SEAMLESS_PORTALS_CLONE
        ent.SEAMLESS_PORTALS_CLONE = nil
        SafeRemoveEntity(clone)
    end
    ent.SEAMLESS_PORTALS_CUTOUT = nil
    if ent.SetNWEntity then ent:SetNWEntity("seamless_portals_clip_entry",NULL) end
    set_collision(ent, self, false)
    restore_world_collision(ent)
end

-- Idempotent: cleanup can run before Remove(), on invalidation and in OnRemove().
function ENT:Deactivate()
    if self.SEAMLESS_PORTALS_DEACTIVATING then return end
    self.SEAMLESS_PORTALS_DEACTIVATING = true
    self.SEAMLESS_PORTALS_READY = false
    local records={}
    for ent in pairs(self.ENTITIES or {}) do
        local record=IsValid(ent) and ent.SEAMLESS_PORTALS_CARRY
        if record and not records[record] then
            records[record]=true
            if SeamlessPortals.RestoreCarryFront then SeamlessPortals.RestoreCarryFront(record) end
            if SeamlessPortals.ClearCarryState then SeamlessPortals.ClearCarryState(record) end
        end
        self:RemoveEntity(ent)
    end
    for clone in pairs(self.PROXIES or {}) do self:RemoveProxy(clone) end
end

function ENT:PhysicsCollide(data)
    local ent=data.HitEntity
    if self.ENTITIES[ent] or (self.PROXIES and self.PROXIES[ent]) then return end
    -- Changing collision filters/freezing within VPhysics callbacks is unsafe.
    -- Defer the filter update, and never detach a native held controller.
    local velocity=data.TheirOldVelocity and Vector(data.TheirOldVelocity)
    local angular=data.TheirOldAngularVelocity and Vector(data.TheirOldAngularVelocity)
    timer.Simple(0,function()
        if not IsValid(self) or not IsValid(ent) or self.ENTITIES[ent]
            or (self.PROXIES and self.PROXIES[ent]) then return end
        set_collision(ent,self,false)
        local phys=ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:RecheckCollisionFilter()
            if not ent:IsPlayerHolding() and phys:IsMotionEnabled() then
                if velocity then phys:SetVelocity(velocity) end
                if angular then phys:SetAngleVelocity(angular) end
            end
        end
    end)
end

function ENT:StartTouch(ent)
	timer.Simple(0, function() -- will crash without this!
		if IsValid(self) and IsValid(ent) and self.SEAMLESS_PORTALS_READY then self:PhysicsCollide({HitEntity = ent}) end
	end)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:TestCollision(_, delta, isbox, _, mask)
	return isbox and mask == 33570827 and !delta:IsZero() -- nothing except vphysics spawn trace
end

function ENT:OnRemove()
	self:Deactivate()
end
