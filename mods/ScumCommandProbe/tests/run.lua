--[[
    Runs main.lua against a fake UE4SS runtime. Run from the repo root:
        lua5.4 mods/ScumCommandProbe/tests/run.lua
]]

local failures, count = 0, 0
local function check(name, condition)
    count = count + 1
    if not condition then
        failures = failures + 1
        io.stdout:write("FAIL: " .. name .. "\n")
    end
end

-- ------------------------------------------------------------------ fake UE4SS objects
local function FName(text) return { ToString = function() return text end } end

local function Property(typeName, owner, name)
    return {
        GetFName = function() return FName(name) end,
        GetFullName = function() return typeName .. " " .. owner .. ":" .. name end,
    }
end

local function Object(className, fullPath, extra)
    local name = string.match(fullPath, "[:%.]([^:%.]+)$")
    local object = {
        GetClass = function() return { GetFName = function() return FName(className) end } end,
        GetFName = function() return FName(name) end,
        GetFullName = function() return className .. " " .. fullPath end,
        IsValid = function() return true end,
    }
    for key, value in pairs(extra or {}) do object[key] = value end
    return object
end

local function Function(fullPath, flags, params)
    return Object("Function", fullPath, {
        GetFunctionFlags = function() return flags end,
        ForEachProperty = function(_, callback)
            for _, p in ipairs(params or {}) do
                if callback(Property(p[2], fullPath, p[1])) then break end
            end
        end,
    })
end

local function Class(className, fullPath, functions)
    return Object(className, fullPath, {
        ForEachFunction = function(_, callback)
            for _, f in ipairs(functions or {}) do
                if callback(f) then break end
            end
        end,
    })
end

local nativeClasses = {
    Class("Class", "/Script/ConZ.ConZPlayerController", {
        Function("/Script/ConZ.ConZPlayerController:Server_ProcessAdminCommand", 0x00220CC0, { { "Command", "StrProperty" } }),
        Function("/Script/ConZ.ConZPlayerController:GetInventory", 0x04020401),   -- no keyword
    }),
    Class("Class", "/Script/ConZ.ConZGameMode", {
        Function("/Script/ConZ.ConZGameMode:BroadcastServerMessage", 0x04000400, { { "Message", "StrProperty" }, { "Duration", "FloatProperty" } }),
    }),
    Class("Class", "/Script/Engine.PlayerController", {
        Function("/Script/Engine.PlayerController:ServerExec", 0x00220CC0, { { "Msg", "StrProperty" } }),
    }),
    Class("Class", "/Script/UMG.Widget", {                                         -- noisy module
        Function("/Script/UMG.Widget:ExecuteSomething", 0x04000400),
    }),
    Class("Class", "/Script/Engine.SkeletalMeshComponent", {                       -- engine class not of interest
        Function("/Script/Engine.SkeletalMeshComponent:ExecCommand", 0x400),
    }),
    Class("Class", "/Script/ConZ.AdminCommandManager", {}),
    -- Stored values: admin rights are reported, unrelated ones are not.
    Object("Class", "/Script/ConZ.ConZPlayerState", {
        ForEachFunction = function() end,
        ForEachProperty = function(_, callback)
            callback(Property("BoolProperty", "/Script/ConZ.ConZPlayerState", "bIsServerAdmin"))
            callback(Property("FloatProperty", "/Script/ConZ.ConZPlayerState", "Health"))
        end,
    }),
    Class("Class", "/Script/ConZ.Weapon", {}),                                     -- no keyword
    -- A class whose function list throws mid-iteration: must be skipped, not fatal.
    Object("Class", "/Script/ConZ.BrokenChatThing", {
        ForEachFunction = function() error("access violation") end,
    }),
    -- A completely unreadable object.
    setmetatable({}, { __index = function() error("access violation") end }),
}

local blueprintClasses = {
    Class("BlueprintGeneratedClass", "/Game/ConZ/BP_AdminTools.BP_AdminTools_C", {
        Function("/Game/ConZ/BP_AdminTools.BP_AdminTools_C:KickPlayer", 0x00020400, { { "PlayerId", "StrProperty" } }),
    }),
}

-- ------------------------------------------------------------------ fake UE4SS globals
loopTicks = 0
local log = {}
local scannedAtTick = nil
function print(text)
    table.insert(log, text)
    if string.find(text, "scanning reflection data", 1, true) then scannedAtTick = loopTicks end
