-- AI helper functions for downloading and extracting Workshop GMAs. Loaded idle until called.

SeamlessPortals = SeamlessPortals or {}
local SP = SeamlessPortals
SP.AI = SP.AI or {}

local Workshop = SP.AI.Workshop or {
    dataDir = "seamless_tests",
    maxRetries = 3,
    retryDelay = 1,
    readChunkSize = 65536
}

SP.AI.Workshop = Workshop

Workshop.dataDir = Workshop.dataDir or "seamless_tests"
Workshop.maxRetries = Workshop.maxRetries or 3
Workshop.retryDelay = Workshop.retryDelay or 1
Workshop.readChunkSize = Workshop.readChunkSize or 65536

local function utcNow()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function runID()
    return os.date("!%Y%m%d_%H%M%S")
end

local function dataPath(...)
    return table.concat({ ... }, "/")
end

local function createDirs(path)
    local dir = string.match(path, "^(.*)/[^/]*$") or ""
    local current = ""

    for segment in string.gmatch(dir, "[^/]+") do
        current = current == "" and segment or current .. "/" .. segment
        file.CreateDir(current)
    end
end

local function writeJSON(path, data)
    createDirs(path)
    file.Write(path, util.TableToJSON(data, true))
end

local function printStatus(message)
    print("[Seamless Portals AI] workshop inspector: " .. message)
end

local function sanitizeWorkshopID(workshopID)
    workshopID = tostring(workshopID or "")
    if not string.match(workshopID, "^%d+$") then return end

    return workshopID
end

