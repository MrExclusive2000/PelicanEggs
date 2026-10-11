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

local objects = {
    Function("/Script/ConZ.ConZPlayerController:Server_ProcessAdminCommand", 0x00220CC0, { { "Command", "StrProperty" } }),
    Function("/Script/ConZ.ConZGameMode:BroadcastServerMessage", 0x04000400, { { "Message", "StrProperty" }, { "Duration", "FloatProperty" } }),
    Function("/Script/Engine.PlayerController:ServerExec", 0x00220CC0, { { "Msg", "StrProperty" } }),
    Function("/Script/Engine.Actor:ReceiveTick", 0x08020800),               -- no keyword
    Function("/Script/Engine.Pawn:GetController", 0x54020401),              -- no keyword
    Function("/Script/UMG.Widget:ExecuteSomething", 0x04000400),            -- noisy module
    Function("/Script/Engine.SkeletalMeshComponent:ExecCommand", 0x400),    -- engine class not of interest
    Object("Class", "/Script/ConZ.AdminCommandManager"),
    Object("Class", "/Script/ConZ.Weapon"),                                 -- no keyword
    Object("Package", "/Script/ConZ"),                                      -- not a class/function
    -- A broken object: every call errors. The probe must survive it.
    setmetatable({}, { __index = function() error("access violation") end }),
}

-- ------------------------------------------------------------------ fake UE4SS globals
loopTicks = 0
local log = {}
local scannedAtTick = nil
function print(text)
    table.insert(log, text)
    if string.find(text, "scanning reflection data", 1, true) then scannedAtTick = loopTicks end
end
function ForEachUObject(callback)
    for index, object in ipairs(objects) do callback(object, 0, index) end
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
check("non-matching class skipped", string.find(report, "ConZ.Weapon", 1, true) == nil)
check("counts", string.find(report, "Objects scanned: 11, matching functions: 3, matching classes: 1", 1, true) ~= nil)

local logText = table.concat(log)
check("summary logged", string.find(logText, "3 matching functions, 1 matching classes", 1, true) ~= nil)
check("report path logged", string.find(logText, "probe-output.txt", 1, true) ~= nil)

-- Second scenario: the game mode never appears, so the probe scans after 2 minutes anyway.
log, loopTicks, findCalls, gameModeAvailableAfter, scannedAtTick = {}, 0, 0, math.huge, nil
dofile(copy)
check("fallback scan after 12 ticks (2 minutes)", scannedAtTick == 12)
check("fallback scan ran", string.find(table.concat(log), "scanning reflection data", 1, true) ~= nil)

os.execute("rm -rf '" .. tmp .. "'")
print = _G.print
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
