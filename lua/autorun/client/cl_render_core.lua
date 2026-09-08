-- this is the rendering code for the portals. Rewritten on 7/25/2026

AddCSLuaFile()

if SERVER then return end
include("seamless_portals/skybox.lua")

local max_render = CreateClientConVar("seamless_portals_maxrender", "6", true, false, "maximum number of portals to render per frame", 0)
local scene_budget = CreateClientConVar("seamless_portals_render_budget_ms", "0", true, false, "Soft CPU wall-time budget; zero disables", 0, 50)
local skip_frames = CreateClientConVar("seamless_portals_refreshrate", "1", false, false, "How many frames to skip when rendering portals", 1)
local draw_viewer = CreateClientConVar("seamless_portals_drawviewer", "1", false, false, "Draw player in portal view", 0, 1)
local renderview_table = {
	x = 0,
	y = 0,
	w = ScrW(),
	h = ScrH(),
	origin = Vector(),
	angles = Angle(),
	drawviewmodel = false,
	viewid = 2
}

local function get_framebuffer(name)
	return GetRenderTargetEx(name, 1, 1,
	    RT_SIZE_FULL_FRAME_BUFFER,
	    MATERIAL_RT_DEPTH_SEPARATE,
	    4 + 8 + 256 + 512,
	    0,
	    IMAGE_FORMAT_RGBA8888
	)
end

-- TODO: ideally use pre-allocated framebuffers
SeamlessPortals.PortalRT = get_framebuffer("seamless_portals_backbuffer")
SeamlessPortals.Frame = 0
local framebuffer = get_framebuffer("seamless_portals_framebuffer")


timer.Remove("seamless_portal_distance_fix")
local function build_candidates(eye_pos, eye_ang, draw_distance)
    local candidates = {}
    for _, portal in ipairs(SeamlessPortals.Portals) do
        if SeamlessPortals.IsPortal(portal) then
            local exit = portal:GetExitPortal()
            if SeamlessPortals.IsUsableLink(portal, exit)
                and SeamlessPortals.ShouldRender(portal, eye_pos, eye_ang, draw_distance) then
                candidates[#candidates + 1] = {portal = portal, id = portal:EntIndex(),
                    distance = math.min(portal:GetPos():DistToSqr(eye_pos), exit:GetPos():DistToSqr(eye_pos))}
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.distance == b.distance then return a.id < b.id end
        return a.distance < b.distance
    end)
    return candidates
end

-- Oh boy... VVIS with renderview.. my favorite problem
-- When the virtual camera is inside of a wall, it will cause problems with PVS
	-- unrendering the map... turning off the skybox... etc.
-- this sucks! it ruins immersion and causes horrendous flashing
-- what we can do is set the actual RenderView origin inside the map, so PVS gets set up correctly
	-- and then modify the camera location afterwords with a 3d cam. context
-- Unfortunately, source doesn't make this process easy and camera contexts can ONLY be set up at specific times in the renderer

local clip_pos = Vector()
local clip_up = Vector()
local clip_offset = Vector()
local num_cam_3d = 0

local function push_cam(scale)
	cam.Start3D(renderview_table.origin - clip_offset * scale, renderview_table.angles, renderview_table.fov)
	num_cam_3d = num_cam_3d + 1
end

local function pop_cams()
	if !SeamlessPortals.Rendering then return end
	for _ = 1, num_cam_3d do
		cam.End3D()
	end

	num_cam_3d = 0
end

local skybox_info = nil
hook.Add("PreDrawSkyBox", "seamless_portals_renderview", function()
	if !SeamlessPortals.Rendering then return end

	render.EnableClipping(false) -- disable clipping in the skybox
	skybox_info = game.Get3DSkyboxInfo()
    if not skybox_info or not SeamlessPortals.IsFinite(skybox_info.scale) or skybox_info.scale<=0
        or not SeamlessPortals.FiniteVector(skybox_info.origin) then return end

	renderview_table.origin:Mul(1 / skybox_info.scale)
	renderview_table.origin:Add(skybox_info.origin)
	pop_cams()
	push_cam(1 / skybox_info.scale)
end)

