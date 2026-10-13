--[[
    ScumCommandProbe (ExclsvProbe) - read-only UE4SS mod for SCUM dedicated servers.

    Once the server has loaded its world, it maps what SCUM exposes for the features our mods
    use or plan to use, grouped by topic (admin, chat, money, squads, bases, mines, events,
    vehicles, loot, combat, ...):

      - classes (with their parent class) and their functions, with parameters and network flags
      - stored values (properties) and events other code can listen to (delegates)
      - enums with their values (e.g. squad ranks, chat channels) and structs with their fields
      - data tables (loot, traders, items)
      - a census: how many of each world thing (vehicles, flags, traders, ...) exist right now

    Nothing in the game is called or changed: it reads the reflection data Unreal keeps about
    its own classes and counts live objects without touching them.

    Output:
      ue4ss/Mods/ScumCommandProbe/probe-output.txt   (full report)
      ue4ss/UE4SS.log                                (summary, lines start with [ExclsvProbe])

    It scans once the world has loaded (and, if probe-settings.lua asks for it, again later:
    vehicles and airdrops load their classes only once they appear). Disable or delete it
    after you have the report.
]]

local TAG = "[ExclsvProbe] "

-- Topics, in priority order: a name that fits several topics is listed under the first.
-- census = count the world objects of these classes.
local TOPICS = {
    { name = "Admin, rights and commands", words = { "admin", "command", "cheat", "exec", "permission", "privilege", "rights", "godmode", "whitelist", "kick", "ban" } },
    { name = "Chat, messages and on-screen notices", words = { "chat", "console", "announce", "broadcast", "message", "say", "whisper", "notif", "popup", "toast", "hud" } },
    { name = "Money, traders and fame", census = true, words = { "currency", "balance", "money", "gold", "cash", "bank", "wallet", "trade", "price", "fame", "economy", "shop" } },
    { name = "Squads", census = true, words = { "squad", "party", "invite" } },
    { name = "Bases, flags and raids", census = true, words = { "baseelement", "basebuilding", "flag", "raid", "lock", "door", "gate", "decay", "upkeep", "territory", "claim" } },
    { name = "Mines and traps", census = true, words = { "mine", "trap", "explosive", "claymore", "tripwire" } },
    { name = "World events, airdrops and NPCs", census = true, words = { "airdrop", "cargo", "bunker", "killbox", "horde", "puppet", "zombie", "sentry", "encounter", "event", "mech", "drone" } },
    { name = "Vehicles", census = true, words = { "vehicle", "fuel", "boat", "bicycle", "motorcycle", "aircraft", "airplane", "driver", "passenger", "seat" } },
    { name = "Loot and zones", census = true, words = { "loot", "spawner", "zone", "region", "sector" } },
    { name = "Stats and skills", words = { "skill", "attribute", "metabolism", "experience" } },
    { name = "Combat, damage and kills", words = { "damage", "projectile", "killer", "killed", "death", "recoil", "ammo", "firerate" } },
    { name = "Teleport and respawn", words = { "teleport", "respawn", "spawnpoint", "spawnlocation" } },
    { name = "Weather and time of day", words = { "weather", "timeofday", "daytime", "nighttime", "rain", "fog", "season" } },
    { name = "Map and markers", words = { "marker", "waypoint", "minimap", "mapicon" } },
    { name = "Logins and logs", words = { "login", "logout", "gamelog", "writelog" } },
}

-- Parts of names that contain a keyword by accident ("Flags" is not a base flag, a bandage
-- is not a ban). They are removed before matching.
local IGNORED_FRAGMENTS = {
    "flags", "determine", "examine", "bandage", "banner", "strap", "block", "clock",
    "prevent", "essay", "eventual", "train", "brain", "terrain",
}

-- Every function of these classes is listed, matching or not.
local WHOLE_CLASSES = { "conzplayercontroller", "conzgamemode", "conzgamestate", "conzplayerstate" }

-- Engine modules that are noise for this purpose, except for the classes listed below.
local NOISY_PREFIXES = {
    "/Script/CoreUObject.", "/Script/UMG.", "/Script/Slate", "/Script/Niagara",
    "/Script/MovieScene", "/Script/AudioMixer", "/Script/MediaAssets", "/Script/Landscape",
    "/Script/AnimGraphRuntime", "/Script/Chaos", "/Script/Foliage", "/Script/Paper2D",
    "/Script/OnlineSubsystem", "/Script/LevelSequence", "/Script/Synthesis",
}

