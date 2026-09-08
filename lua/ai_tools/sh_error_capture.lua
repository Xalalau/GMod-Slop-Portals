-- AI helper functions for temporary Lua error capture. Loaded by the addon, idle until called.

SeamlessPortals = SeamlessPortals or {}
local SP = SeamlessPortals
SP.AI = SP.AI or {}

local ErrorCapture = SP.AI.ErrorCapture or {
    logPath = "seamless_tests/lua_errors_" .. (SERVER and "server" or "client") .. ".json",
    hookName = "SEAMLESS_PORTALS_AI_CaptureLuaErrors",
    flushTimer = "SEAMLESS_PORTALS_AI_FlushLuaErrors",
    errors = {},
    dirty = false,
    flushes = 0
}

SP.AI.ErrorCapture = ErrorCapture

local function realmName()
    return SERVER and "server" or "client"
end

local function internalError(err)
    print("[Seamless Portals AI] internal error capture failure: " .. tostring(err))
end

local function stackToLines(stack)
    local lines = {}

    if istable(stack) then
        for index, frame in ipairs(stack) do
            if index > 16 then break end

            if istable(frame) then
                lines[#lines + 1] = tostring(frame.File or "") .. ":" .. tostring(frame.Line or "") .. " " .. tostring(frame.Function or "")
            else
                lines[#lines + 1] = tostring(frame)
            end
        end
    end

    return lines
end

local function readLog()
    if not file.Exists(ErrorCapture.logPath, "DATA") then
        return { realms = {}, tests = {} }
    end

    local raw = file.Read(ErrorCapture.logPath, "DATA") or ""
    local ok, decoded = pcall(util.JSONToTable, raw)

    if ok and istable(decoded) then
        decoded.realms = decoded.realms or {}
        decoded.tests = decoded.tests or {}
        return decoded
    end

    return { realms = {}, tests = {} }
end

function ErrorCapture.Reset()
    ErrorCapture.errors = {}
    ErrorCapture.dirty = false
    ErrorCapture.flushes = 0
end

function ErrorCapture.Capture(msg, realm, stack, addonName, addonId)
    local key = tostring(msg or "unknown error")
    local row = ErrorCapture.errors[key]

    if not row then
        row = {
            msg = key,
            realm = tostring(realm or realmName()),
            addon = tostring(addonName or ""),
            addon_id = tostring(addonId or ""),
            map = game.GetMap(),
            stack = stackToLines(stack),
            quantity = 0
        }
        ErrorCapture.errors[key] = row
    end

    row.quantity = row.quantity + 1
    ErrorCapture.dirty = true
end

function ErrorCapture.Flush(force)
    if not force and not ErrorCapture.dirty then return end

    ErrorCapture.dirty = false
    ErrorCapture.flushes = ErrorCapture.flushes + 1

    local dir = string.match(ErrorCapture.logPath, "^(.*)/[^/]+$")
    if dir and dir ~= "" then file.CreateDir(dir) end

    local current = readLog()
    local realm = realmName()

    current.updated = os.date("!%Y-%m-%dT%H:%M:%SZ")
    current.map = game.GetMap()
    current.realms[realm] = {
        flushes = ErrorCapture.flushes,
        errors = ErrorCapture.errors
    }

    file.Write(ErrorCapture.logPath, util.TableToJSON(current, true))

    print("[Seamless Portals AI] flushed Lua errors to data/" .. ErrorCapture.logPath)
end

function ErrorCapture.Install()
    hook.Remove("OnLuaError", ErrorCapture.hookName)
    hook.Add("OnLuaError", ErrorCapture.hookName, function(...)
        xpcall(ErrorCapture.Capture, internalError, ...)
    end)

    timer.Remove(ErrorCapture.flushTimer)
    timer.Create(ErrorCapture.flushTimer, 1, 0, function()
        ErrorCapture.Flush(false)
    end)

    print("[Seamless Portals AI] Lua error capture installed on " .. realmName())
end

function ErrorCapture.Cleanup()
    hook.Remove("OnLuaError", ErrorCapture.hookName)
    timer.Remove(ErrorCapture.flushTimer)
    print("[Seamless Portals AI] Lua error capture cleaned on " .. realmName())
end
