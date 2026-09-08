AddCSLuaFile()
AddCSLuaFile("cl_portal_flashlight.lua")

local function too_fast(vel)
	return vel:LengthSqr() > 1000 * 1000
end

-- TODO: figure out the correct mask for this..
local portal_trace_data = {
	filter = function(e) return e:GetClass() == "seamless_portal" end,
	ignoreworld = true,
	mask = MASK_PLAYERSOLID
}

-- hull modifier (so we can enter floor/ground)
local function get_hull(ply)
	local mins, maxs
	if ply.SEAMLESS_PORTALS_HULL_MINS then
		mins, maxs = Vector(ply.SEAMLESS_PORTALS_HULL_MINS), Vector(ply.SEAMLESS_PORTALS_HULL_MAXS)
	else
		mins, maxs = ply:GetHull()
	end

	local scale = ply:GetModelScale()
	mins:Mul(scale)
	maxs:Mul(scale)

	return mins, maxs
end

local function get_hull_duck(ply)
	local mins, maxs
	if ply.SEAMLESS_PORTALS_HULL_DUCK_MINS then
		mins, maxs = Vector(ply.SEAMLESS_PORTALS_HULL_DUCK_MINS), Vector(ply.SEAMLESS_PORTALS_HULL_DUCK_MAXS)
	else
		mins, maxs = ply:GetHullDuck()
	end

	local scale = ply:GetModelScale()
	mins:Mul(scale)
	maxs:Mul(scale)

	return mins, maxs
end

local function invalidate_hull(ply)
	if ply.SEAMLESS_PORTALS_HULL_MINS then return end

	ply.SEAMLESS_PORTALS_HULL_MINS, ply.SEAMLESS_PORTALS_HULL_MAXS = ply:GetHull()
	ply.SEAMLESS_PORTALS_HULL_DUCK_MINS, ply.SEAMLESS_PORTALS_HULL_DUCK_MAXS = ply:GetHullDuck()
	for _, name in ipairs({"MINS", "MAXS", "DUCK_MINS", "DUCK_MAXS"}) do
		local key = "SEAMLESS_PORTALS_HULL_" .. name
		ply[key] = Vector(ply[key])
	end
end

local function validate_hull(ply)
	if !ply.SEAMLESS_PORTALS_HULL_MINS then return false end

	local mins, maxs = ply:GetHull()
	local duck_mins, duck_maxs = ply:GetHullDuck()
	local own = ply.SEAMLESS_PORTALS_LAST_HULL
	-- Do not overwrite a newer hull installed by another addon.
	if not own or (mins == own[1] and maxs == own[2]) then
		ply:SetHull(Vector(ply.SEAMLESS_PORTALS_HULL_MINS), Vector(ply.SEAMLESS_PORTALS_HULL_MAXS))
	end
	if not own or (duck_mins == own[3] and duck_maxs == own[4]) then
		ply:SetHullDuck(Vector(ply.SEAMLESS_PORTALS_HULL_DUCK_MINS), Vector(ply.SEAMLESS_PORTALS_HULL_DUCK_MAXS))
	end
	ply.SEAMLESS_PORTALS_LAST_HULL = nil

	ply.SEAMLESS_PORTALS_HULL_MINS = nil
	ply.SEAMLESS_PORTALS_HULL_MAXS = nil
	ply.SEAMLESS_PORTALS_HULL_DUCK_MINS = nil
	ply.SEAMLESS_PORTALS_HULL_DUCK_MAXS = nil

	return true
end

local function is_hull_invalid(ply)
	return ply.SEAMLESS_PORTALS_HULL_MINS and true or false
end

local function get_hull_clip(hull_mins, hull_maxs)
	for i = 1, 2 do
		hull_mins[i] = math.max(hull_mins[i] / 4, -4)
		hull_maxs[i] = math.min(hull_maxs[i] / 4, 4)
	end

	hull_maxs[3] = hull_maxs[3] * 0.9
