AddCSLuaFile("seamless_portals/core.lua")
include("seamless_portals/core.lua")

if SERVER then include("seamless_portals/transport.lua") end

AddCSLuaFile("seamless_portals/holding.lua")
include("seamless_portals/holding.lua")
if SERVER then
    include("seamless_portals/carry.lua")
    include("seamless_portals/held_proxy.lua")
    include("seamless_portals/physgun_pickup.lua")
end

AddCSLuaFile("seamless_portals/funneling.lua")
include("seamless_portals/funneling.lua")

AddCSLuaFile("seamless_portals/skybox.lua")

AddCSLuaFile("seamless_portals/tool_features.lua")
include("seamless_portals/tool_features.lua")
