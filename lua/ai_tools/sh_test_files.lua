-- AI helper functions for managing temporary test artifacts. Loaded idle until called.

SeamlessPortals = SeamlessPortals or {}
local SP = SeamlessPortals
SP.AI = SP.AI or {}

local Files = SP.AI.Files or {
    dataDir = "seamless_tests"
}

SP.AI.Files = Files

Files.dataDir = Files.dataDir or "seamless_tests"

local function keepLookup(list)
    local lookup = {}

    for _, name in ipairs(list or {}) do
        lookup[string.lower(tostring(name))] = true
    end

    return lookup
end

local function shouldKeep(keep, name, path)
    return keep[string.lower(tostring(name))] or keep[string.lower(tostring(path))]
end

local function deleteTree(path, removed)
    local files, dirs = file.Find(path .. "/*", "DATA")

    for _, name in ipairs(files or {}) do
        local filePath = path .. "/" .. name

        file.Delete(filePath)
        removed[#removed + 1] = filePath
    end

    for _, name in ipairs(dirs or {}) do
        local dirPath = path .. "/" .. name

        deleteTree(dirPath, removed)
        file.Delete(dirPath)
        removed[#removed + 1] = dirPath
    end
end

function Files.Cleanup(options)
    options = options or {}

    local dir = options.dataDir or Files.dataDir
    local keep = keepLookup(options.keep)
    local files, dirs = file.Find(dir .. "/*", "DATA")
    local removed = {}
    local skipped = {}

    for _, name in ipairs(files or {}) do
        local lowerName = string.lower(name)

        if keep[lowerName] then
            skipped[#skipped + 1] = name
        else
            file.Delete(dir .. "/" .. name)
            removed[#removed + 1] = name
        end
    end

    for _, name in ipairs(dirs or {}) do
        local path = dir .. "/" .. name

        if shouldKeep(keep, name, path) then
            skipped[#skipped + 1] = name
        else
            deleteTree(path, removed)
            file.Delete(path)
            removed[#removed + 1] = name
        end
    end

    local result = {
        data_dir = dir,
        removed = removed,
        skipped = skipped,
        removed_count = #removed,
        skipped_count = #skipped
    }

    print("[Seamless Portals AI] cleaned data/" .. dir .. " (" .. tostring(#removed) .. " file(s) removed)")

    return result
end
