-- Bridge the native hull handoff with two clipped views of the same animation.
local SP = SeamlessPortals
local message = "seamless_portals_npc_transition"
local function writeVector(v)
    net.WriteFloat(v.x) net.WriteFloat(v.y) net.WriteFloat(v.z)
end
local function readVector()
    return Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
end

if SERVER then
    util.AddNetworkString(message)
    function SP.SendNPCTransition(npc, entry, exit, source, destination, angle)
        local lo, hi = npc:GetCollisionBounds()
        local center = (lo + hi) * 0.5
        local start = SP.TransformPortal(entry, exit, source + center) - center
        local offset = start - destination
        local speed = math.max(npc:GetIdealMoveSpeed(), 1)
        local duration = offset:Length2D() / speed
        if duration <= 0 or duration > 2 then return end
        local sequence = npc:GetSequence()
        local animation = {sequence = sequence, cycle = npc:GetCycle(), rate = npc:GetPlaybackRate(),
            distance = npc:GetSequenceGroundSpeed(sequence) * npc:SequenceDuration(sequence)}
        net.Start(message)
        net.WriteEntity(npc) net.WriteEntity(entry) net.WriteEntity(exit)
        writeVector(destination) writeVector(offset) writeVector(center)
        net.WriteAngle(angle)
        net.WriteFloat(CurTime())
        net.WriteFloat(duration)
        net.WriteUInt(sequence, 16)
        net.WriteFloat(animation.cycle)
        net.WriteFloat(animation.distance)
        net.Broadcast()
        animation.endCycle = animation.distance > 0 and (animation.cycle + offset:Length2D() / animation.distance) % 1 or animation.cycle
        return duration, animation
    end
    return
end

if SP.CleanupNPCTransitions then SP.CleanupNPCTransitions() end
SP.NPCTransitions = {}
local active = SP.NPCTransitions
local blendTime = 0.25

local function suppress(npc)
    local old = npc.RenderOverride
    local wrapper = function() end
    npc.RenderOverride = wrapper
    return {entity = npc, previous = old, wrapper = wrapper}
end

local function release(npc)
    local r = active[npc]
    if not r then return end
    for _, item in ipairs(r.handles) do
        if IsValid(item.entity) and item.entity.RenderOverride == item.wrapper then
            item.entity.RenderOverride = item.previous
        end
    end
    for _, model in ipairs(r.models) do if IsValid(model) then model:Remove() end end
    active[npc] = nil
end