local function sanitizeGMAPath(path)
    path = tostring(path or "")
    path = string.Replace(path, "\\", "/")

    if path == "" or string.StartWith(path, "/") or string.find(path, ":", 1, true) then return end
    if string.find(path, "%z") then return end

    local parts = {}

    for part in string.gmatch(path, "[^/]+") do
        if part == "" or part == "." or part == ".." then return end

        parts[#parts + 1] = part
    end

    if #parts == 0 then return end

    return table.concat(parts, "/")
end

local function readCString(gma, limit)
    local chars = {}
    limit = limit or 32768

    while not gma:EndOfFile() do
        local char = gma:Read(1)

        if not char or char == "" then return nil, "Unexpected end of file while reading string" end
        if char == "\0" then return table.concat(chars) end

        chars[#chars + 1] = char

        if #chars > limit then
            return nil, "Unterminated string exceeded " .. tostring(limit) .. " bytes"
        end
    end

    return nil, "Unexpected end of file while reading string"
end

local function readUInt64(gma)
    local low = gma:ReadULong()
    local high = gma:ReadULong()

    if not low or not high then return end

    return high * 4294967296 + low
end

local function skipBytes(gma, amount)
    amount = tonumber(amount) or 0

    while amount > 0 do
        local step = math.min(amount, Workshop.readChunkSize)
        gma:Skip(step)
        amount = amount - step
    end
end

local function normalizeFileInfo(result)
    if not istable(result) then return nil end

    return {
        title = tostring(result.title or ""),
        description = tostring(result.description or ""),
        owner = tostring(result.owner or ""),
        size = tonumber(result.size) or 0,
        tags = tostring(result.tags or ""),
        updated = tonumber(result.updated) or 0,
        created = tonumber(result.created) or 0,
        wsid = tostring(result.id or result.publishedfileid or "")
    }
end

local function classifyEntry(entry, summary)
    local path = string.lower(entry.path)

    summary.total_size = summary.total_size + entry.size

    if string.StartWith(path, "lua/") then
        summary.lua_count = summary.lua_count + 1
        summary.lua_files[#summary.lua_files + 1] = entry.path
    end

    if string.StartWith(path, "lua/autorun/") or
       string.StartWith(path, "lua/autorun/server/") or
       string.StartWith(path, "lua/autorun/client/") then
        summary.entry_points[#summary.entry_points + 1] = entry.path
    elseif string.StartWith(path, "lua/entities/") then
        summary.entities[#summary.entities + 1] = entry.path
    elseif string.StartWith(path, "lua/weapons/") then
        summary.weapons[#summary.weapons + 1] = entry.path
    elseif string.StartWith(path, "lua/vgui/") then
        summary.vgui[#summary.vgui + 1] = entry.path
    end
end

local function openOutputFile(path, options)
    local outputPath = options.preserveExtensions and path or path .. ".dat"

    createDirs(outputPath)

    local output = file.Open(outputPath, "wb", "DATA")
    if output then return output, outputPath end

    if string.EndsWith(outputPath, ".dat") then return end

    local fallbackPath = outputPath .. ".dat"
    createDirs(fallbackPath)

    output = file.Open(fallbackPath, "wb", "DATA")
    if output then return output, fallbackPath end
end

local function copyEntryBytes(gma, entry, output)
    local remaining = entry.size

    while remaining > 0 do
        local step = math.min(remaining, Workshop.readChunkSize)
        local chunk = gma:Read(step)

        if not chunk or chunk == "" then
            return false, "Unexpected end of file while extracting " .. entry.path
        end

        output:Write(chunk)
        remaining = remaining - #chunk
    end

    return true
end

local function parseGMAHeader(gma, result)
    local magic = gma:Read(4)

    if magic ~= "GMAD" then
        return false, "File does not start with GMAD"
    end

    local versionByte = gma:Read(1)
    result.version = versionByte and string.byte(versionByte) or 0
    result.steam_id = readUInt64(gma) or 0
    result.timestamp = readUInt64(gma) or 0
    result.required_content = {}

    while not gma:EndOfFile() do
        local required, err = readCString(gma)
        if required == nil then return false, err end
        if required == "" then break end

        result.required_content[#result.required_content + 1] = required
    end

    result.title = readCString(gma) or ""
    result.description = readCString(gma) or ""
    result.author = readCString(gma) or ""
    result.addon_version = gma:ReadLong() or 0

    return true
end

local function parseGMAEntries(gma, result, options)
    local maxEntries = options.maxEntries or 20000

    result.entries = {}
    result.summary = {
        total_size = 0,
        lua_count = 0,
        lua_files = {},
        entry_points = {},
        entities = {},
        weapons = {},
        vgui = {}
    }

    while not gma:EndOfFile() do
        if #result.entries >= maxEntries then
            return false, "GMA file list exceeded " .. tostring(maxEntries) .. " entries"
        end

        local number = gma:ReadULong()
        if not number then return false, "Unexpected end of file while reading file number" end
        if number == 0 then return true end

        local rawPath, pathErr = readCString(gma)
        if rawPath == nil then return false, pathErr end

        local safePath = sanitizeGMAPath(rawPath)
        local size = readUInt64(gma)
        local crc = gma:ReadULong()

        if not size or not crc then
            return false, "Unexpected end of file while reading file metadata"
        end

        local entry = {
            number = number,
            path = rawPath,
            safe_path = safePath,
            size = size,
            crc = crc
        }

        result.entries[#result.entries + 1] = entry

        if safePath then
            classifyEntry(entry, result.summary)
        end
    end

    return false, "Unexpected end of file before file table terminator"
end

local function extractEntries(gma, result, options)
    local extracted = {}
    local skipped = {}
    local outputRoot = options.outputRoot or dataPath(Workshop.dataDir, "workshop_" .. tostring(options.workshopID or "unknown") .. "_" .. runID())
    local filesRoot = dataPath(outputRoot, "files")
    local maxFileBytes = options.maxFileBytes

    result.output_root = outputRoot
    result.index_path = dataPath(outputRoot, "index.json")

    for _, entry in ipairs(result.entries) do
        if not entry.safe_path then
            skipBytes(gma, entry.size)
            skipped[#skipped + 1] = {
                path = entry.path,
                size = entry.size,
                reason = "unsafe path"
            }
        elseif maxFileBytes and entry.size > maxFileBytes then
            skipBytes(gma, entry.size)
            skipped[#skipped + 1] = {
                path = entry.path,
                size = entry.size,
                reason = "larger than maxFileBytes"
            }
        else
            local outputPath = dataPath(filesRoot, entry.safe_path)
            local output, storedPath = openOutputFile(outputPath, options)

            if not output then
                skipBytes(gma, entry.size)
                skipped[#skipped + 1] = {
                    path = entry.path,
                    size = entry.size,
                    reason = "could not open output file"
                }
            else
                local ok, err = copyEntryBytes(gma, entry, output)
                output:Close()

                if not ok then return false, err end

                extracted[#extracted + 1] = {
                    path = entry.path,
                    stored_path = storedPath,
                    size = entry.size,
                    crc = entry.crc
                }
            end
        end
    end

    result.extracted = extracted
    result.skipped = skipped
    result.extracted_count = #extracted
    result.skipped_count = #skipped

    return true
end

function Workshop.GMADataPath(workshopID)
    return dataPath(Workshop.dataDir, "workshop_" .. tostring(workshopID) .. ".dat")
end

function Workshop.ResultPath(workshopID)
    return dataPath(Workshop.dataDir, "workshop_" .. tostring(workshopID) .. "_inspect.json")
end

function Workshop.ExtractGMA(gmaDataPath, options)
    options = options or {}

    local result = {
        test = "workshop_gma_extract",
        ok = false,
        map = game.GetMap(),
        started = utcNow(),
        updated = utcNow(),
        gma_data_path = gmaDataPath,
        workshop_id = tostring(options.workshopID or "")
    }

    local gma = file.Open(gmaDataPath, "rb", "DATA")

    if not gma then
        result.error = "Could not open data/" .. tostring(gmaDataPath)
        writeJSON(options.resultPath or dataPath(Workshop.dataDir, "workshop_extract_failed.json"), result)
        return false, result
    end

    local ok, err = xpcall(function()
        local headerOk, headerErr = parseGMAHeader(gma, result)
        if not headerOk then error(headerErr) end

        local entriesOk, entriesErr = parseGMAEntries(gma, result, options)
        if not entriesOk then error(entriesErr) end

        local extractOk, extractErr = extractEntries(gma, result, options)
        if not extractOk then error(extractErr) end

        result.ok = true
    end, debug.traceback)

    gma:Close()

    if not ok then
        result.error = tostring(err)
        result.needs_system_fallback = true
    end

    result.updated = utcNow()

    writeJSON(result.index_path or options.resultPath or dataPath(Workshop.dataDir, "workshop_extract_failed.json"), result)

    return result.ok, result
end

function Workshop.DownloadAndExtract(workshopID, options)
    options = options or {}
    workshopID = sanitizeWorkshopID(workshopID)

    if not workshopID then
        printStatus("invalid workshop ID")
        return false
    end

    if SERVER then
        printStatus("steamworks.DownloadUGC is client-only; run this helper from the client realm")
        return false
    end

    if not steamworks or not steamworks.DownloadUGC then
        printStatus("steamworks.DownloadUGC is unavailable in this realm")
        return false
    end

    local resultPath = options.resultPath or Workshop.ResultPath(workshopID)
    local result = {
        test = "workshop_download_and_extract",
        ok = false,
        workshop_id = workshopID,
        map = game.GetMap(),
        started = utcNow(),
        updated = utcNow(),
        result_path = resultPath,
        gma_data_path = Workshop.GMADataPath(workshopID)
    }

    local function saveResult()
        result.updated = utcNow()
        writeJSON(resultPath, result)
    end

    local function fail(message)
        result.ok = false
        result.error = tostring(message)
        result.needs_system_fallback = result.gma_saved == true
        saveResult()
        printStatus("failed: " .. tostring(message))
    end

    local function saveGMA(gmaFile)
        createDirs(result.gma_data_path)

        local output = file.Open(result.gma_data_path, "wb", "DATA")
        if not output then
            return false, "Could not write data/" .. result.gma_data_path
        end

        local total = gmaFile.Size and gmaFile:Size()
        local written = 0

        if total and total > 0 then
            while written < total do
                local chunk = gmaFile:Read(math.min(total - written, Workshop.readChunkSize))

                if not chunk or chunk == "" then
                    output:Close()
                    return false, "Downloaded UGC file ended before expected size"
                end

                output:Write(chunk)
                written = written + #chunk
            end
        else
            local content = gmaFile:Read()

            if not content then
                output:Close()
                return false, "Downloaded UGC file returned no bytes"
            end

            output:Write(content)
            written = #content
        end

        output:Close()

        result.gma_saved = true
        result.gma_bytes = written

        return true
    end

    local function finishDownload(path, gmaFile)
        local ok, err = saveGMA(gmaFile)

        if gmaFile then
            gmaFile:Close()
        end

        if not ok then
            fail(err)
            return
        end

        result.ugc_path = tostring(path or "")

        if options.extract == false then
            result.ok = true
            saveResult()
            printStatus("saved gma to data/" .. result.gma_data_path)
            return
        end

        local extractOk, extractResult = Workshop.ExtractGMA(result.gma_data_path, {
            workshopID = workshopID,
            outputRoot = options.outputRoot,
            maxEntries = options.maxEntries,
            maxFileBytes = options.maxFileBytes,
            preserveExtensions = options.preserveExtensions,
            resultPath = resultPath
        })

        result.extract = extractResult
        result.output_root = extractResult.output_root
        result.index_path = extractResult.index_path
        result.ok = extractOk
        result.needs_system_fallback = not extractOk

        if not extractOk then
            result.error = extractResult.error
            printStatus("downloaded gma but extraction failed; use data/" .. result.gma_data_path .. " for system fallback")
        else
            printStatus("downloaded and extracted to data/" .. tostring(result.output_root))
        end

        saveResult()
    end

    local function download(attempt)
        attempt = attempt or 1
        result.download_attempts = attempt
        saveResult()
        printStatus("downloading Workshop item " .. workshopID .. " (attempt " .. tostring(attempt) .. ")")

        steamworks.DownloadUGC(workshopID, function(path, gmaFile)
            local ok, err = xpcall(function()
                if not path or not gmaFile then
                    if attempt < (options.maxRetries or Workshop.maxRetries) then
                        timer.Simple(options.retryDelay or Workshop.retryDelay, function()
                            download(attempt + 1)
                        end)
                    else
                        fail("steamworks.DownloadUGC returned no file")
                    end

                    return
                end

                finishDownload(path, gmaFile)
            end, debug.traceback)

            if not ok then
                fail(err)
            end
        end)
    end

    local function getFileInfo(attempt)
        if options.skipFileInfo or not steamworks.FileInfo then
            download(1)
            return
        end

        attempt = attempt or 1
        result.file_info_attempts = attempt
        saveResult()

        steamworks.FileInfo(workshopID, function(info)
            local ok, err = xpcall(function()
                local normalized = normalizeFileInfo(info)

                if normalized then
                    result.file_info = normalized
                    download(1)
                    return
                end

                if attempt < (options.maxRetries or Workshop.maxRetries) then
                    timer.Simple(options.retryDelay or Workshop.retryDelay, function()
                        getFileInfo(attempt + 1)
                    end)
                else
                    result.file_info_error = "steamworks.FileInfo returned no metadata"
                    download(1)
                end
            end, debug.traceback)

            if not ok then
                fail(err)
            end
        end)
    end

    getFileInfo(1)

    return true
end
