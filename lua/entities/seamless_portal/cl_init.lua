include("sh_init.lua")

local varDrawDistance = SeamlessPortals.ClientConVars.drawdistance

function ENT:Initialize()
	self.SEAMLESS_PORTALS_GEOMETRY_DIRTY = true
	table.insert(SeamlessPortals.Portals, self)
end

function ENT:OnRemove()
	timer.Simple(0, function()
		if IsValid(self) then return end
		table.RemoveByValue(SeamlessPortals.Portals, self)
	end)
end

local drawMat = Material("models/dav0r/hoverball")

local render_matrix = Matrix()
function ENT:GetRenderMesh()
	local cached = SeamlessPortals.GetRenderMesh(self:GetSides())
	if not cached then return nil end
	return {
		Mesh     = cached,
		Matrix   = render_matrix,
		Material = drawMat
	}
end

function ENT:DrawModelMesh(portal_size, nudge_z)
	local draw_mesh = SeamlessPortals.GetRenderMesh(self:GetSides())
	if not draw_mesh then return end
	local render_matrix = self:GetWorldTransformMatrix()
	render_matrix:SetScale(portal_size)
	if nudge_z then render_matrix:Translate(Vector(0, 0, (nudge_z - 1))) end
	cam.PushModelMatrix(render_matrix)
	local ok, err = xpcall(function() draw_mesh:Draw() end, debug.traceback)
	cam.PopModelMatrix()
	if not ok then error(err, 0) end
end

-- So the size is in source units (remember we are using sine/cosine)
local size_mult = Vector(math.sqrt(2) / 2, math.sqrt(2) / 2, 1)

