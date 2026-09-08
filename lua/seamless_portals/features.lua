-- C01: User-visible custom behavior, independent of the old SEv framework.
local SP = SeamlessPortals
SP.FeatureKeys = {
    props = {"disablePropTeleport", true, true},
    players = {"disablePlayerTeleport", true, true},
    damage = {"disableDamageTransfer", true, true},
    sound = {"disableSoundTransfer", true, true},
    funnel = {"enableFunneling", false, false},
}
function SP.FeatureEnabled(portal, name)
    local def = SP.FeatureKeys[name]
    if not def or not SP.IsPortal(portal) then return false end
    local fallback = def[2]
    if def[3] then fallback = not fallback end
    local value = portal:GetNWBool(def[1], fallback)
    if def[3] then return not value end
    return value
end
function SP.SetFeature(portal, name, enabled)
    if not SERVER or not SP.IsPortal(portal) or not isbool(enabled) then return false end
    local def = SP.FeatureKeys[name]
    if not def then return false end
    local stored = enabled
    if def[3] then stored = not enabled end
    portal:SetNWBool(def[1], stored)
    if name == "props" and not enabled and portal.DiscardTraversalState then portal:DiscardTraversalState() end
    if duplicator then
        local values = {}
        for key in pairs(SP.FeatureKeys) do values[key] = SP.FeatureEnabled(portal, key) end
        duplicator.StoreEntityModifier(portal, "seamless_portals_features", values)
    end
    return true
end
function SP.LinkAllows(entry, exit, feature)
    return SP.IsUsableLink(entry, exit) and SP.FeatureEnabled(entry, feature)
        and SP.FeatureEnabled(exit, feature)
end
function SP.RunSafeHook(name, ...)
    local args = {...}
    local ok, result = xpcall(function() return hook.Run(name, unpack(args)) end, debug.traceback)
    if not ok then ErrorNoHalt("[Seamless Portals] " .. name .. ": " .. tostring(result) .. "\n") end
    return ok, result
end
-- Called only for completed server transactions, never during predicted retries.
function SP.NotifyTraversal(ent, entry, exit, kind)
    for _, pair in ipairs({{entry, "OnTeleportFrom"}, {exit, "OnTeleportTo"}}) do
        if SP.IsPortal(pair[1]) and IsValid(ent) then
            local ok, err = xpcall(function() pair[1]:TriggerOutput(pair[2], ent) end, debug.traceback)
            if not ok then ErrorNoHalt("[Seamless Portals] output: " .. tostring(err) .. "\n") end
        end
    end
    if IsValid(ent) and ent:IsPlayer() then
        if SP.IsPortal(entry) and entry.RunPlyUsageCallbacks then
            local ok, err = xpcall(function() entry:RunPlyUsageCallbacks(ent, "entry", exit) end, debug.traceback)
            if not ok then ErrorNoHalt(tostring(err) .. "\n") end
        end
        if exit ~= entry and SP.IsPortal(exit) and exit.RunPlyUsageCallbacks then
            local ok, err = xpcall(function() exit:RunPlyUsageCallbacks(ent, "exit", entry) end, debug.traceback)
            if not ok then ErrorNoHalt(tostring(err) .. "\n") end
        end
    end
    SP.RunSafeHook("SeamlessPortalsTeleported", ent, entry, exit, kind)
end
if SERVER then
    duplicator.RegisterEntityModifier("seamless_portals_features", function(_, ent, data)
        if not istable(data) then return end
        for key, value in pairs(data) do if isbool(value) then SP.SetFeature(ent, key, value) end end
    end)
end
