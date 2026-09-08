-- AI helper functions for offscreen world screenshots. Loaded idle until called.

SeamlessPortals = SeamlessPortals or {}
local SP = SeamlessPortals
SP.AI = SP.AI or {}

local WorldCapture = SP.AI.WorldCapture or {
    hookName = "SEAMLESS_PORTALS_AI_WorldCapture",
    pvsHookName = "SEAMLESS_PORTALS_AI_WorldCapturePVS",
    timerName = "SEAMLESS_PORTALS_AI_WorldCapture",
    netPVS = "SEAMLESS_PORTALS_AI_WorldCapturePVS",
    dataDir = "seamless_tests",
    imagePath = "seamless_tests/world_capture.png",
    metaPath = "seamless_tests/world_capture.json",
    maxDimension = 1024
}

SP.AI.WorldCapture = WorldCapture

WorldCapture.hookName = WorldCapture.hookName or "SEAMLESS_PORTALS_AI_WorldCapture"
WorldCapture.pvsHookName = WorldCapture.pvsHookName or "SEAMLESS_PORTALS_AI_WorldCapturePVS"
WorldCapture.timerName = WorldCapture.timerName or "SEAMLESS_PORTALS_AI_WorldCapture"
WorldCapture.netPVS = WorldCapture.netPVS or "SEAMLESS_PORTALS_AI_WorldCapturePVS"
WorldCapture.dataDir = WorldCapture.dataDir or "seamless_tests"
WorldCapture.imagePath = WorldCapture.imagePath or "seamless_tests/world_capture.png"
WorldCapture.metaPath = WorldCapture.metaPath or "seamless_tests/world_capture.json"
WorldCapture.maxDimension = WorldCapture.maxDimension or 1024
WorldCapture.pvsOrigins = WorldCapture.pvsOrigins or {}

local function createParent(path)
    local dir = string.match(path, "^(.*)/[^/]+$")
    if dir and dir ~= "" then file.CreateDir(dir) end
end

local function writeJSON(path, data)
    createParent(path)
    file.Write(path, util.TableToJSON(data, true))
end

local function vectorJSON(value)
    if not value then return end

    return {
        x = math.Round(value.x, 3),
        y = math.Round(value.y, 3),
        z = math.Round(value.z, 3)
    }
end

local function angleJSON(value)
    if not value then return end

    return {
        p = math.Round(value.p, 3),
        y = math.Round(value.y, 3),
        r = math.Round(value.r, 3)
    }
end

local function nextPowerOfTwo(value)
    local size = 1

    while size < value do
        size = size * 2
    end

    return size
end

local function sanitizeCaptureDimension(value, fallback)
    value = tonumber(value) or fallback
    value = math.floor(value + 0.5)

    return math.Clamp(value, 16, 4096)
end

local function normalizeCaptureSize(width, height, options)
    width = sanitizeCaptureDimension(width, 1024)
    height = sanitizeCaptureDimension(height, 576)

    local maxDimension = options.maxDimension
    if maxDimension == nil then maxDimension = WorldCapture.maxDimension end

    if maxDimension and maxDimension > 0 then
        local largest = math.max(width, height)

        if largest > maxDimension then
            local scale = maxDimension / largest
            width = math.max(16, math.floor(width * scale + 0.5))
            height = math.max(16, math.floor(height * scale + 0.5))
        end
    end

    return width, height
end

local function listMatches(value, expected)
    if not expected then return true end

    if istable(expected) then
        for _, item in ipairs(expected) do
            if value == item then return true end
        end

        return false
    end

    return value == expected
end

local function containsMatches(value, expected)
    if not expected then return true end
    if not value then return false end

    value = string.lower(tostring(value))

    if istable(expected) then
        for _, item in ipairs(expected) do
            if string.find(value, string.lower(tostring(item)), 1, true) then
                return true
            end
        end

        return false
    end

    return string.find(value, string.lower(tostring(expected)), 1, true) ~= nil
end