-- DrawModel inside of a non Draw hook will call Draw instead of DrawModel (thanks, gmod API)
-- this check is so we can call DrawModel inside of DrawStenciled
local draw_model = false
local function draw_stenciled(self, texture, flip, nudge_z)
	draw_model = true

	local portal_size = self:GetSize()
	portal_size:Mul(size_mult)

	-- little nudge for MSAA, otherwise it will sample the edges outside the portal
	-- and lead to some pretty nasty artifacting
	portal_size:Mul(nudge_z or 1)

	local backface_disabled = self:GetDisableBackface()
    local linked = SeamlessPortals.IsUsableLink(self,self:GetExitPortal())
    -- A live no-back portal has no geometry when viewed from behind, even if
    -- the view was rendered earlier in this frame or skipped by its budget.
    if backface_disabled and linked and SeamlessPortals.PlaneDistance(self,EyePos()) < 0 then return end

	render_matrix:Identity()
	render_matrix:SetScale(portal_size)

	-- outside frame (backface)
	if !backface_disabled then
		self:DrawModel()
	end

	-- F07: Backface is a backing-slab option, not visibility of an unlinked
    -- aperture. Always show a front-plane outline while no view is available.
    if backface_disabled and not linked then
        local vertices=SeamlessPortals.ApertureVertices(self)
        local color=Color(80,210,255,255)
        for i,a in ipairs(vertices) do
            local b=vertices[i % #vertices+1]
            render.DrawLine(self:LocalToWorld(a+Vector(0,0,0.1)),self:LocalToWorld(b+Vector(0,0,0.1)),color,true)
        end
        -- Two crossing guide lines distinguish a waiting aperture from a live
        -- portal. No opaque backface is added and depth occlusion is respected.
        if #vertices>=4 then
            for i=1,2 do
                local j=i+math.floor(#vertices/2)
                render.DrawLine(self:LocalToWorld(vertices[i]),self:LocalToWorld(vertices[j]),color,true)
            end
        end
    end

    -- frame flat face
	if SeamlessPortals.Rendering or not linked or !self.SEAMLESS_PORTALS_RENDERED then
		if !backface_disabled then
			portal_size[3] = 0
			render.CullMode(1)
				self:DrawModelMesh(portal_size)
			render.CullMode(0)
		end
	else
		render.ClearStencil()
		render.SetStencilWriteMask(255)
		render.SetStencilTestMask(255)
		render.SetStencilReferenceValue(1)
		render.SetStencilFailOperation(STENCIL_KEEP)
		render.SetStencilZFailOperation(STENCIL_KEEP)
		render.SetStencilPassOperation(STENCIL_REPLACE)
		render.SetStencilCompareFunction(STENCIL_ALWAYS)
		render.SetStencilEnable(true)
		render.SetMaterial(drawMat)

		-- Draw inside of portal
		render.CullMode(1)
			self:DrawModelMesh(portal_size, nudge_z)
		render.CullMode(0)

		render.SetStencilCompareFunction(STENCIL_EQUAL)

		if flip then
			render.DrawTextureToScreenRect(texture, ScrW(), 0, -ScrW(), ScrH())
		else
			render.DrawTextureToScreen(texture)
		end

		render.SetStencilEnable(false)
	end

	draw_model = false
end


function ENT:DrawStenciled(texture, flip, nudge_z)
    local ok, err = xpcall(function() draw_stenciled(self, texture, flip, nudge_z) end, debug.traceback)
    draw_model = false
    -- This renderer owns stencil/cull state for the duration of its pass.
    render.SetStencilEnable(false)
    render.CullMode(MATERIAL_CULLMODE_CCW)
    if not ok then error(err, 0) end
end

function ENT:Draw(flags)
	if bit.band(flags, STUDIO_SHADOWDEPTHTEXTURE) > 0 then return end -- portal should not cast shadows

	-- resetting the stencil buffer when drawing halos will cause horrible flashing
	-- also, don't render the portal we're rendering out of
	if halo.RenderedEntity() == self or SeamlessPortals.Rendering == self then return end

	if draw_model then
		self:DrawModel(flags)
	else
		self:DrawStenciled(SeamlessPortals.PortalRT)
	end
end

function ENT:Think()
	if not self:ReconcileGeometry() then return end
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:EnableMotion(false)
		phys:SetPos(self:GetPos())
		phys:SetAngles(self:GetAngles())
	else
		self:UpdatePhysmesh()
	end
end

local flashlight_extents = Vector(4, 4, 4)
function ENT:TestCollision(startpos, delta, isbox, extents, mask)
	-- probably flashlight
	if (mask == 33570947 or mask == 33570827) and extents == flashlight_extents then return false end

    -- C04 handles real pellet impacts in both realms; do not make portals
    -- transparent to client bullets only in singleplayer.

	return true
end

SeamlessPortals.DrawPlayerInView = true
SeamlessPortals.GetDrawDistance = function()
	return varDrawDistance:GetFloat()
end

-- Create meshes used for the portals
-- They can have a dynamic amount of sides
SeamlessPortals.PortalMeshes = SeamlessPortals.PortalMeshes or {}
local function destroy_portal_meshes()
	for sides, cached in pairs(SeamlessPortals.PortalMeshes) do
		cached:Destroy()
		SeamlessPortals.PortalMeshes[sides] = nil
	end
end
hook.Add("ShutDown", "seamless_portals_destroy_meshes", destroy_portal_meshes)
-- Bump this when topology changes; clear only outside an active portal render.
local mesh_version = 1
if SeamlessPortals.PortalMeshVersion ~= mesh_version and not SeamlessPortals.Rendering then
	destroy_portal_meshes()
	SeamlessPortals.PortalMeshVersion = mesh_version
end
SeamlessPortals.GetRenderMesh = function(sides)
	if not SeamlessPortals.ValidateSides(sides) then return nil end
	if !SeamlessPortals.PortalMeshes[sides] then
		SeamlessPortals.PortalMeshes[sides] = Mesh()
		local ang_mul = 360 / sides
		local ang_pick = sides % 4 != 0 and 0 or 45
		local rad_offset = math.rad(sides * 90 + ang_pick)
		local function mesh_vertex(pos, u, v)
			mesh.Position(pos)
			mesh.TexCoord(0, u, v)
			mesh.Normal(0, 0, 0)
			mesh.UserData(0, 0, 0, 0)
			mesh.AdvanceVertex()
		end
		mesh.Begin(SeamlessPortals.PortalMeshes[sides], MATERIAL_TRIANGLES, sides * 3)
		for side = 1, sides do
			local side1 = Vector(0, 0, -1)
			local sidex = math.rad(side * ang_mul) + rad_offset
			local sidey = math.rad((side + 1) * ang_mul) + rad_offset
			local side2 = Vector(math.sin(sidex), math.cos(sidex), -1)
			local side3 = Vector(math.sin(sidey), math.cos(sidey), -1)

			local streach1 = (side / sides) * 4
			local streach2 = ((side + 1) / sides) * 4
			mesh_vertex(side2, 1, 0)
			mesh_vertex(side1, 0, 1)
			mesh_vertex(side3, 0, 0)

			mesh_vertex(Vector(side2[1], side2[2]), streach1, 1)
			mesh_vertex(side2, streach1, 0)
			mesh_vertex(side3, streach2, 0)

			mesh_vertex(side3, streach2, 0)
			mesh_vertex(Vector(side3[1], side3[2]), streach2, 1)
			mesh_vertex(Vector(side2[1], side2[2]), streach1, 1)
		end
		mesh.End()
	end

	return SeamlessPortals.PortalMeshes[sides]
end

--Funny flipped scene
local mirrored = false
function SeamlessPortals.ToggleMirror(enable)
	if enable == nil then -- what the fuck is this
		return mirrored
	end

	mirrored = enable

	if (!enable) then
		hook.Remove("PreDrawViewModels", "seamless_portals_flip")
		hook.Remove("InputMouseApply", "seamless_portals_flip")
		hook.Remove("CreateMove", "seamless_portals_flip")

		return mirrored
	end

	hook.Add("PreDrawViewModels", "seamless_portals_flip", function()
		if SeamlessPortals.Rendering then return end

		render.UpdateScreenEffectTexture()
		render.DrawTextureToScreenRect(render.GetScreenEffectTexture(), ScrW(), 0, -ScrW(), ScrH())

		if LocalPlayer():Health() <= 0 then
			SeamlessPortals.ToggleMirror(false)
		end
	end)

	-- Invert mouse x
	hook.Add("InputMouseApply", "seamless_portals_flip", function(cmd, x, y, ang)
		cmd:SetViewAngles(ang + Angle(0, x / 22.5, 0))
	end)

	-- Invert movement x
	hook.Add("CreateMove", "seamless_portals_flip", function(cmd)
		cmd:SetSideMove(-cmd:GetSideMove())
	end)

	return mirrored
end

SeamlessPortals.ToggleMirror(false)