hook.Add("PostDraw2DSkyBox", "seamless_portals_renderview", function()
    if SeamlessPortals.Rendering then SeamlessPortals.PortalSkySeen=true end
    pop_cams()
end)
hook.Add("SetupWorldFog", "seamless_portals_renderview", pop_cams)
hook.Add("PostDrawSkyBox", "seamless_portals_renderview", function()
	if !SeamlessPortals.Rendering then return end

	render.EnableClipping(true)
end)

local setup_world_fog_table = nil
local setup_world_fog_override = {[""] = function()
	pop_cams()

	-- emulate hook library
	hook.GetTable().SetupWorldFog = setup_world_fog_table
	return hook.Run("SetupWorldFog")
end}

-- The implementation of halos sucks.
-- We must disable clipping so that the framebuffer doesn't become corrupted
-- we only do this during portal rendering, so it shouldnt affect other operations,
-- since the clip state gets set back after rendering
hook.Add("PreDrawEffects", "seamless_portals_effects", function()
	if !SeamlessPortals.Rendering then return end

	render.EnableClipping(false)
end)

-- TODO: ideally we could "clip" the edges that we know are going to be discarded

local function render_scene()
    local old_clipping = render.EnableClipping(true)
    local plane_pushed = false
    local ok, err = xpcall(function()
        render.PushCustomClipPlane(clip_up, clip_up:Dot(clip_pos))
        plane_pushed = true
        push_cam(1)
        local render_view = render.RealRenderView or render.RenderView
        render_view(renderview_table)
    end, debug.traceback)
    pop_cams()
    if plane_pushed then render.PopCustomClipPlane() end
    render.EnableClipping(old_clipping)
    SeamlessPortals.Rendering = false
    if not ok then error(err, 0) end
end