local function hasTargetCriteria(filters)
    return filters.all == true
        or filters.entity ~= nil
        or filters.entities ~= nil
        or filters.entityIndex ~= nil
        or filters.entityIndexes ~= nil
        or filters.class ~= nil
        or filters.classes ~= nil
        or filters.classContains ~= nil
        or filters.model ~= nil
        or filters.models ~= nil
        or filters.modelContains ~= nil
        or filters.predicate ~= nil
        or filters.where ~= nil
end

local function tableHasEntity(list, ent)
    for _, candidate in ipairs(list or {}) do
        if candidate == ent then return true end
    end

    return false
end

local function tableHasEntityIndex(list, ent)
    local index = ent:EntIndex()

    for _, candidate in ipairs(list or {}) do
        if candidate == index then return true end
    end

    return false
end

local function getEntityCenter(ent)
    if ent.WorldSpaceCenter then
        return ent:WorldSpaceCenter()
    end

    return ent:GetPos()
end

local function entityMatches(ent, filters)
    if not IsValid(ent) then return false end

    if IsValid(filters.entity) and ent ~= filters.entity then return false end
    if filters.entities and not tableHasEntity(filters.entities, ent) then return false end

    if filters.entityIndex and ent:EntIndex() ~= filters.entityIndex then return false end
    if filters.entityIndexes and not tableHasEntityIndex(filters.entityIndexes, ent) then return false end

    if not listMatches(ent:GetClass(), filters.class or filters.classes) then return false end
    if not containsMatches(ent:GetClass(), filters.classContains) then return false end

    if not listMatches(ent:GetModel(), filters.model or filters.models) then return false end
    if not containsMatches(ent:GetModel(), filters.modelContains) then return false end

    local center = filters.origin or filters.near or filters.position
    if center and filters.radius then
        local radius = filters.radius
        if (getEntityCenter(ent) - center):LengthSqr() > radius * radius then
            return false
        end
    end

    local predicate = filters.predicate or filters.where
    if type(predicate) == "function" and predicate(ent, filters) ~= true then
        return false
    end

    return true
end

local function sortTargets(targets, filters)
    local origin = filters.sortOrigin or filters.origin or filters.near or filters.position

    if origin then
        table.sort(targets, function(left, right)
            return (getEntityCenter(left) - origin):LengthSqr() < (getEntityCenter(right) - origin):LengthSqr()
        end)

        return
    end

    table.sort(targets, function(left, right)
        return left:EntIndex() < right:EntIndex()
    end)
end

local function normalizeFilters(filters)
    filters = filters or {}

    return filters.filter or filters.filters or filters
end

local function firstValidEntity(list)
    for _, ent in ipairs(list or {}) do
        if IsValid(ent) then return ent end
    end
end

local function resolveTarget(options)
    local filters = normalizeFilters(options)

    if IsValid(options.target) then return options.target end
    if IsValid(options.entity) then return options.entity end

    if options.entityIndex then
        local ent = Entity(options.entityIndex)
        if IsValid(ent) then return ent end
    end

    if options.entities then
        return firstValidEntity(options.entities)
    end

    return WorldCapture.SelectTarget(filters)
end

