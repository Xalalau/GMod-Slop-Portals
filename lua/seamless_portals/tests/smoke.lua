-- Run manually on a DEVELOPMENT server/client after applying the complete series.
-- This inherited smoke list does NOT cover every F00-F10 field-fix module.
-- Server: lua_openscript seamless_portals/tests/smoke.lua
-- Client: lua_openscript_cl seamless_portals/tests/smoke.lua
-- Compiles addon-owned files without executing their registration side effects.
local paths = {
    "autorun/000_seamless_portals_core.lua",
    "autorun/ai_tools_init.lua",
    "ai_tools/sh_error_capture.lua",
    "ai_tools/sh_menu_tests.lua",
    "ai_tools/sh_playground.lua",
    "ai_tools/sh_test_files.lua",
    "ai_tools/sh_workshop_inspector.lua",
    "ai_tools/sh_world_capture.lua",
    "autorun/client/cl_render_core.lua",
    "autorun/client/cl_seamless_effects.lua",
    "autorun/client/cl_seamless_rpg.lua",
    "autorun/client/cl_seamless_mirror_physgun.lua",
    "autorun/server/sv_portals_pvs.lua",
    "autorun/sh_detours.lua",
    "autorun/sh_player_teleport.lua",
    "autorun/sh_seamless_diagnostics.lua",
    "autorun/sh_seamless_tool_lights.lua",
    "cl_portal_flashlight.lua",
    "entities/seamless_portal/cl_init.lua",
    "entities/seamless_portal/init.lua",
    "entities/seamless_portal/sh_init.lua",
    "entities/seamless_portal_clone.lua",
    "entities/seamless_portal_cutout.lua",
    "seamless_portals/aperture.lua",
    "seamless_portals/blasts.lua",
    "seamless_portals/bullet_emitter.lua",
    "seamless_portals/carry.lua",
    "seamless_portals/crossing.lua",
    "seamless_portals/held_proxy.lua",
    "seamless_portals/remote_pickup.lua",
    "seamless_portals/melee.lua",
    "seamless_portals/gravitygun.lua",
    "seamless_portals/npc_awareness.lua",
    "seamless_portals/npc_navigation.lua",
    "seamless_portals/npc_transition.lua",
    "seamless_portals/projectiles.lua",
    "seamless_portals/properties.lua",
    "seamless_portals/rpg_guidance.lua",
    "seamless_portals/tracers.lua",
    "seamless_portals/bullets.lua",
    "seamless_portals/client_config.lua",
    "seamless_portals/core.lua",
    "seamless_portals/custom_defaults.lua",
    "seamless_portals/features.lua",
    "seamless_portals/funneling.lua",
    "seamless_portals/holding.lua",
    "seamless_portals/skybox.lua",
    "seamless_portals/sound.lua",
    "seamless_portals/tests/smoke.lua",
    "seamless_portals/tool_effects.lua",
    "seamless_portals/tool_features.lua",
    "seamless_portals/tool_trails.lua",
    "seamless_portals/traces.lua",
    "seamless_portals/transport.lua",
    "weapons/gmod_tool/stools/portal_behavior_tool.lua",
    "weapons/gmod_tool/stools/portal_creator_tool.lua",
    "weapons/gmod_tool/stools/portal_fitter_tool.lua",
    "weapons/gmod_tool/stools/portal_resizer_tool.lua",
    "weapons/portal_gun.lua",
}
local server_only = {
    ["seamless_portals/blasts.lua"] = true,
    ["seamless_portals/carry.lua"] = true,
    ["seamless_portals/held_proxy.lua"] = true,
    ["seamless_portals/remote_pickup.lua"] = true,
    ["seamless_portals/npc_awareness.lua"] = true,
    ["seamless_portals/npc_navigation.lua"] = true,
    ["seamless_portals/projectiles.lua"] = true,
    ["seamless_portals/properties.lua"] = true,
    ["seamless_portals/rpg_guidance.lua"] = true,
    ["autorun/server/sv_portals_pvs.lua"] = true,
    ["entities/seamless_portal/init.lua"] = true,
    ["entities/seamless_portal_cutout.lua"] = true,
    ["seamless_portals/transport.lua"] = true,
    ["seamless_portals/tool_trails.lua"] = true
}
for _, path in ipairs(paths) do
    if SERVER or not server_only[path] then
        local source = file.Read(path, "LUA")
        assert(source, "Missing source in this realm: " .. path)
        local compiled = CompileString(source, "@" .. path, false)
        assert(isfunction(compiled), tostring(compiled))
    end
end
local SP = SeamlessPortals
assert(SP.AI and SP.AI.LoadedAt, "Development helper loader did not run")
for name, method in pairs({ErrorCapture = "Install", Files = "Cleanup", WorldCapture = "CaptureEntity", Menu = "OpenTool", Workshop = "DownloadAndExtract"}) do
    assert(SP.AI[name] and isfunction(SP.AI[name][method]), "Missing AI helper API: " .. name .. "." .. method)
end
assert(SP.ValidateSides(3) and SP.ValidateSides(100))
assert(not SP.ValidateSides(0) and not SP.ValidateSides(3.5) and not SP.ValidateSides(math.huge))
assert(SP.ValidateSize(Vector(100, 100, 8)) and not SP.ValidateSize(Vector(0, 100, 8)))
assert(SP.AspectCompatibleSize(Vector(100, 50, 8), Vector(200, 100, 8)))
assert(not SP.AspectCompatibleSize(Vector(100, 50, 8), Vector(100, 100, 8)))
assert(SP.PatchSeriesCount == 94 and SP.CustomProposalCount == 15)
for _, name in ipairs({"FeatureEnabled", "InAperture", "TracePortalLine", "PortalBulletCallback", "GetHeldRecord", "ApplyFunneling", "SuppressPortalMeleeSound", "TraceGravityGun", "PuntThroughPortal", "GravityGunPuntFeedback", "SuppressPortalGravitySound", "PrepareGravityGunGrip", "RestoreGravityGunGrip"}) do
    assert(isfunction(SP[name]), "Missing inherited RC2 API: " .. name)
end
if SERVER then
    assert(isfunction(SP.ResetToolTrail), "Missing Trail Tool crossing adapter")
    assert(isfunction(SP.CanTargetPropertyThroughPortal), "Missing context-menu range adapter")
    for _,name in ipairs({"PlanTransport","CommitTransport","SnapshotDamage","CopyDamage","RelayBlast","RelayPortalMelee","TransferProjectile","UpdateRPGGuidance", "PullThroughPortal"}) do
        assert(isfunction(SP[name]),"Missing field API: "..name)
    end
    assert(isfunction(SP.UpdateNPCNavigation) and isfunction(SP.TransferNPCThroughPortal)
        and isfunction(SP.NPCPortalRoutePoints), "Missing NPC navigation API")
end
print("[Seamless Portals] Native GLua compile + pure smoke checks passed. Gameplay/rendering not tested.")
