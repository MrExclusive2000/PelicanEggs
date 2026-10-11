--[[
    ScumCommandProbe - read-only UE4SS mod for SCUM dedicated servers.

    Once the server has loaded its world, it lists every game function whose name looks
    related to admin commands, chat or console input, with its class, network flags and
    parameters. Nothing in the game is called or changed: it only reads the reflection data
    Unreal keeps about its own classes.

    Output:
      ue4ss/Mods/ScumCommandProbe/probe-output.txt   (full report)
      ue4ss/UE4SS.log                                (summary, lines start with [ScumCommandProbe])

    It runs once per server start. Disable or delete it after you have the report.
]]

local TAG = "[ScumCommandProbe] "

-- Case-insensitive name fragments worth reporting.
local KEYWORDS = {
    "admin", "command", "cheat", "chat", "console", "exec", "kick", "ban",
    "teleport", "announce", "broadcast", "message", "say", "whisper",
}

-- Engine modules that are noise for this purpose, except for the classes listed below.
local NOISY_PREFIXES = {
    "/Script/CoreUObject.", "/Script/UMG.", "/Script/Slate", "/Script/Niagara",
    "/Script/MovieScene", "/Script/AudioMixer", "/Script/MediaAssets", "/Script/Landscape",
    "/Script/AnimGraphRuntime", "/Script/Chaos", "/Script/Foliage", "/Script/Paper2D",
    "/Script/OnlineSubsystem", "/Script/LevelSequence", "/Script/Synthesis",
}

-- Engine classes that are relevant even though they live in /Script/Engine.
local ENGINE_CLASSES_OF_INTEREST = {
    "PlayerController", "GameModeBase", "GameMode", "CheatManager", "GameSession",
    "GameStateBase", "KismetSystemLibrary",
}

-- Looked up by path if FindObjects returns nothing.
local FALLBACK_CLASSES = {
    "/Script/Engine.PlayerController", "/Script/Engine.GameModeBase", "/Script/Engine.GameMode",
    "/Script/Engine.CheatManager", "/Script/Engine.GameSession", "/Script/Engine.GameStateBase",
}

-- EFunctionFlags (Engine/Source/Runtime/CoreUObject/Public/UObject/Script.h)
local FLAGS = {
    { 0x00000040, "Net" },
    { 0x00000080, "NetReliable" },
    { 0x00000200, "Exec" },
    { 0x00000400, "Native" },
    { 0x00000800, "BlueprintEvent" },
    { 0x00002000, "Static" },
    { 0x00004000, "NetMulticast" },
    { 0x00200000, "NetServer" },
    { 0x01000000, "NetClient" },
    { 0x04000000, "BlueprintCallable" },
}

local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function fname(object)
    return safe(function() return object:GetFName():ToString() end) or "?"
end

local function lower(text)
    return string.lower(text or "")
end

local function matchesKeyword(name)
    local lowered = lower(name)
    for _, keyword in ipairs(KEYWORDS) do
        if string.find(lowered, keyword, 1, true) then
            return true
        end
    end
    return false
end