end

-- hull stand and hull duck must be calculated separately
local function clip_hull(ply, hull_mins, hull_maxs, half)
	--local hull_mins, hull_maxs = get_hull(ply) -- pass in to avoid gc spaz (-2 vectors)
	get_hull_clip(hull_mins, hull_maxs)

	local hull_duck_mins, hull_duck_maxs = get_hull_duck(ply)
	get_hull_clip(hull_duck_mins, hull_duck_maxs)

	if half then
		local thickness = math.max(0.01, 0.01 * ply:GetModelScale())
		hull_mins[3] = math.max(hull_mins[3], hull_maxs[3] - thickness)
		hull_duck_mins[3] = math.max(hull_duck_mins[3], hull_duck_maxs[3] - thickness)
	end

	for i = 1, 3 do
		if not SeamlessPortals.IsFinite(hull_mins[i]) or not SeamlessPortals.IsFinite(hull_maxs[i])
			or not SeamlessPortals.IsFinite(hull_duck_mins[i]) or not SeamlessPortals.IsFinite(hull_duck_maxs[i])
			or hull_mins[i] >= hull_maxs[i] or hull_duck_mins[i] >= hull_duck_maxs[i] then
			validate_hull(ply)
			return false
		end
	end
	ply:SetHull(hull_mins, hull_maxs)
	ply:SetHullDuck(hull_duck_mins, hull_duck_maxs)
	ply.SEAMLESS_PORTALS_LAST_HULL = {
		Vector(hull_mins), Vector(hull_maxs), Vector(hull_duck_mins), Vector(hull_duck_maxs)
	}

	--debugoverlay.Box(ply:GetPos(), hull_mins, hull_maxs, 0.5, Color(255, 0, 0, 0))
end

local function update_hull(ply, ply_pos)
	local own = ply.SEAMLESS_PORTALS_LAST_HULL
	if own then
		local a, b = ply:GetHull()
		local c, d = ply:GetHullDuck()
		if a ~= own[1] or b ~= own[2] or c ~= own[3] or d ~= own[4] then
			validate_hull(ply) -- release old ownership before capturing a new baseline
		end
	end
	-- no need to modify hull if we're in noclip
	if ply:GetMoveType() == MOVETYPE_NOCLIP then
		validate_hull(ply)
		return
	end

	local hull_mins, hull_maxs = get_hull(ply)
	portal_trace_data.start = ply_pos
	portal_trace_data.endpos = ply_pos
	portal_trace_data.mins = hull_mins
	portal_trace_data.maxs = hull_maxs
	local tr_hull = util.TraceHull(portal_trace_data)
	if !tr_hull.Hit then
		if is_hull_invalid(ply) then
			-- Test the supplied predicted/destination position, not an unrelated entity origin.
			if util.TraceHull({
				start = ply_pos,
				endpos = ply_pos,
				mins = hull_mins,
				maxs = hull_maxs,
				filter = ply,
				mask = MASK_PLAYERSOLID,
				collisiongroup = COLLISION_GROUP_PLAYER
			}).Hit
			then
				-- shit. We're stuck
				clip_hull(ply, hull_mins, hull_maxs, false) -- back to standing
				return true -- let movement code try to extrude player
			end
		end

		return validate_hull(ply)
	end

	local portal = tr_hull.Entity
	if not SeamlessPortals.IsPortal(portal)
        or not SeamlessPortals.LinkAllows(portal, portal:GetExitPortal(), "players") then
        return validate_hull(ply)
    end

	-- we're about to change hull
	invalidate_hull(ply)

	-- floor portal mode. yikes.
	local half = portal:GetUp():Dot(Vector(0, 0, 1)) > 0.5
	if half then
		portal_trace_data.start = ply_pos + Vector(0, 0, hull_maxs[3])
		portal_trace_data.endpos = ply_pos + Vector(0, 0, hull_mins[3])

		local tr_ground = SeamlessPortals.TraceLine(portal_trace_data)
		half = tr_ground.Hit and !tr_ground.StartSolid
	end

	clip_hull(ply, hull_mins, hull_maxs, half)

	if half then
		ply:SetGroundEntity(nil)
	end

	return true