-- Blueprint classes that are user interface or animation, by name prefix.
local NOISY_CLASS_PREFIXES = { "wbp_", "w_", "abp_", "umg_" }

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

-- Limits that keep one huge enum, struct or census from swamping the report or the server.
local MAX_ENUM_VALUES = 200
local MAX_STRUCT_FIELDS = 60
local MAX_CENSUS_CLASSES = 200
local CENSUS_PER_SECOND = 2

local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

-- UE4SS runs LoopAsync callbacks on a background thread without locking this mod's Lua state,
-- while game-thread callbacks and hooks use it at the same time; together they corrupt the
-- state and crash the server (twice on a live server, inside UE4SS). So timers run on the game
-- thread when this UE4SS has LoopInGameThreadWithDelay; on an older one the background thread
-- only hands the work over. The callback returns true to stop.
local function every(milliseconds, callback)
    if type(LoopInGameThreadWithDelay) == "function" then
        local handle
        handle = LoopInGameThreadWithDelay(milliseconds, function()
            local stop = callback()
            if stop == true and handle ~= nil and type(CancelDelayedAction) == "function" then
                CancelDelayedAction(handle)
            end
            return stop
        end)
        return handle
    end
    local stopped = false
    return LoopAsync(milliseconds, function()
        if not stopped then
            ExecuteInGameThread(function()
                if callback() == true then stopped = true end
            end)
        end
        return stopped
    end)
end

-- Optional probe-settings.lua in the mod folder (an old probe.lua is ignored on purpose) narrows the search to one topic:
--   return { title = "...", keywords = { ... }, nativeOnly = true, wholeClasses = { ... },
--            lateScanMinutes = 45, census = true }
-- nativeOnly skips Blueprint (/Game/) classes; wholeClasses lists every function of classes
-- whose name contains one of these words; lateScanMinutes = 45 scans again 45 minutes later
-- (off by default: the scan briefly freezes the server, which players would notice);
-- census = true also counts the live world objects of each topic (off by default: counting
-- touches live objects, which is riskier than reading class definitions).
local TITLE = "ExclsvProbe report"
local NATIVE_ONLY = false
local LATE_SCAN_MINUTES = 0
local CENSUS = false
do
    local source = string.gsub(debug.getinfo(1, "S").source or "", "^@", "")
    local dir = string.match(source, "^(.*)[/\\]Scripts[/\\]main%.lua$")
    local ok, settings = pcall(dofile, (dir or ".") .. "/probe-settings.lua")
    if ok and type(settings) == "table" then
        if type(settings.keywords) == "table" then
            TOPICS = { { name = "Matches", words = settings.keywords } }
        end
        TITLE = settings.title or TITLE
        NATIVE_ONLY = settings.nativeOnly == true
        WHOLE_CLASSES = settings.wholeClasses or WHOLE_CLASSES
        if type(settings.lateScanMinutes) == "number" then LATE_SCAN_MINUTES = settings.lateScanMinutes end
        CENSUS = settings.census == true
    end
end

local function fname(object)
    return safe(function() return object:GetFName():ToString() end) or "?"
end

local function lower(text)
    return string.lower(text or "")
end

-- Index of the first topic whose keyword appears in the name, or nil.
local function topicOf(name)
    local lowered = lower(name)
    for _, fragment in ipairs(IGNORED_FRAGMENTS) do
        lowered = string.gsub(lowered, fragment, " ")
    end
    for index, topic in ipairs(TOPICS) do
        for _, word in ipairs(topic.words) do
            if string.find(lowered, word, 1, true) then
                return index
            end
        end
    end
    return nil
end