local function chooseCamera(target, targetPos, options)
    if options.cameraOrigin and options.cameraAngles then
        return options.cameraOrigin, options.cameraAngles
    end

    if options.cameraOrigin and targetPos then
        return options.cameraOrigin, (targetPos - options.cameraOrigin):Angle()
    end

    if options.cameraOffset and targetPos then
        local origin = targetPos + options.cameraOffset
        return origin, (targetPos - origin):Angle()
    end

    local radius = options.targetRadius or 32
    if IsValid(target) and target.BoundingRadius then
        radius = math.max(target:BoundingRadius(), radius)
    end

    local dirs = options.cameraDirections or {
        Vector(1, 0, 0),
        Vector(-1, 0, 0),
        Vector(0, 1, 0),
        Vector(0, -1, 0),
        Vector(1, 1, 0):GetNormalized(),
        Vector(-1, 1, 0):GetNormalized(),
        Vector(1, -1, 0):GetNormalized(),
        Vector(-1, -1, 0):GetNormalized()
    }
    local distance = options.cameraDistance or math.Clamp(radius * 5, 160, 360)
    local height = options.cameraHeight or math.Clamp(radius * 0.7, 40, 100)
    local fallback

    for _, dir in ipairs(dirs) do
        local desired = targetPos + dir * distance + Vector(0, 0, height)
        fallback = fallback or desired

        local trace = util.TraceHull({
            start = targetPos + Vector(0, 0, height * 0.3),
            endpos = desired,
            mins = Vector(-8, -8, -8),
            maxs = Vector(8, 8, 8),
            filter = target,
            mask = MASK_SOLID_BRUSHONLY
        })

        if not trace.Hit then
            return desired, (targetPos - desired):Angle()
        end
    end

    return fallback, (targetPos - fallback):Angle()
end