end

-- TODO: extrude on sides too so we dont get stuck in a wall
local function extrude_player(ply, ply_pos)
	if ply:GetMoveType() == MOVETYPE_NOCLIP then
		return false
	end

	local mins, maxs = (ply:Crouching() and ply.GetHullDuck or ply.GetHull)(ply)
	local max_diff = maxs[3] - mins[3]
	if max_diff <= 0 then return false end

	mins:Mul(0.999)
	maxs:Mul(0.999)
	mins[3] = maxs[3]

	local tr_ground = util.TraceHull({
		start = ply_pos,
		endpos = ply_pos - Vector(0, 0, maxs[3]),
		mins = mins,
		maxs = maxs,
		filter = ply,
		mask = MASK_PLAYERSOLID,
		collisiongroup = COLLISION_GROUP_PLAYER
	})

	if !tr_ground.StartSolid and tr_ground.Hit then
		ply_pos[3] = ply_pos[3] + math.min((1 - tr_ground.Fraction) * maxs[3], max_diff)
		return true
	end

	return false
end

-- client lerp prevention
local get_flashlight = CLIENT and include("cl_portal_flashlight.lua")
local saved_flashlight_color, flashlight_owner
SeamlessPortals.GetSavedFlashlightColor = function() return saved_flashlight_color end
local function restore_flashlight_color()
    if IsValid(flashlight_owner) and saved_flashlight_color then
        local now = flashlight_owner:GetFlashlightColor()
        -- Black is the temporary value this addon owns; preserve newer external colors.
        if now.r == 0 and now.g == 0 and now.b == 0 then
            flashlight_owner:SetFlashlightColor(saved_flashlight_color)
        end
    end
    saved_flashlight_color, flashlight_owner = nil, nil