end
function ForEachUObject() error("the probe must not walk every object") end
-- Real UE4SS: FindAllOf never returns class definitions, only live instances.
function FindAllOf() return nil end
local findObjectsWorks = true
function FindObjects(count, className, objectName, banned, required, exact)
    if not findObjectsWorks then return {} end
    assert(count == 0 and className == "Class" and objectName == nil and exact == false)
    local all = {}
    for _, c in ipairs(nativeClasses) do all[#all + 1] = c end
    for _, c in ipairs(blueprintClasses) do all[#all + 1] = c end
    return all
end
function StaticFindObject(path)
    for _, c in ipairs(nativeClasses) do
        local ok, full = pcall(function() return c:GetFullName() end)
        if ok and full == "Class " .. path then return c end
    end
    return { IsValid = function() return false end }
end
local gameModeAvailableAfter = 2
local findCalls = 0
function FindFirstOf(name)
    findCalls = findCalls + 1
    if name == "GameModeBase" and findCalls >= gameModeAvailableAfter then
        return Object("BP_ConZGameMode_C", "/Game/ConZ.Default__BP_ConZGameMode_C")
    end
    return nil
end
function ExecuteInGameThread(callback) callback() end
function LoopAsync(_, callback)
    for _ = 1, 100 do
        loopTicks = loopTicks + 1
        if callback() then return end
    end
end

-- Write the report into a temp copy of the mod so the real folder is untouched.
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p '" .. tmp .. "/ScumCommandProbe/Scripts'")
local source = assert(io.open("mods/ScumCommandProbe/Scripts/main.lua")):read("a")
local copy = tmp .. "/ScumCommandProbe/Scripts/main.lua"
assert(io.open(copy, "w")):write(source):close()

dofile(copy)

local reportFile = io.open(tmp .. "/ScumCommandProbe/probe-output.txt")
check("report file written", reportFile ~= nil)
local report = reportFile and reportFile:read("a") or ""

check("waited for the game mode before scanning", scannedAtTick == 2)
check("admin command function listed with parameter",
    string.find(report, "/Script/ConZ.ConZPlayerController:Server_ProcessAdminCommand (Command: StrProperty)", 1, true) ~= nil)
check("server RPC flags decoded", string.find(report, "Net,NetReliable,Native,BlueprintEvent,NetServer", 1, true) ~= nil)
check("two parameters listed", string.find(report, "(Message: StrProperty, Duration: FloatProperty)", 1, true) ~= nil)
check("engine PlayerController kept", string.find(report, "/Script/Engine.PlayerController:ServerExec", 1, true) ~= nil)
check("non-matching function skipped", string.find(report, "ReceiveTick", 1, true) == nil)
check("noisy module skipped", string.find(report, "/Script/UMG", 1, true) == nil)
check("uninteresting engine class skipped", string.find(report, "SkeletalMeshComponent", 1, true) == nil)
check("matching class listed", string.find(report, "/Script/ConZ.AdminCommandManager", 1, true) ~= nil)
check("admin rights property listed", string.find(report, "/Script/ConZ.ConZPlayerState.bIsServerAdmin: BoolProperty", 1, true) ~= nil)
check("unrelated property skipped", string.find(report, ".Health:", 1, true) == nil)
check("non-matching class skipped", string.find(report, "ConZ.Weapon", 1, true) == nil)
check("blueprint function listed", string.find(report, "/Game/ConZ/BP_AdminTools.BP_AdminTools_C:KickPlayer (PlayerId: StrProperty)", 1, true) ~= nil)
check("broken class still listed by name, others unaffected", string.find(report, "/Script/ConZ.BrokenChatThing", 1, true) ~= nil)
check("counts", string.find(report, "Classes scanned: 11, matching functions: 4, matching classes: 3", 1, true) ~= nil)

local logText = table.concat(log)
check("FindObjects count logged", string.find(logText, "FindObjects returned 11 classes", 1, true) ~= nil)
check("summary logged", string.find(logText, "4 matching functions, 3 matching classes", 1, true) ~= nil)
check("class names are not false matches (playeRCONtroller)", string.find(report, "== Classes ==\n/Game/ConZ/BP_AdminTools.BP_AdminTools_C\n/Script/ConZ.AdminCommandManager\n/Script/ConZ.BrokenChatThing\n", 1, true) ~= nil)
check("report path logged", string.find(logText, "probe-output.txt", 1, true) ~= nil)

-- Second scenario: the game mode never appears, so the probe scans after 2 minutes anyway.
log, loopTicks, findCalls, gameModeAvailableAfter, scannedAtTick = {}, 0, 0, math.huge, nil
dofile(copy)
check("fallback scan after 12 ticks (2 minutes)", scannedAtTick == 12)
check("fallback scan ran", string.find(table.concat(log), "scanning reflection data", 1, true) ~= nil)

-- Third scenario: FindObjects returns nothing, so the fallback looks classes up by path.
log, loopTicks, findCalls, gameModeAvailableAfter, scannedAtTick, findObjectsWorks = {}, 0, 0, 1, nil, false
dofile(copy)
local fallbackReport = assert(io.open(tmp .. "/ScumCommandProbe/probe-output.txt")):read("a")
check("fallback lookup logged", string.find(table.concat(log), "Fallback lookup found 1 of 6 known classes", 1, true) ~= nil)
check("fallback still reports PlayerController functions", string.find(fallbackReport, "/Script/Engine.PlayerController:ServerExec", 1, true) ~= nil)

-- Fourth scenario: probe.lua narrows the topic, skips Blueprints and lists whole classes.
assert(io.open(tmp .. "/ScumCommandProbe/probe.lua", "w")):write([[return {
    title = "Item probe", keywords = { "inventory" }, nativeOnly = true, wholeClasses = { "gamemode" },
}]]):close()
log, loopTicks, findCalls, gameModeAvailableAfter, scannedAtTick, findObjectsWorks = {}, 0, 0, 1, nil, true
dofile(copy)
local itemReport = assert(io.open(tmp .. "/ScumCommandProbe/probe-output.txt")):read("a")
check("probe.lua title", string.sub(itemReport, 1, 11) == "Item probe\n")
check("probe.lua keywords", string.find(itemReport, "ConZPlayerController:GetInventory", 1, true) ~= nil
    and string.find(itemReport, "Server_ProcessAdminCommand", 1, true) == nil)
check("probe.lua whole class listed", string.find(itemReport, "ConZGameMode:BroadcastServerMessage", 1, true) ~= nil)
check("probe.lua native only", string.find(itemReport, "BP_AdminTools", 1, true) == nil)

os.execute("rm -rf '" .. tmp .. "'")
print = _G.print
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