local function copyModel(entity, parent, models)
    local model = ClientsideModel("models/props_junk/PopCan01a.mdl", RENDERGROUP_OPAQUE)
    if not model or not IsValid(model) then return end
    models[#models + 1] = model
    model:SetNoDraw(true)
    -- SetIK needs a model change after creation. The real NPC's foot targets
    -- must never be reused for drawing the other side of the portal.
    model:SetIK(false)
    model:SetModel(entity:GetModel())
    model:SetModelScale(entity:GetModelScale(), 0)
    model:SetSkin(entity:GetSkin())
    model:SetMaterial(entity:GetMaterial())
    model:SetColor(entity:GetColor())
    model:SetRenderMode(entity:GetRenderMode())
    for i = 0, math.min(entity:GetNumBodyGroups(), 32) - 1 do model:SetBodygroup(i, entity:GetBodygroup(i)) end
    for i = 0, math.min(#entity:GetMaterials(), 32) - 1 do model:SetSubMaterial(i, entity:GetSubMaterial(i)) end
    if parent then
        model:SetParent(parent)
        model:AddEffects(EF_BONEMERGE)
    end
    return model
end

local function blendBones(model, r, count)
    if not r.nativeBones or not r.blend or r.blend <= 0 then return end
    local bones, blended, visiting = {}, {}, {}
    for i = 0, math.min(count, 128) - 1 do
        if r.nativeBones[i] and model:GetBoneName(i) ~= "__INVALIDBONE__" then
            local matrix = model:GetBoneMatrix(i)
            if matrix then
                bones[i] = {matrix = matrix, position = matrix:GetTranslation(), angle = matrix:GetAngles()}
            end
        end
    end
    -- Blend relative to each joint. Averaging world-space bone positions
    -- shortens limbs when two gait phases bend a leg in different directions.
    local function blend(i)
        if blended[i] then return blended[i] end
        if not bones[i] or visiting[i] then return end
        visiting[i] = true
        local source, target = bones[i], r.nativeBones[i]
        local parent = model:GetBoneParent(i)
        local pose = bones[parent] and blend(parent)
        local sourcePos, sourceAngle, targetPos, targetAngle
        if pose then
            local from, to = bones[parent], r.nativeBones[parent]
            sourcePos, sourceAngle = WorldToLocal(source.position, source.angle, from.position, from.angle)
            targetPos, targetAngle = WorldToLocal(target.position, target.angle, to.position, to.angle)
        else
            pose = {position = model:GetPos(), angle = model:GetAngles()}
            sourcePos, sourceAngle = WorldToLocal(source.position, source.angle, pose.position, pose.angle)
            targetPos, targetAngle = target.position, target.angle
        end
        local pos, ang = LocalToWorld(LerpVector(r.blend, sourcePos, targetPos),
            LerpAngle(r.blend, sourceAngle, targetAngle), pose.position, pose.angle)
        local matrix = source.matrix
        matrix:SetTranslation(pos)
        matrix:SetAngles(ang)
        matrix:SetScale(LerpVector(r.blend, matrix:GetScale(), target.scale))
        model:SetBoneMatrix(i, matrix)
        blended[i] = {position = pos, angle = ang}
        visiting[i] = nil
        return blended[i]
    end
    for i = 0, math.min(count, 128) - 1 do blend(i) end
end

function SP.BeginNPCTransition(npc, entry, exit, destination, offset, center, angle, started, duration, animation)
    if not SP.IsLiveEntity(npc) or not npc:IsNPC() or not SP.LinkAllows(entry, exit, "props")
        or not SP.FiniteVector(destination) or not SP.FiniteVector(offset) or not SP.FiniteVector(center)
        or not SP.IsFinite(started) or not SP.IsFinite(duration) or duration <= 0 or duration > 2
        or CurTime() >= started + duration then return false end
    release(npc)
    local count = 0 for _ in pairs(active) do count = count + 1 end
    if count >= 32 then return false end
    local r = {entry = entry, exit = exit, destination = destination, offset = offset, center = center,
        angle = angle, started = started, duration = duration, geometry = SP.CaptureGeometry(entry),
        models = {}, handles = {}, modelName = npc:GetModel()}
    if animation and SP.IsFinite(animation.distance) and animation.distance > 0
        and SP.IsFinite(animation.cycle) and SP.IsFinite(animation.sequence)
        and animation.sequence >= 0 and animation.sequence < npc:GetSequenceCount() then
        r.animation = animation
    end
    active[npc] = r
    local ok, ready = pcall(function()
        local model = copyModel(npc, nil, r.models)
        if not model or not IsValid(model) then return false end
        model:AddCallback("BuildBonePositions", function(copy, count) blendBones(copy, r, count) end)
        r.handles[1] = suppress(npc)
        local weapon = npc:GetActiveWeapon()
        if IsValid(weapon) then
            if not IsValid(copyModel(weapon, model, r.models)) then return false end
            r.handles[2] = suppress(weapon)
        end
        return true
    end)
    if not ok or not ready then release(npc) return false end
    return ready
end

net.Receive(message, function()
    local npc, entry, exit = net.ReadEntity(), net.ReadEntity(), net.ReadEntity()
    local destination, offset, center = readVector(), readVector(), readVector()
    local angle, started, duration = net.ReadAngle(), net.ReadFloat(), net.ReadFloat()
    local animation = {sequence = net.ReadUInt(16), cycle = net.ReadFloat(), distance = net.ReadFloat()}
    SP.BeginNPCTransition(npc, entry, exit, destination, offset, center, angle, started, duration, animation)
end)

function SP.DrawNPCTransition(npc, r)
    local elapsed = CurTime() - r.started
    local fraction = math.Clamp(elapsed / r.duration, 0, 1)
    -- Native pursuit waits for this crossing, so its movement is not added to
    -- the traversal speed. The message also precedes some position snapshots.
    local position, angle = r.destination + r.offset * (1 - fraction), r.angle
    r.blend = math.Clamp((elapsed - r.duration) / blendTime, 0, 1)
    if r.blend > 0 then
        position, angle = npc:GetPos(), LerpAngle(r.blend, r.angle, npc:GetAngles())
    end
    local source, sourceAngle = SP.TransformPortal(r.exit, r.entry, position + r.center, angle)
    source = source - r.center
    local model = r.models[1]
    local clipping, pushed = render.EnableClipping(true), false
    local ok, err = xpcall(function()
        if r.animation then
            r.distance = r.offset:Length2D() * math.max(elapsed / r.duration, 0)
            local phase = (r.animation.cycle + r.distance / r.animation.distance) % 1
            model:SetSequence(r.animation.sequence)
            model:SetCycle(phase % 1)
        else
            model:SetSequence(npc:GetSequence())
            model:SetCycle(npc:GetCycle())
        end
        model:SetPlaybackRate(0)
        -- Blend to the engine's actual resumed pose, including a different
        -- walk sequence. Only the visual copy receives transformed bones.
        r.nativeBones = nil
        if r.blend > 0 then
            npc:SetupBones()
            r.nativeBones = {}
            for i = 0, math.min(npc:GetBoneCount(), 128) - 1 do
                local matrix = npc:GetBoneMatrix(i)
                if matrix then
                    local pos, ang = WorldToLocal(matrix:GetTranslation(), matrix:GetAngles(), npc:GetPos(), npc:GetAngles())
                    r.nativeBones[i] = {position = pos, angle = ang, scale = matrix:GetScale()}
                end
            end
        end
        for i = 0, math.min(npc:GetNumPoseParameters(), 24) - 1 do
            local name = npc:GetPoseParameterName(i)
            local lo, hi = npc:GetPoseParameterRange(i)
            model:SetPoseParameter(name, Lerp(npc:GetPoseParameter(name), lo, hi))
        end
        for _, pose in ipairs({{r.entry, source, sourceAngle}, {r.exit, position, angle}}) do
            local normal = pose[1]:GetUp()
            render.PushCustomClipPlane(normal, normal:Dot(pose[1]:GetPos())) pushed = true
            model:SetPos(pose[2]) model:SetAngles(pose[3])
            for _, copy in ipairs(r.models) do
                if IsValid(copy) then
                    copy:InvalidateBoneCache() copy:SetupBones()
                    copy:DrawModel()
                end
            end
            render.PopCustomClipPlane() pushed = false
        end
    end, debug.traceback)
    if pushed then render.PopCustomClipPlane() end
    render.EnableClipping(clipping)
    if not ok then release(npc) ErrorNoHalt("[Seamless Portals] NPC transition: " .. tostring(err) .. "\n") end
end

local function valid(npc, r)
    return SP.IsLiveEntity(npc) and npc:Health() > 0 and SP.LinkAllows(r.entry, r.exit, "props")
        and npc:GetModel() == r.modelName and IsValid(r.models[1])
        and SP.SameGeometry(r.geometry, SP.CaptureGeometry(r.entry)) and CurTime() < r.started + r.duration + blendTime
        and npc.RenderOverride == r.handles[1].wrapper
end
hook.Add("Think", "seamless_portals_npc_transition", function()
    for npc, r in pairs(active) do if not valid(npc, r) then release(npc) end end
end)
hook.Add("PostDrawOpaqueRenderables", "seamless_portals_npc_transition", function(depth, sky)
    if depth or sky then return end
    for npc, r in pairs(active) do
        if valid(npc, r) then SP.DrawNPCTransition(npc, r) else release(npc) end
    end
end)
function SP.CleanupNPCTransitions()
    for npc in pairs(active) do release(npc) end
end
hook.Add("PostCleanupMap", "seamless_portals_npc_transition", SP.CleanupNPCTransitions)
hook.Add("ShutDown", "seamless_portals_npc_transition", SP.CleanupNPCTransitions)