end
local flashlight = nil -- flashlight will flicker going through (because of player lerp).. create a temporary fake one
local transition_revision = 0
local function lerp_teleport(start_pos, start_vel, transition)
	if not IsValid(LocalPlayer()) then return end
	transition_revision = transition_revision + 1
	local revision = transition_revision
	SeamlessPortals.Frame = -1 -- force render after a teleport to avoid flashing

	-- reset values after teleport
	timer.Create("seamless_portals_lerp_teleport", 0.3, 1, function()
		if revision ~= transition_revision then return end
		SeamlessPortals.DrawPlayerInView = true
		hook.Remove("CalcView", "seamless_portals_lerp_teleport")
		hook.Remove("CalcViewModelView", "seamless_portals_lerp_teleport")
		hook.Remove("GetMotionBlurValues", "seamless_portals_lerp_teleport")

		-- reset roll / flashlight
		local ply = LocalPlayer()
		restore_flashlight_color()
		if not IsValid(ply) then
			if flashlight then SeamlessPortals.ReleaseFlashlight("transition") flashlight = nil end
			return
		end
		local ang = ply:EyeAngles() ang[3] = 0
		ply:SetEyeAngles(ang)
		if flashlight then SeamlessPortals.ReleaseFlashlight("transition") flashlight = nil end
	end)

	local ply = LocalPlayer()
	if ply:GetViewEntity() != ply then -- viewing from a camera, no need to lerp
		return
	end

	SeamlessPortals.DrawPlayerInView = false
	start_pos = Vector(start_pos) -- this will be self-modified

	-- need for frame interp. noticable flashing over this speed. Hacky
	-- TODO: is this fixable?
	if !too_fast(start_vel) then
		start_pos:Sub(start_vel * FrameTime())
	end

	local bridge_seconds = math.Clamp(ply:Ping() * 0.001 + engine.TickInterval() * 2, 0.03, 0.25)
    local weapon_pos = Vector(start_pos)
	local total_frame_time = 0
	local last_interpolation_frame = -1
	hook.Add("CalcView", "seamless_portals_lerp_teleport", function(_, pos, ang)
		if revision ~= transition_revision or not IsValid(ply) then return end
		if ply:GetViewEntity() ~= ply then restore_flashlight_color() SeamlessPortals.ReleaseFlashlight("transition") flashlight = nil return end
		local frame_time = last_interpolation_frame == FrameNumber() and 0 or FrameTime()
		last_interpolation_frame = FrameNumber()
		ang[3] = ang[3] * math.pow(math.max(0.3 - total_frame_time, 0) / 0.3, 3)

		-- prevents client from seeing small jitter during teleport with portals on differing heights (hack..)
		pos:Set(ply:EyePos())

		-- in my testing, lerp from positions takes roughly 0.03 seconds
		-- which means we need to fake our velocity for a tiny bit
		if total_frame_time < bridge_seconds and not (transition and transition.acknowledged) then
			start_pos:Add(ply:GetVelocity() * frame_time)
			pos:Set(start_pos)
		elseif !SeamlessPortals.DrawPlayerInView then
			SeamlessPortals.DrawPlayerInView = true
			hook.Remove("GetMotionBlurValues", "seamless_portals_lerp_teleport")
		end

		if not saved_flashlight_color then
			local color = ply:GetFlashlightColor()
			saved_flashlight_color = Color(color.r, color.g, color.b, color.a)
			flashlight_owner = ply
		end
		ply:SetFlashlightColor(Color(0, 0, 0))
		flashlight = get_flashlight(pos, ang, "transition")
		if flashlight then flashlight:Update() end

		weapon_pos:Set(pos)

		total_frame_time = total_frame_time + frame_time
	end)

	hook.Add("CalcViewModelView", "seamless_portals_lerp_teleport", function(_, _, old_pos, _, pos, ang)
		if revision ~= transition_revision or not IsValid(ply) then return end
		--pos:Sub(old_pos)
		--pos:Add(weapon_pos)
		pos:Set(weapon_pos)
		ang[3] = ang[3] * math.pow(math.max(0.3 - total_frame_time, 0) / 0.3, 3)
	end)

	-- >:)
	hook.Add("GetMotionBlurValues", "seamless_portals_lerp_teleport", function(h, v, f, r)
		return 0, 0, 0, 0
	end)
end