local function baseResult(options)
    return {
        test = "world_capture",
        status = "queued",
        map = game.GetMap(),
        image_path = options.imagePath or WorldCapture.imagePath,
        started_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end

local function sendPVSOrigin(origin, lifetime)
    if SERVER then return true end

    local ok, err = pcall(function()
        net.Start(WorldCapture.netPVS)
        net.WriteVector(origin)
        net.WriteFloat(lifetime)
        net.SendToServer()
    end)

    return ok, err
end

function WorldCapture.InstallPVS()
    if CLIENT then return true end

    WorldCapture.pvsOrigins = WorldCapture.pvsOrigins or {}
    WorldCapture.pvsEnabled = true

    util.AddNetworkString(WorldCapture.netPVS)

    net.Receive(WorldCapture.netPVS, function(_, ply)
        if not WorldCapture.pvsEnabled then return end
        if not IsValid(ply) then return end
        if not ply:IsAdmin() then return end

        local previous = WorldCapture.pvsOrigins[ply]
        if previous and previous.nextRequest > CurTime() then return end
        local origin = net.ReadVector()
        local lifetime = net.ReadFloat()
        for _, value in ipairs({origin.x, origin.y, origin.z, lifetime}) do
            if value ~= value or value == math.huge or value == -math.huge then return end
        end
        if math.abs(origin.x) > 32768 or math.abs(origin.y) > 32768 or math.abs(origin.z) > 32768 then return end
        lifetime = math.Clamp(lifetime, 0.1, 3)

        WorldCapture.pvsOrigins = WorldCapture.pvsOrigins or {}
        WorldCapture.pvsOrigins[ply] = {
            origin = origin,
            expires = CurTime() + lifetime,
            nextRequest = CurTime() + 0.1
        }
    end)

    hook.Add("SetupPlayerVisibility", WorldCapture.pvsHookName, function(ply)
        local state = WorldCapture.pvsOrigins[ply]
        if not state then return end

        if state.expires < CurTime() then
            WorldCapture.pvsOrigins[ply] = nil
            return
        end

        AddOriginToPVS(state.origin)
    end)

    hook.Add("PlayerDisconnected", WorldCapture.pvsHookName, function(ply)
        WorldCapture.pvsOrigins[ply] = nil
    end)

    return true
end

function WorldCapture.Cleanup()
    if SERVER then
        WorldCapture.pvsEnabled = false
        WorldCapture.pvsOrigins = {}
        hook.Remove("SetupPlayerVisibility", WorldCapture.pvsHookName)
        hook.Remove("PlayerDisconnected", WorldCapture.pvsHookName)
        return
    end

    hook.Remove("PostRender", WorldCapture.hookName)
    timer.Remove(WorldCapture.timerName)
end

function WorldCapture.FindTargets(filters)
    filters = normalizeFilters(filters)

    if not hasTargetCriteria(filters) then
        return {}
    end

    local targets = {}
    local limit = filters.limit

    for _, ent in ipairs(ents.GetAll()) do
        if entityMatches(ent, filters) then
            targets[#targets + 1] = ent
        end
    end

    sortTargets(targets, filters)

    if limit and #targets > limit then
        for index = #targets, limit + 1, -1 do
            targets[index] = nil
        end
    end

    return targets
end

function WorldCapture.SelectTarget(filters)
    filters = normalizeFilters(filters)

    if IsValid(filters.target) then return filters.target end
    if IsValid(filters.entity) then return filters.entity end

    local targets = WorldCapture.FindTargets(filters)

    return targets[1]
end

function WorldCapture.Capture(options)
    options = options or {}

    if SERVER then
        print("[Seamless Portals AI] world capture is client-only; run it from client realm")
        return false
    end

    WorldCapture.Cleanup()

    local imagePath = options.imagePath or WorldCapture.imagePath
    local metaPath = options.metaPath or WorldCapture.metaPath
    local width, height = normalizeCaptureSize(options.width or 1024, options.heightPixels or options.captureHeight or 576, options)
    local rtSize = options.rtSize or nextPowerOfTwo(math.max(width, height))
    local result = baseResult(options)
    WorldCapture.lastResult = result
    local target = resolveTarget(options)
    local targetPos = options.targetPos or options.lookAt

    if not targetPos and IsValid(target) then
        targetPos = getEntityCenter(target)
    end

    if not targetPos and not (options.cameraOrigin and options.cameraAngles) then
        result.status = "failed"
        result.error = "Capture needs a target, targetPos, or cameraOrigin plus cameraAngles"
        result.finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
        writeJSON(metaPath, result)
        return false
    end

    local cameraOrigin, cameraAngles = chooseCamera(target, targetPos, options)

    result.capture = { w = width, h = height }
    result.rt_size = rtSize
    result.target_pos = vectorJSON(targetPos)
    result.camera_origin = vectorJSON(cameraOrigin)
    result.camera_angles = angleJSON(cameraAngles)

    if IsValid(target) then
        result.entity_index = target:EntIndex()
        result.entity_class = target:GetClass()
        result.entity_model = target:GetModel()
        result.entity_pos = vectorJSON(target:GetPos())
        result.entity_center = vectorJSON(getEntityCenter(target))
    end

    result.status = "waiting_pvs"
    writeJSON(metaPath, result)

    if options.addToPVS ~= false then
        local pvsOk, pvsErr = sendPVSOrigin(cameraOrigin, options.pvsLifetime or 1)
        result.pvs_requested = pvsOk == true
        if not pvsOk then result.pvs_error = tostring(pvsErr) end
        writeJSON(metaPath, result)
    end

    timer.Create(WorldCapture.timerName, options.pvsDelay or 0.25, 1, function()
        result.status = "waiting_postrender"
        writeJSON(metaPath, result)

        hook.Add("PostRender", WorldCapture.hookName, function()
            hook.Remove("PostRender", WorldCapture.hookName)

            local pushed = false
            local ok, err = xpcall(function()
                result.status = "rendering"
                writeJSON(metaPath, result)

                if IsValid(target) then
                    targetPos = options.targetPos or options.lookAt or getEntityCenter(target)
                end

                local drawViewer = options.drawviewer or options.drawViewer
                if drawViewer == nil and IsValid(target) and target == LocalPlayer() then
                    drawViewer = true
                end

                local rtName = options.rtName or ("SEAMLESS_PORTALS_AI_WorldCapture_" .. tostring(rtSize))
                local rt = GetRenderTarget(rtName, rtSize, rtSize, false)

                render.PushRenderTarget(rt, 0, 0, width, height)
                pushed = true
                render.Clear(10, 10, 10, 255, true, true)
                local view = {
                    origin = cameraOrigin,
                    angles = cameraAngles,
                    x = 0,
                    y = 0,
                    w = width,
                    h = height,
                    fov = options.fov or 50,
                    aspectratio = width / height,
                    drawhud = false,
                    drawviewmodel = false,
                    drawviewer = drawViewer == true,
                    dopostprocess = false,
                    bloomtone = false
                }

                if options.viewID then
                    view.viewid = options.viewID
                end

                render.RenderView(view)

                local png = render.Capture({
                    format = "png",
                    x = 0,
                    y = 0,
                    w = width,
                    h = height,
                    alpha = false
                })

                render.PopRenderTarget()
                pushed = false

                if not png or #png == 0 then
                    error("render.Capture returned empty data")
                end

                createParent(imagePath)
                file.Write(imagePath, png)

                result.status = "done"
                result.bytes = #png
                result.finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
                writeJSON(metaPath, result)
                WorldCapture.lastResult = result

                print("[Seamless Portals AI] saved offscreen world capture to data/" .. imagePath)
            end, debug.traceback)

            if pushed then
                render.PopRenderTarget()
            end

            if not ok then
                result.status = "failed"
                result.error = tostring(err)
                result.finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
                writeJSON(metaPath, result)
                WorldCapture.lastResult = result

                print("[Seamless Portals AI] offscreen world capture failed: " .. tostring(err))
            end
        end)
    end)

    return true
end

function WorldCapture.CapturePlayerView(options)
    options = options or {}

    if SERVER then
        print("[Seamless Portals AI] world capture is client-only; run it from client realm")
        return false
    end

    WorldCapture.Cleanup()

    local imagePath = options.imagePath or WorldCapture.imagePath
    local metaPath = options.metaPath or WorldCapture.metaPath
    local width, height = normalizeCaptureSize(options.width or ScrW(), options.heightPixels or options.captureHeight or ScrH(), options)
    local result = baseResult(options)
    WorldCapture.lastResult = result

    result.status = "waiting_postrender"
    result.capture = { w = width, h = height }
    result.source = "PostRender"
    writeJSON(metaPath, result)

    hook.Add("PostRender", WorldCapture.hookName, function()
        hook.Remove("PostRender", WorldCapture.hookName)

        local ok, err = xpcall(function()
            result.status = "capturing"
            writeJSON(metaPath, result)

            local png = render.Capture({
                format = "png",
                x = options.x or 0,
                y = options.y or 0,
                w = width,
                h = height,
                alpha = false
            })

            if not png or #png == 0 then
                error("render.Capture returned empty data")
            end

            createParent(imagePath)
            file.Write(imagePath, png)

            result.status = "done"
            result.bytes = #png
            result.finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
            writeJSON(metaPath, result)
            WorldCapture.lastResult = result

            print("[Seamless Portals AI] saved player view capture to data/" .. imagePath)
        end, debug.traceback)

        if not ok then
            result.status = "failed"
            result.error = tostring(err)
            result.finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
            writeJSON(metaPath, result)
            WorldCapture.lastResult = result

            print("[Seamless Portals AI] player view capture failed: " .. tostring(err))
        end
    end)

    return true
end

function WorldCapture.CaptureNoPVS(options)
    options = options or {}
    options.addToPVS = false

    return WorldCapture.Capture(options)
end

function WorldCapture.CaptureAt(cameraOrigin, cameraAngles, options)
    options = options or {}
    options.cameraOrigin = cameraOrigin
    options.cameraAngles = cameraAngles

    return WorldCapture.Capture(options)
end

function WorldCapture.CapturePoint(targetPos, options)
    options = options or {}
    options.targetPos = targetPos

    return WorldCapture.Capture(options)
end

function WorldCapture.CaptureEntity(entity, options)
    options = options or {}
    options.entity = entity

    return WorldCapture.Capture(options)
end

function WorldCapture.CaptureFirst(filters, options)
    options = options or {}
    options.filter = filters

    return WorldCapture.Capture(options)
end

function WorldCapture.CaptureModel(model, options)
    options = options or {}
    options.filter = options.filter or {}
    options.filter.model = model

    return WorldCapture.Capture(options)
end

-- Refresh an explicitly installed adapter without enabling it on first include.
if SERVER and WorldCapture.pvsEnabled then WorldCapture.InstallPVS() end
