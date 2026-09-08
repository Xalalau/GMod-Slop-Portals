-- The native laser predicts a straight trace inside every rendered view.
local SP = SeamlessPortals
if SP.CleanupRPGAimRendering then SP.CleanupRPGAimRendering() end
local state = {lasers = {}, paths = {}, drawPaths = {}, hidden = {}, count = 0}
SP.RPGAimRendering = state
local material = Material("sprites/redglow1")
local white = Color(255, 255, 255)
-- Native client entities can expose their C++ type name instead of the map class.
local classes = {env_laserdot = true, ["10C_LaserDot"] = true,
    C_LaserDot = true, ["class C_LaserDot"] = true}

function SP.PortalRPGAim(owner)
    if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() or owner:IsDormant()
        or not SP.TracePortalLine or not SP.HasTraversablePortals() then return end
    local weapon = owner:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass() ~= "weapon_rpg" then return end
    for _, name in ipairs({"seamless_portals_damage", "seamless_portals_projectiles"}) do
        local cv = GetConVar(name)
        if cv and not cv:GetBool() then return end
    end
    local origin = owner:GetShootPos()
    local trace = SP.TracePortalLine({start = origin, endpos = origin + owner:GetAimVector() * 56756,
        filter = {owner, weapon}, mask = bit.band(MASK_SHOT, bit.bnot(CONTENTS_WINDOW)),
        SeamlessFeature = "damage"})
    local segments = trace.SeamlessSegments
    local last = segments and segments[#segments]
    if not last or last.StartSolid or last.AllSolid then return end
    return {position = last.HitPos + last.HitNormal * 4,
        draw = last.Hit and not last.HitSky}
end

local function register(ent)
    if not IsValid(ent) or not classes[ent:GetClass()] or state.lasers[ent]
        or state.count >= 64 then return end
    state.lasers[ent] = {}
    state.count = state.count + 1
end
hook.Add("NetworkEntityCreated", "seamless_portals_rpg_aim", register)
hook.Add("EntityNetworkedVarChanged", "seamless_portals_rpg_aim", function(ent, key, _, value)
    if key == "seamless_portals_rpg_owner" and IsValid(value) then register(ent) end
end)
local pending, generation = 0, 0
hook.Add("OnEntityCreated", "seamless_portals_rpg_aim", function(ent)
    -- The C++ type can still be its base class during construction.
    if pending >= 64 then return end
    pending = pending + 1
    local version = generation
    timer.Simple(0, function()
        pending = pending - 1
        if version == generation then register(ent) end
    end)
end)
for class in pairs(classes) do
    for _, ent in ipairs(ents.FindByClass(class)) do register(ent) end
end

local function restoreHidden()
    for ent in pairs(state.hidden) do
        if IsValid(ent) and ent:GetNoDraw() then ent:SetNoDraw(false) end
    end
    state.hidden = {}
end
hook.Add("PostRender", "seamless_portals_rpg_aim", restoreHidden)

hook.Add("PreRender", "seamless_portals_rpg_aim", function()
    restoreHidden()
    state.paths, state.drawPaths = {}, {}
    local owners = {}
    for ent, record in pairs(state.lasers) do
        if not IsValid(ent) then
            state.lasers[ent] = nil
            state.count = state.count - 1
        elseif not ent:GetNoDraw() and not ent:IsDormant() then
            local nativeOwner = ent:GetOwner()
            if IsValid(nativeOwner) and nativeOwner:IsPlayer() then record.owner = nativeOwner end
            local guidanceOwner = ent:GetNWEntity("seamless_portals_rpg_owner")
            local owner = IsValid(guidanceOwner) and guidanceOwner or record.owner
            if IsValid(owner) then
                if owners[owner] == nil then owners[owner] = SP.PortalRPGAim(owner) or false end
                state.paths[ent] = owners[owner] or nil
                if state.paths[ent] then
                    -- Keep the same client aim point through the owner handoff.
                    state.drawPaths[owner] = state.paths[ent]
                    state.hidden[ent] = true
                    ent:SetNoDraw(true)
                end
            end
        end
    end
end)

-- Draw independently of the native dot's bounds in the entrance room, so the
-- exit view can see it even when that native entity is culled from this view.
hook.Add("PostDrawTranslucentRenderables", "seamless_portals_rpg_aim", function(depth, sky)
    if depth or sky then return end
    render.SetMaterial(material)
    for owner, path in pairs(state.drawPaths) do
        if IsValid(owner) and path.draw then
            render.DrawSprite(path.position, 16, 16, white)
        end
    end
end)

function SP.CleanupRPGAimRendering()
    generation = generation + 1
    restoreHidden()
    state.paths, state.drawPaths = {}, {}
    state.lasers, state.count = {}, 0
end
hook.Add("ShutDown", "seamless_portals_rpg_aim", SP.CleanupRPGAimRendering)
hook.Add("PostCleanupMap", "seamless_portals_rpg_aim", SP.CleanupRPGAimRendering)