local function isNoisy(path)
    if NATIVE_ONLY and string.sub(path, 1, 8) ~= "/Script/" then
        return true
    end
    for _, prefix in ipairs(NOISY_PREFIXES) do
        if string.sub(path, 1, #prefix) == prefix then
            return true
        end
    end

    local shortName = lower(string.match(path, "([^%./:]+)$"))
    for _, prefix in ipairs(NOISY_CLASS_PREFIXES) do
        if string.sub(shortName, 1, #prefix) == prefix then
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
-- entry is skipped instead of taking the whole scan down. Returns the items, whether the
-- iteration finished, and {item, second argument} pairs (enums pass name and value).
local function collect(owner, method)
    local pairsSeen = {}
    local ok = pcall(function()
        owner[method](owner, function(item, value)
            pairsSeen[#pairsSeen + 1] = { item, value }
        end)
    end)
    local items = {}
    for index, pair in ipairs(pairsSeen) do items[index] = pair[1] end
    return items, ok, pairsSeen
end

local function pathOf(object)
    local full = safe(function() return object:GetFullName() end)
    if full == nil then return nil end
    return string.match(full, "^%S+%s+(.+)$") or full
end

-- "StrProperty /Script/ConZ.Foo:Bar:Message" -> "StrProperty"
local function propertyType(property)
    local full = safe(function() return property:GetFullName() end) or ""
    return string.match(full, "^(%S+)%s") or "?"
end

local function describeFields(owner, limit)
    local fields = {}
    for _, property in ipairs((collect(owner, "ForEachProperty"))) do
        if limit and #fields >= limit then
            fields[#fields + 1] = "..."
            break
        end
        fields[#fields + 1] = fname(property) .. ": " .. propertyType(property)
    end
    return "(" .. table.concat(fields, ", ") .. ")"
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

local function newReport()
    local report = { topics = {}, whole = {}, otherEvents = {}, dataTables = {}, census = {}, censusList = {},
        classCount = 0, functionCount = 0, classMatches = 0 }
    for index = 1, #TOPICS do
        report.topics[index] = { classes = {}, functions = {}, properties = {}, events = {}, enums = {}, structs = {} }
    end
    return report
end

local function inspectClass(class, report)
    local classPath = pathOf(class)
    if classPath == nil then
        return
    end
    progress = classPath
    if isNoisy(classPath) then
        return
    end

    local className = fname(class)
    local classTopic = topicOf(className)
    if classTopic ~= nil then
        local parent = safe(function() return class:GetSuperStruct() end)
        local parentPath = parent ~= nil and pathOf(parent) or nil
        table.insert(report.topics[classTopic].classes, classPath .. (parentPath and ("  (parent: " .. parentPath .. ")") or ""))
        report.classMatches = report.classMatches + 1
        if TOPICS[classTopic].census and #report.censusList < MAX_CENSUS_CLASSES then
            table.insert(report.censusList, { name = className, path = classPath, topic = classTopic })
        end
    end

    local whole = false
    for _, word in ipairs(WHOLE_CLASSES) do
        if string.find(lower(className), word, 1, true) then whole = true end
    end

    for _, func in ipairs((collect(class, "ForEachFunction"))) do
        local name = fname(func)
        local topic = topicOf(name)
        if whole or topic ~= nil then
            progress = classPath .. ":" .. name
            local flags = safe(function() return func:GetFunctionFlags() end)
            local line = string.format("%s:%s %s\n    %s", classPath, name, describeFields(func), describeFlags(flags))
            table.insert(whole and report.whole or report.topics[topic].functions, line)
            report.functionCount = report.functionCount + 1
        end
    end

    -- Properties are only read from the class description: no object's value is touched.
    for _, property in ipairs((collect(class, "ForEachProperty"))) do
        local name = fname(property)
        local kind = propertyType(property)
        local topic = topicOf(name)
        local line = string.format("%s.%s: %s", classPath, name, kind)
        if string.find(kind, "Delegate", 1, true) then
            -- Events other code can listen to: one hook instead of polling every tick.
            table.insert(topic and report.topics[topic].events or report.otherEvents, line)
        elseif topic ~= nil then
            table.insert(report.topics[topic].properties, line)
        end
    end
end

local function inspectEnum(enum, report)
    local path = pathOf(enum)
    if path == nil or isNoisy(path) then return end
    local topic = topicOf(fname(enum))
    if topic == nil then return end

    local values = {}
    local _, ok, named = collect(enum, "ForEachName")
    if ok then
        for _, pair in ipairs(named) do
            if #values >= MAX_ENUM_VALUES then
                values[#values + 1] = "..."
                break
            end
            local name = type(pair[1]) == "string" and pair[1] or safe(function() return pair[1]:ToString() end) or "?"
            values[#values + 1] = pair[2] ~= nil and (name .. "=" .. tostring(pair[2])) or name
        end
    end
    table.insert(report.topics[topic].enums, path .. ": " .. (#values > 0 and table.concat(values, ", ") or "(values not readable)"))
end

local function inspectStruct(struct, report)
    local path = pathOf(struct)
    if path == nil or isNoisy(path) then return end
    local topic = topicOf(fname(struct))
    if topic == nil then return end
    table.insert(report.topics[topic].structs, path .. " " .. describeFields(struct, MAX_STRUCT_FIELDS))
end

-- Objects that are still loading or already being destroyed can have half-built member lists;
-- reading those crashes natively (pcall cannot catch it), so FindObjects leaves them out.
local function unsafeFlags()
    local flags = type(EObjectFlags) == "table" and EObjectFlags or {}
    return (flags.RF_NeedLoad or 0x400) | (flags.RF_NeedPostLoad or 0x1000)
        | (flags.RF_BeginDestroyed or 0x8000) | (flags.RF_FinishDestroyed or 0x10000)
end

-- Every object of a type (non-exact, so subclasses count too), searched on the C++ side.
-- filteredOnly: never fall back to a search that includes loading/destroyed objects.
local function findAll(className, filteredOnly)
    local noFlags = (type(EObjectFlags) == "table" and EObjectFlags.RF_NoFlags) or 0
    local found = safe(function() return FindObjects(0, className, nil, noFlags, unsafeFlags(), false) end)
    if not filteredOnly and (type(found) ~= "table" or next(found) == nil) then
        -- Some UE4SS builds may not take the flag filter; then search without it.
        found = safe(function() return FindObjects(0, className, nil, noFlags, noFlags, false) end)
        if type(found) == "table" and next(found) ~= nil then
            print(TAG .. "FindObjects ignored the loading/destroyed filter for " .. className .. "; searched without it.\n")
        end
    end
    local list = {}
    if type(found) == "table" then
        for _, object in pairs(found) do list[#list + 1] = object end
    end
    return list
end

local function render(report, pass)
    local lines = {
        TITLE,
        "Generated: " .. os.date("!%Y-%m-%d %H:%M:%S UTC") .. " (" .. pass .. ")",
        string.format("Classes scanned: %d, matching functions: %d, matching classes: %d", report.classCount, report.functionCount, report.classMatches),
        "",
        "How to read: Net/NetServer = callable over the network to the server; Exec = console command;",
        "BlueprintEvent/Native functions and Delegate properties can be hooked by a mod.",
        "",
        "== Summary ==",
    }
    for index, topic in ipairs(TOPICS) do
        local t = report.topics[index]
        lines[#lines + 1] = string.format("%s: %d classes, %d functions, %d properties, %d events, %d enums, %d structs",
            topic.name, #t.classes, #t.functions, #t.properties, #t.events, #t.enums, #t.structs)
    end

    local function section(title, entries)
        if #entries == 0 then return end
        table.sort(entries)
        lines[#lines + 1] = ""
        lines[#lines + 1] = title
        for _, entry in ipairs(entries) do lines[#lines + 1] = entry end
    end

    for index, topic in ipairs(TOPICS) do
        local t = report.topics[index]
        lines[#lines + 1] = ""
        lines[#lines + 1] = "######## " .. topic.name .. " ########"
        section("== Classes ==", t.classes)
        section("== Functions ==", t.functions)
        section("== Properties ==", t.properties)
        section("== Events (delegates) ==", t.events)
        section("== Enums ==", t.enums)
        section("== Structs ==", t.structs)
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "######## Other ########"
    section("== Key classes, every function ==", report.whole)
    section("== Other events (delegates) ==", report.otherEvents)
    section("== Data tables ==", report.dataTables)

    lines[#lines + 1] = ""
    if not CENSUS then
        lines[#lines + 1] = "== Census: off (census = true in probe-settings.lua turns it on) =="
    elseif report.censusDone then
        lines[#lines + 1] = "== Census (live objects right now; a count of 1 can be the class template) =="
        table.sort(report.census, function(a, b) return a.count > b.count or (a.count == b.count and a.path < b.path) end)
        for _, row in ipairs(report.census) do
            lines[#lines + 1] = string.format("%6d  %s  [%s]", row.count, row.path, TOPICS[row.topic].name)
        end
    else
        lines[#lines + 1] = "== Census: still counting, the report is written again when it is done =="
    end

    return lines
end

local function write(report, pass)
    local lines = render(report, pass)
    local path = outputPath()
    if path ~= nil then
        local file = io.open(path, "w")
        if file ~= nil then
            file:write(table.concat(lines, "\n") .. "\n")
            file:close()
            return path
        end
    end

    print(TAG .. "Could not write probe-output.txt, printing the report here instead.\n")
    for _, line in ipairs(lines) do
        print(TAG .. line .. "\n")
    end
    return nil
end

-- Counts the live objects of the matched world classes, a few per second so the server does
-- not stall, then writes the report again with the census. Only the number of objects is
-- read; none of them is touched. Objects still loading or being destroyed are left out (the
-- old FindAllOf count included them, which could crash the server), and each class is named
-- in UE4SS.log before it is counted so a crash can be traced to it.
local function runCensus(report, pass)
    if not CENSUS then return end
    local list = report.censusList
    local nextIndex = 1
    local queued = false

    local function finish()
        report.censusDone = true
        local total = 0
        for _, row in ipairs(report.census) do total = total + row.count end
        write(report, pass)
        print(TAG .. string.format("Census done: %d world objects across %d classes.\n", total, #report.census))
    end

    if #list == 0 then
        finish()
        return
    end

    every(1000, function()
        if nextIndex > #list then
            return true
        end
        if not queued then
            queued = true
            ExecuteInGameThread(function()
                queued = false
                for _ = 1, CENSUS_PER_SECOND do
                    local entry = list[nextIndex]
                    if entry == nil then break end
                    nextIndex = nextIndex + 1
                    progress = "census " .. entry.path
                    print(TAG .. "Counting " .. entry.path .. "\n")
                    local count = #findAll(entry.name, true)
                    if count > 0 then
                        table.insert(report.census, { path = entry.path, topic = entry.topic, count = count })
                    end
                end
                if nextIndex > #list then
                    finish()
                end
            end)
        end
        return nextIndex > #list
    end)
end

local function scan(pass)
    local report = newReport()

    -- FindObjects searches GUObjectArray on the C++ side. Class "Class" (not exact) covers
    -- native classes and Blueprint classes, which derive from it.
    local allClasses = {}
    local seen = {}
    local function add(class)
        local key = safe(function() return class:GetAddress() end) or class
        if class ~= nil and not seen[key] then
            seen[key] = true
            allClasses[#allClasses + 1] = class
        end
    end

    local found = findAll("Class")
    for _, class in ipairs(found) do add(class) end
    print(TAG .. string.format("FindObjects returned %d classes.\n", #found))

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
        if not pcall(inspectClass, class, report) then
            skipped = skipped + 1
        end
    end
    report.classCount = #allClasses
    if skipped > 0 then
        print(TAG .. string.format("Skipped %d classes that could not be read.\n", skipped))
    end

    for _, enum in ipairs(findAll("Enum")) do pcall(inspectEnum, enum, report) end
    for _, struct in ipairs(findAll("ScriptStruct")) do pcall(inspectStruct, struct, report) end
    for _, dataTable in ipairs(findAll("DataTable")) do
        local path = pathOf(dataTable)
        if path ~= nil and string.sub(path, 1, 6) == "/Game/" then
            table.insert(report.dataTables, path)
        end
    end

    local path = write(report, pass)
    print(TAG .. string.format("Scanned %d classes (%s): %d matching functions, %d matching classes.\n",
        report.classCount, pass, report.functionCount, report.classMatches))
    if path ~= nil then
        print(TAG .. "Full report written to " .. path .. "\n")
    end

    runCensus(report, pass)
end

-- Wait until the world (and with it SCUM's game mode) exists, then scan on the game thread;
-- scan again LATE_SCAN_MINUTES later to catch classes that load only when they appear.
local TICK_SECONDS = 10
local scans = 0
local queued = false
local attempts = 0
local firstScanAt = nil

every(TICK_SECONDS * 1000, function()
    attempts = attempts + 1

    if scans == 0 and attempts > 60 then
        print(TAG .. "Gave up: no game mode appeared within 10 minutes.\n")
        return true
    end
    if scans >= 2 or (scans == 1 and LATE_SCAN_MINUTES <= 0) then
        return true
    end
    if scans == 1 and (attempts - firstScanAt) * TICK_SECONDS < LATE_SCAN_MINUTES * 60 then
        return false
    end

    if not queued then
        queued = true
        ExecuteInGameThread(function()
            queued = false

            if scans == 0 then
                -- Blueprint classes load with the map, so prefer to wait for a game mode. Native
                -- classes exist from startup, so after two minutes scan regardless.
                local gameMode = safe(function() return FindFirstOf("GameModeBase") end)
                local ready = gameMode ~= nil and safe(function() return gameMode:IsValid() end)
                if not ready and attempts < 12 then
                    return
                end
                firstScanAt = attempts
            end

            scans = scans + 1
            local pass = scans == 1 and "first scan, world loaded" or ("second scan, " .. LATE_SCAN_MINUTES .. " min later")
            print(TAG .. "Scanning reflection data (read-only, " .. pass .. ")...\n")
            local ok, err = pcall(scan, pass)
            if not ok then
                print(TAG .. "Scan failed while reading " .. tostring(progress) .. ": " .. tostring(err) .. "\n")
            end
        end)
    end

    return false
end)

print(TAG .. "Loaded. Waiting for the world to load before scanning.\n")