hook.Add("Move", "seamless_portal_teleport", function(ply, mv)
	if SeamlessPortals.RecordMovement then SeamlessPortals.RecordMovement(ply, mv, "input") end
	if !SeamlessPortals or #SeamlessPortals.Portals < 1 then
		validate_hull(ply)
		return
	end

	SeamlessPortals.ApplyFunneling(ply,mv,engine.TickInterval())
	local ply_eyepos = mv:GetOrigin() + ply:GetCurrentViewOffset() -- predicted origin, not a stale entity pose
	local ply_vel = mv:GetVelocity()
	local ply_vel_offset = ply_vel * engine.TickInterval()

	-- update_hull will return true if we might need to do a ground extrusion
	local ply_pos = mv:GetOrigin()
	if update_hull(ply, ply_pos + ply_vel_offset) then
		if extrude_player(ply, ply_pos) then
			mv:SetOrigin(ply_pos)
		end
	end

	-- teleportation logic
	portal_trace_data.start = ply_eyepos
	portal_trace_data.endpos = ply_eyepos + ply_vel_offset
	portal_trace_data.ignoreworld = false
	local tr = SeamlessPortals.TraceLine(portal_trace_data)
	portal_trace_data.ignoreworld = true
	if !tr.Hit then return end

	local portal = tr.Entity -- might be world, but IsValid will catch it
	if not SeamlessPortals.IsPortal(portal) or portal:GetUp():Dot(ply_vel) >= 0 then return end -- not going into portal

	local exit_portal = portal:GetExitPortal()
	if not SeamlessPortals.LinkAllows(portal, exit_portal, "players") then return end

	local hit_pos = portal_trace_data.endpos
	if too_fast(ply_vel) then
		hit_pos = tr.HitPos
	end

	local new_ply_eyepos, new_ply_ang = SeamlessPortals.TransformPortal(portal, exit_portal, hit_pos, ply:EyeAngles())
	local new_ply_vel = SeamlessPortals.TransformDirection(portal, exit_portal, ply_vel, false):GetNormalized()
	new_ply_vel:Mul(math.max(
		ply_vel:Length(),
		exit_portal:GetUp():Dot(-physenv.GetGravity() / 2) -- minimum velocity (to prevent fast in/out movement)
	))

	local ratio = exit_portal:GetSize()[1] / portal:GetSize()[1]
	new_ply_vel:Mul(ratio)

	local new_ply_pos = ply:GetCurrentViewOffset()
	new_ply_pos:Negate()
	new_ply_pos:Add(new_ply_eyepos)

    -- Compute destination extrusion BEFORE moving the held assembly, so all
    -- objects receive the same player-space displacement.
    update_hull(ply, new_ply_pos)
    extrude_player(ply, new_ply_pos)
    new_ply_eyepos = new_ply_pos + ply:GetCurrentViewOffset()
    local hold = SeamlessPortals.GetHeldRecord(ply)
    local transport
    if hold then
        if not SeamlessPortals.SupportsPropTraversal(portal, exit_portal) then
            return SeamlessPortals.BlockHeldTraversal(ply,mv,portal,"held_props_disabled_or_mirror")
        end
        if SERVER then
            local reason
            transport, reason = SeamlessPortals.PlanTransport(hold.entity,portal,exit_portal,ply,ply_eyepos,new_ply_eyepos)
            if not transport then return SeamlessPortals.BlockHeldTraversal(ply,mv,portal,reason) end
            new_ply_pos:Add(transport.offset)
            new_ply_eyepos:Add(transport.offset)
            local ok
            ok, reason = SeamlessPortals.CommitTransport(transport)
            if not ok then return SeamlessPortals.BlockHeldTraversal(ply,mv,portal,reason) end
        end
    end
    -- Preserve the native grab controller. No DropObject, ForcePlayerDrop,
    -- PickupObject, recreated original PhysObj, or permission bypass is used.
    mv:SetOrigin(new_ply_pos)
    mv:SetVelocity(new_ply_vel)
    ply:SetGroundEntity(nil)
    if CLIENT then
        if IsFirstTimePredicted() then
            ply:SetEyeAngles(new_ply_ang)
            local cmd=ply:GetCurrentCommand()
            local transition={entry=portal,exit=exit_portal,command=cmd and cmd:CommandNumber() or 0,time=RealTime()}
            SeamlessPortals.PendingTransition=transition
            lerp_teleport(new_ply_eyepos,new_ply_vel,transition)
            if portal == exit_portal then SeamlessPortals.ToggleMirror(not SeamlessPortals.ToggleMirror()) end
        end
    else
        -- The native physgun target uses player view space: update it on the
        -- authoritative server too, rather than only in singleplayer.
        ply:SetEyeAngles(new_ply_ang)
        if game.SinglePlayer() then
            net.Start("SEAMLESS_PORTALS_FIX_SINGLEPLAYER")
            net.WriteVector(new_ply_eyepos) net.WriteVector(new_ply_vel)
            net.WriteBool(portal == exit_portal)
            net.Send(ply)
        end
        ply:SetNWInt("desired_size",ply:GetNWInt("desired_size",100)*ratio)
        if not game.SinglePlayer() then
            ply.SEAMLESS_PORTALS_ACK_SEQUENCE=(ply.SEAMLESS_PORTALS_ACK_SEQUENCE or 0)+1
            if portal==exit_portal then ply.SEAMLESS_PORTALS_MIRRORED=not ply.SEAMLESS_PORTALS_MIRRORED end
            local cmd=ply:GetCurrentCommand()
            net.Start("SEAMLESS_PORTALS_TRANSITION_ACK_V2")
            net.WriteUInt(ply.SEAMLESS_PORTALS_ACK_SEQUENCE % 4294967296,32)
            net.WriteUInt(cmd and cmd:CommandNumber() or 0,32)
            net.WriteEntity(portal) net.WriteEntity(exit_portal)
            net.WriteVector(new_ply_eyepos) net.WriteVector(new_ply_vel) net.WriteAngle(new_ply_ang)
            net.WriteBool(ply.SEAMLESS_PORTALS_MIRRORED or false)
            net.Send(ply)
        end
        if transport then
            if SeamlessPortals.FinishHeldTraversal then SeamlessPortals.FinishHeldTraversal(ply,hold) end
            SeamlessPortals.AuditHeldTransport(ply,hold,transport)
            SeamlessPortals.NotifyTransport(transport,"held_"..hold.kind)
        end
        SeamlessPortals.NotifyTraversal(ply,portal,exit_portal,"player")
    end
    if SeamlessPortals.RecordMovement then SeamlessPortals.RecordMovement(ply,mv,"teleported") end

	return true
end)

