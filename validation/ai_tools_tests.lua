-- Run from the addon root: lua5.4 validation/ai_tools_tests.lua
-- Executes real helper sources with API doubles; this is not native GMod acceptance.
local root = arg[1] or "."
local passed = 0
local function test(name, callback)
    callback()
    passed = passed + 1
    print("PASS AI-" .. passed .. ": " .. name)
end

local function environment(server)
    local env = setmetatable({SERVER = server, CLIENT = not server}, {__index = _G})
    env._G = env
    env.print = function() end
    env.NBC = {AI = {untouched = true}}
    env.istable = function(value) return type(value) == "table" end
    env.IsValid = function(value) return type(value) == "table" and value.valid == true end
    env.game = {GetMap = function() return "gm_flatgrass" end}
    env.GAMEMODE = {IsSandboxDerived = true}
    env.hooks, env.timers, env.sent, env.includes = {}, {}, {}, {}
    env.hook = {
        Add = function(event, name, callback)
            env.hooks[event] = env.hooks[event] or {}
            env.hooks[event][name] = callback
        end,
        Remove = function(event, name)
            if env.hooks[event] then env.hooks[event][name] = nil end
        end
    }
    env.timer = {
        Create = function(name, _, _, callback) env.timers[name] = callback end,
        Remove = function(name) env.timers[name] = nil end
    }
    env.directories, env.written = {}, {}
    env.file = {
        CreateDir = function(path) env.directories[path] = true end,
        Exists = function() return false end,
        Write = function(path, content)
            assert(env.directories[path:match("^(.*)/[^/]+$")], "Parent not created: " .. path)
            env.written[path] = content
        end
    }
    env.util = {
        TableToJSON = function(value) env.lastJSON = value; return "json" end,
        AddNetworkString = function(name) env.networkString = name end
    }
    env.receivers = {}
    env.net = {
        Receive = function(name, callback) env.receivers[name] = callback end,
        ReadVector = function() return env.origin end,
        ReadFloat = function() return env.lifetime end
    }
    env.math = setmetatable({Clamp = function(n, lo, hi) return math.min(hi, math.max(lo, n)) end}, {__index = math})
    env.now = 10
    env.CurTime = function() return env.now end
    env.AddOriginToPVS = function(origin) env.visibleOrigin = origin end
    env.AddCSLuaFile = function(path)
        assert(server, "Client tried to send Lua")
        env.sent[path or "autorun/ai_tools_init.lua"] = true
    end
    env.include = function(path)
        if server and path:match("^ai_tools/") then assert(env.sent[path], "Include before send: " .. path) end
        env.includes[#env.includes + 1] = path
        return assert(loadfile(root .. "/lua/" .. path, "t", env))()
    end
    env.include("autorun/ai_tools_init.lua")
    return env, env.SeamlessPortals.AI
end

for _, server in ipairs({true, false}) do
    local realm = server and "server" or "client"
    local env, ai = environment(server)
    test(realm .. " startup loads idle APIs without touching NBC", function()
        assert(ai.LoadedAt and ai.Realm == realm)
        for _, name in ipairs({"Files", "ErrorCapture", "WorldCapture", "Menu", "Workshop"}) do assert(ai[name]) end
        assert(env.NBC.AI.untouched and next(env.NBC.AI, "untouched") == nil)
        assert(next(env.timers) == nil and next(env.written) == nil and next(env.receivers) == nil)
        assert(env.includes[#env.includes] == "ai_tools/sh_workshop_inspector.lua")
        env.hooks.InitPostEntity.SEAMLESS_PORTALS_AI_Init()
        assert(env.includes[#env.includes] == "ai_tools/sh_playground.lua")
        assert(next(env.written) == nil and next(env.timers) == nil)
    end)
    test(realm .. " error capture preserves state on reload and cleans its registrations", function()
        local capture = ai.ErrorCapture
        assert(capture.logPath == "seamless_tests/lua_errors_" .. realm .. ".json")
        capture.logPath = "seamless_tests/nested/" .. realm .. "/errors.json"
        capture.Install()
        env.hooks.OnLuaError[capture.hookName]("sentinel", realm, {{File = "probe.lua", Line = 3}}, "seamless", "0")
        env.include("autorun/ai_tools_init.lua")
        assert(env.SeamlessPortals.AI == ai and ai.ErrorCapture == capture)
        assert(capture.errors.sentinel.quantity == 1)
        capture.Flush(true)
        assert(env.written[capture.logPath] and env.lastJSON.realms[realm].errors.sentinel)
        capture.Cleanup()
        assert(env.hooks.OnLuaError[capture.hookName] == nil and env.timers[capture.flushTimer] == nil)
    end)
end

local env, ai = environment(true)
test("PVS is explicit, validates admin input, expires and cleans up", function()
    local capture = ai.WorldCapture
    capture.InstallPVS()
    local receive = assert(env.receivers[capture.netPVS])
    local ply = {valid = true, IsAdmin = function() return false end}
    env.origin, env.lifetime = {x = 1, y = 2, z = 3}, 20
    receive(128, ply)
    assert(next(capture.pvsOrigins) == nil)
    ply.IsAdmin = function() return true end
    env.origin.x = 0 / 0
    receive(128, ply)
    assert(next(capture.pvsOrigins) == nil)
    env.origin.x = 40000
    receive(128, ply)
    assert(next(capture.pvsOrigins) == nil)
    env.origin.x = 1
    receive(128, ply)
    local state = assert(capture.pvsOrigins[ply])
    assert(state.expires == 13)
    receive(128, ply)
    assert(capture.pvsOrigins[ply] == state)
    env.hooks.SetupPlayerVisibility[capture.pvsHookName](ply)
    assert(env.visibleOrigin == env.origin)
    env.now = 14
    env.hooks.SetupPlayerVisibility[capture.pvsHookName](ply)
    assert(capture.pvsOrigins[ply] == nil)
    capture.Cleanup()
    receive(128, ply)
    assert(next(capture.pvsOrigins) == nil)
    assert(env.hooks.SetupPlayerVisibility[capture.pvsHookName] == nil)
    assert(env.hooks.PlayerDisconnected[capture.pvsHookName] == nil)
end)

env, ai = environment(false)
test("Menu opens a portal tool and rejects a stale or missing panel", function()
    local name = "portal_behavior_tool"
    local panel = {valid = true, GetInitialized = function() return true end, GetClassName = function() return "ControlPanel" end}
    env.g_SpawnMenu = {valid = true}
    env.spawnmenu = {
        GetTools = function() return {{Name = "Main", Items = {{{ItemName = name, Text = "Portal Behavior"}}}}} end,
        ActivateTool = function(tool, menuOnly) assert(tool == name and menuOnly) end,
        ActiveControlPanel = function() return panel end
    }
    env.controlpanel = {Get = function(tool) assert(tool == name); return panel end}
    env.gui = {MouseX = function() return 0 end, MouseY = function() return 0 end}
    env.RunConsoleCommand = function(command) assert(command == "+menu") end
    local menu = ai.Menu
    assert(menu.OpenTool(name, {enableCursor = false, moveCursor = false}))
    env.timers[menu.openTimer]()
    env.timers[menu.activateTimer]()
    env.timers[menu.finishTimer]()
    assert(menu.lastResult.opened and menu.lastResult.item_name == name)
    env.spawnmenu.ActiveControlPanel = function() return {valid = true} end
    menu.OpenTool(name, {enableCursor = false, moveCursor = false})
    env.timers[menu.openTimer]()
    env.timers[menu.activateTimer]()
    assert(menu.lastResult.error and not menu.lastResult.opened)
    menu.OpenTool("missing_tool")
    env.timers[menu.openTimer]()
    assert(menu.lastResult.error and not menu.lastResult.found)
    menu.Cleanup()
    assert(next(env.timers) == nil)
end)
print(passed .. " helper checks passed; NOT native GMod.")