local function isNoisy(path)
    for _, prefix in ipairs(NOISY_PREFIXES) do
        if string.sub(path, 1, #prefix) == prefix then
            return true
        end
    end

    if string.sub(path, 1, #"/Script/Engine.") == "/Script/Engine." then
        local className = string.match(path, "^/Script/Engine%.([^:]+)")
        for _, interesting in ipairs(ENGINE_CLASSES_OF_INTEREST) do
            if className == interesting then
                return false
            end
        end
        return true
    end

    return false
end

local function describeFlags(flags)
    if type(flags) ~= "number" then
        return "flags=?"
    end

    local names = {}
    for _, flag in ipairs(FLAGS) do
        if flags & flag[1] ~= 0 then
            table.insert(names, flag[2])
        end
    end

    return string.format("flags=0x%08X %s", flags, table.concat(names, ","))
end

-- UE4SS invokes iteration callbacks from C++. Keep those callbacks to a bare table insert
-- and do all the inspection afterwards, each item inside its own pcall, so one broken
-- entry is skipped instead of taking the whole scan down.
local function collect(owner, method)
    local items = {}
    local ok = pcall(function()
        owner[method](owner, function(item)
            items[#items + 1] = item
        end)
    end)
    return items, ok
end

-- "StrProperty /Script/ConZ.Foo:Bar:Message" -> "Message: StrProperty"
local function describeParameters(func)
    local params = {}
    local properties = collect(func, "ForEachProperty")

    for _, property in ipairs(properties) do
        local full = safe(function() return property:GetFullName() end) or ""
        local propertyType = string.match(full, "^(%S+)%s") or "?"
        params[#params + 1] = fname(property) .. ": " .. propertyType
    end

    return "(" .. table.concat(params, ", ") .. ")"
end

local function outputPath()
    local source = debug.getinfo(1, "S").source or ""
    source = string.gsub(source, "^@", "")
    local modDir = string.match(source, "^(.*)[/\\]Scripts[/\\]main%.lua$")
    if modDir == nil then
        return nil
    end
    return modDir .. "/probe-output.txt"
end

local progress = "start"

local function inspectClass(class, functions, classes)
    local full = safe(function() return class:GetFullName() end)
    if full == nil then
        return 0
    end

    local classPath = string.match(full, "^%S+%s+(.+)$") or full
    progress = classPath
    if isNoisy(classPath) then
        return 0
    end

    if matchesKeyword(fname(class)) then
        classes[#classes + 1] = classPath
    end

    local found = 0
    local classFunctions = collect(class, "ForEachFunction")
    for _, func in ipairs(classFunctions) do
        local name = fname(func)
        if matchesKeyword(name) then
            progress = classPath .. ":" .. name
            local flags = safe(function() return func:GetFunctionFlags() end)
            functions[#functions + 1] = string.format("%s:%s %s\n    %s", classPath, name, describeParameters(func), describeFlags(flags))
            found = found + 1
        end
    end

    return found
end

local function scan()
    local functions = {}
    local classes = {}
    local allClasses = {}

    -- FindObjects searches GUObjectArray on the C++ side. Class "Class" (not exact) covers
    -- native classes and Blueprint classes, which derive from it.
    local noFlags = (type(EObjectFlags) == "table" and EObjectFlags.RF_NoFlags) or 0
    local seen = {}
    local function add(class)
        local key = safe(function() return class:GetAddress() end) or class
        if class ~= nil and not seen[key] then
            seen[key] = true
            allClasses[#allClasses + 1] = class
        end
    end

    local found = safe(function() return FindObjects(0, "Class", nil, noFlags, noFlags, false) end)
    local viaFindObjects = 0
    if type(found) == "table" then
        for _, class in pairs(found) do
            add(class)
            viaFindObjects = viaFindObjects + 1
        end
    end
    print(TAG .. string.format("FindObjects returned %d classes.\n", viaFindObjects))

    -- Fallback: look up the Unreal classes that matter most by their full path.
    if #allClasses == 0 then
        for _, path in ipairs(FALLBACK_CLASSES) do
            local class = safe(function() return StaticFindObject(path) end)
            if class ~= nil and safe(function() return class:IsValid() end) then
                add(class)
            end
        end
        print(TAG .. string.format("Fallback lookup found %d of %d known classes.\n", #allClasses, #FALLBACK_CLASSES))
    end

    local skipped = 0
    for _, class in ipairs(allClasses) do
        local ok = pcall(inspectClass, class, functions, classes)
        if not ok then
            skipped = skipped + 1
        end
    end
    local objectCount = #allClasses
    if skipped > 0 then
        print(TAG .. string.format("Skipped %d classes that could not be read.\n", skipped))
    end

    table.sort(functions)
    table.sort(classes)

    local lines = {
        "ScumCommandProbe report",
        "Generated: " .. os.date("!%Y-%m-%d %H:%M:%S UTC"),
        string.format("Classes scanned: %d, matching functions: %d, matching classes: %d", objectCount, #functions, #classes),
        "",
        "== Functions (Net/NetServer = callable over the network to the server; Exec = console command) ==",
    }
    for _, line in ipairs(functions) do table.insert(lines, line) end
    table.insert(lines, "")
    table.insert(lines, "== Classes ==")
    for _, line in ipairs(classes) do table.insert(lines, line) end

    local report = table.concat(lines, "\n") .. "\n"
    local path = outputPath()
    local written = false

    if path ~= nil then
        local file = io.open(path, "w")
        if file ~= nil then
            file:write(report)
            file:close()
            written = true
        end
    end

    print(TAG .. string.format("Scanned %d classes: %d matching functions, %d matching classes.\n", objectCount, #functions, #classes))
    if written then
        print(TAG .. "Full report written to " .. path .. "\n")
    else
        print(TAG .. "Could not write probe-output.txt, printing the report here instead.\n")
        for _, line in ipairs(lines) do
            print(TAG .. line .. "\n")
        end
    end
end

-- Wait until the world (and with it SCUM's game mode) exists, then scan once on the game thread.
local done = false
local queued = false
local attempts = 0

LoopAsync(10000, function()
    if done then
        return true
    end

    attempts = attempts + 1
    if attempts > 60 then
        print(TAG .. "Gave up: no game mode appeared within 10 minutes.\n")
        return true
    end

    if not queued then
        queued = true
        ExecuteInGameThread(function()
            queued = false
            if done then
                return
            end

            -- Blueprint classes load with the map, so prefer to wait for a game mode. Native
            -- classes exist from startup, so after two minutes scan regardless.
            local gameMode = safe(function() return FindFirstOf("GameModeBase") end)
            local ready = gameMode ~= nil and safe(function() return gameMode:IsValid() end)
            if not ready and attempts < 12 then
                return
            end

            done = true
            print(TAG .. "World loaded, scanning reflection data (read-only)...\n")
            local ok, err = pcall(scan)
            if not ok then
                print(TAG .. "Scan failed while reading " .. tostring(progress) .. ": " .. tostring(err) .. "\n")
            end
        end)
    end

    return false
end)

print(TAG .. "Loaded. Waiting for the world to load before scanning.\n")