-- singleplayer hack
if game.SinglePlayer() then
	if SERVER then
		util.AddNetworkString("SEAMLESS_PORTALS_FIX_SINGLEPLAYER")
	else
		net.Receive("SEAMLESS_PORTALS_FIX_SINGLEPLAYER", function()
			lerp_teleport(net.ReadVector(), net.ReadVector())

			if net.ReadBool() then
				SeamlessPortals.ToggleMirror(!SeamlessPortals.ToggleMirror())
			end
		end)
	end
end

SeamlessPortals.RestorePlayerHull = validate_hull
for _, event in ipairs({"PlayerDeath", "PlayerSilentDeath", "PlayerSpawn"}) do
    hook.Add(event, "seamless_portals_restore_hull", function(ply)
        if IsValid(ply) then validate_hull(ply) end
    end)
end
hook.Add("ShutDown", "seamless_portals_restore_hulls", function()
    for _, ply in ipairs(player.GetAll()) do validate_hull(ply) end
end)

if CLIENT then
    hook.Add("ShutDown", "seamless_portals_restore_flashlight", restore_flashlight_color)
end

-- Acknowledgment is cosmetic reconciliation, not client authority over teleporting.
if SERVER then
    util.AddNetworkString("SEAMLESS_PORTALS_TRANSITION_ACK_V2")
else
    local last_sequence=0
    net.Receive("SEAMLESS_PORTALS_TRANSITION_ACK_V2",function()
        local sequence,command=net.ReadUInt(32),net.ReadUInt(32)
        local entry,exit=net.ReadEntity(),net.ReadEntity()
        local eye,vel,ang=net.ReadVector(),net.ReadVector(),net.ReadAngle()
        local mirrored=net.ReadBool()
        if sequence<=last_sequence then return end
        last_sequence=sequence
        if not SeamlessPortals.FiniteVector(eye) or not SeamlessPortals.FiniteVector(vel) then return end
        local pending=SeamlessPortals.PendingTransition
        if pending and command>0 and pending.command>command then return end -- newer prediction owns the view
        local matched=pending and pending.entry==entry and pending.exit==exit
            and (command==0 or command==pending.command) and RealTime()-pending.time<1
        if matched then
            pending.acknowledged=true
        else
            local ply=LocalPlayer()
            if IsValid(ply) then ply:SetEyeAngles(ang) end
            lerp_teleport(eye,vel,{acknowledged=true})
        end
        SeamlessPortals.ToggleMirror(mirrored) -- absolute state, never a second blind toggle
        SeamlessPortals.PendingTransition=nil
    end)
end