local get_flashlight = include("cl_portal_flashlight.lua")
hook.Add("RenderScene", "seamless_portals_draw", function(eye_pos, eye_ang, fov)
	if not SeamlessPortals or SeamlessPortals.Rendering or #SeamlessPortals.Portals < 1 then return end

	local portal_render_max = math.max(0, max_render:GetInt())
	if portal_render_max == 0 then
		for _, portal in ipairs(SeamlessPortals.Portals) do
			if IsValid(portal) then portal.SEAMLESS_PORTALS_RENDERED = false end
		end
		return
	end
	SeamlessPortals.Frame = (SeamlessPortals.Frame + 1) % math.max(1, skip_frames:GetInt())
	if SeamlessPortals.Frame > 0 then return end

	for _, portal in ipairs(SeamlessPortals.Portals) do
		if IsValid(portal) then portal.SEAMLESS_PORTALS_RENDERED = false end
	end
	renderview_table.w, renderview_table.h = ScrW(), ScrH()

    local target_depth, main_camera = 0, false
    local flashlight
    local previous_rendering = SeamlessPortals.Rendering
    local function push_target(target)
        render.PushRenderTarget(target)
        target_depth = target_depth + 1
    end
    local function pop_target()
        render.PopRenderTarget()
        target_depth = target_depth - 1
    end
    local ok, err = xpcall(function()
	cam.Start3D(eye_pos, eye_ang, fov)
	main_camera = true
	push_target(SeamlessPortals.PortalRT)

	-- clear framebuffer (PortalRT) with 2d sky
	render.ClearDepth(true)

	flashlight = get_flashlight(eye_pos, eye_ang, "portal")
	local flashlight_pos = flashlight and flashlight:GetPos()
	local flashlight_ang = flashlight and flashlight:GetAngles()
	local portal_draw_distance = SeamlessPortals.GetDrawDistance()
	local portals_rendered = 0
	local pass_started, budget_ms = SysTime(), scene_budget:GetFloat()
	local candidates = build_candidates(eye_pos, eye_ang, portal_draw_distance)
	for _, candidate in ipairs(candidates) do
		local portal = candidate.portal
		if !IsValid(portal) then continue end

		local exit_portal = portal:GetExitPortal()
		if !IsValid(exit_portal) then continue end

		if budget_ms > 0 and portals_rendered > 0 and (SysTime() - pass_started) * 1000 >= budget_ms then break end
		if SeamlessPortals.ShouldRender(portal, eye_pos, eye_ang, portal_draw_distance) then
			local new_pos, new_ang = SeamlessPortals.TransformPortal(portal, exit_portal, eye_pos, eye_ang)
			clip_up:Set(exit_portal:GetUp())

			-- figure out where virtual camera VVIS should be set up. This is clamped within portal bounds
            local aperture_point=SeamlessPortals.ClosestAperturePoint(exit_portal,new_pos)
            -- Stay slightly inside a polygon edge instead of sampling a leaf in its frame.
            clip_pos:Set(LerpVector(0.995,exit_portal:GetPos(),aperture_point))
			clip_pos:Sub(clip_up)
			clip_offset:Set(clip_pos)
			clip_offset:Sub(new_pos)
			--debugoverlay.Sphere(clip_pos, 10, 0.05)

			renderview_table.origin:Set(clip_pos)
			renderview_table.angles:Set(new_ang)
			renderview_table.fov = fov
			renderview_table.drawviewer = SeamlessPortals.DrawPlayerInView and draw_viewer:GetBool()

			-- I NEED this hook to setup cams properly! No overriding allowed..
			local hook_table = hook.GetTable()
			setup_world_fog_table = hook_table.SetupWorldFog
			hook_table.SetupWorldFog = setup_world_fog_override

			if flashlight then
				local new_pos_fl, new_ang_fl = SeamlessPortals.TransformPortal(portal, exit_portal, flashlight_pos, flashlight_ang)
				flashlight:SetPos(new_pos_fl)
				flashlight:SetAngles(new_ang_fl)
				flashlight:Update()
			end

			push_target(framebuffer)
			SeamlessPortals.Rendering = exit_portal
            SeamlessPortals.PortalVirtualEye=Vector(new_pos)
            SeamlessPortals.PortalSkySeen=false
			portal.SEAMLESS_PORTALS_RENDERED = true
			render_scene()
			pop_target()

			if hook_table.SetupWorldFog == setup_world_fog_override then hook_table.SetupWorldFog = setup_world_fog_table end

			-- Draw quad reversed if the portal is linked to itself
			portal:DrawStenciled(framebuffer, portal == exit_portal, 1.01)

			portals_rendered = portals_rendered + 1
			if portals_rendered >= portal_render_max then
				break
			end
		end
	end

	SeamlessPortals.LastRenderStats = {scenes = portals_rendered, cpu_ms = (SysTime() - pass_started) * 1000,
		width = renderview_table.w, height = renderview_table.h, cap = portal_render_max, candidates = #candidates}
	if flashlight then
		SeamlessPortals.SuspendFlashlight("portal")
		flashlight = nil
	end

	pop_target()
	cam.End3D()
	main_camera = false
    end, debug.traceback)
    if hook.GetTable().SetupWorldFog == setup_world_fog_override then
        hook.GetTable().SetupWorldFog = setup_world_fog_table
    end
    pop_cams()
    SeamlessPortals.Rendering = previous_rendering
    SeamlessPortals.PortalVirtualEye=nil
    SeamlessPortals.PortalSkySeen=nil
    while target_depth > 0 do pop_target() end
    if main_camera then cam.End3D() end
    if flashlight then SeamlessPortals.SuspendFlashlight("portal") end
    if not ok then
        for _, portal in ipairs(SeamlessPortals.Portals) do
            if IsValid(portal) then portal.SEAMLESS_PORTALS_RENDERED = false end
        end
        ErrorNoHalt("[Seamless Portals] Render pass aborted: " .. tostring(err) .. "\n")
    end
end)

hook.Add("OnScreenSizeChanged", "seamless_portals_refresh_size", function()
    renderview_table.w, renderview_table.h = ScrW(), ScrH()
    SeamlessPortals.Frame = -1
end)
