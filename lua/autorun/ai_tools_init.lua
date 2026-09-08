-- Development utilities load in both realms; probes run only from the playground.
if SERVER then AddCSLuaFile() end

SeamlessPortals = SeamlessPortals or {}
local SP = SeamlessPortals
SP.AI = SP.AI or {}
local AI = SP.AI

local helpers = {
    "ai_tools/sh_test_files.lua",
    "ai_tools/sh_error_capture.lua",
    "ai_tools/sh_world_capture.lua",
    "ai_tools/sh_menu_tests.lua",
    "ai_tools/sh_workshop_inspector.lua"
}
local playground = "ai_tools/sh_playground.lua"

if SERVER then
    for _, path in ipairs(helpers) do AddCSLuaFile(path) end
    AddCSLuaFile(playground)
end

-- No entity/player access here, so console APIs also work after a loader hotload.
for _, path in ipairs(helpers) do include(path) end
AI.LoadedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
AI.Realm = SERVER and "server" or "client"

local function loadPlayground()
    AI.WorldReady = true
    if GAMEMODE and GAMEMODE.IsSandboxDerived then include(playground) end
end

hook.Remove("InitPostEntity", "seamless_ai_tool_sh_init")
hook.Add("InitPostEntity", "SEAMLESS_PORTALS_AI_Init", loadPlayground)
if AI.WorldReady then loadPlayground() end
