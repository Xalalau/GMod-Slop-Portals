-- detours so stuff go through portals
AddCSLuaFile()

-- Shared, dynamically owned trace compatibility layer (C03).
AddCSLuaFile("seamless_portals/traces.lua")
include("seamless_portals/traces.lua")
AddCSLuaFile("seamless_portals/tool_effects.lua")
include("seamless_portals/tool_effects.lua")
AddCSLuaFile("seamless_portals/tracers.lua")
include("seamless_portals/tracers.lua")
AddCSLuaFile("seamless_portals/bullet_emitter.lua")
include("seamless_portals/bullet_emitter.lua")
AddCSLuaFile("seamless_portals/bullets.lua")
include("seamless_portals/bullets.lua")
AddCSLuaFile("seamless_portals/npc_transition.lua")
include("seamless_portals/npc_transition.lua")
if SERVER then
    include("seamless_portals/melee.lua")
    include("seamless_portals/blasts.lua")
    include("seamless_portals/projectiles.lua")
    include("seamless_portals/rpg_guidance.lua")
    include("seamless_portals/npc_awareness.lua")
end

AddCSLuaFile("seamless_portals/sound.lua")
include("seamless_portals/sound.lua")
AddCSLuaFile("seamless_portals/sound_loops.lua")
include("seamless_portals/sound_loops.lua")

AddCSLuaFile("seamless_portals/custom_defaults.lua")
include("seamless_portals/custom_defaults.lua")
