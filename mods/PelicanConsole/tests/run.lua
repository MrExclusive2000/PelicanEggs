--[[
    Runs main.lua against a fake UE4SS runtime. Run from the repo root:
        lua5.4 mods/PelicanConsole/tests/run.lua
]]

local failures, count = 0, 0
local function check(name, condition)
    count = count + 1
    if not condition then
        failures = failures + 1
        io.stdout:write("FAIL: " .. name .. "\n")
    end
end

-- ------------------------------------------------------------------ fake UE4SS runtime
local calls = {}
local processorValid, worldAvailable, processorFails = true, true, false

local processor = {
    IsValid = function() return processorValid end,
    Test_ProcessAdminCommand = function(_, context, command)
        if processorFails then error("access violation") end
        calls[#calls + 1] = { context = context, command = command }
    end,
}
local world = { IsValid = function() return true end, name = "World" }

local log = {}
function print(text) log[#log + 1] = text end
function StaticFindObject(path)
    if path == "/Script/SCUM.Default__MiscStatics" then return processor end
    return { IsValid = function() return false end }
end
function FindFirstOf(className)
    if worldAvailable and className == "World" then return world end
    return nil
end
local gameThreadRuns = 0
function ExecuteInGameThread(callback) gameThreadRuns = gameThreadRuns + 1; callback() end
local loopCallback, loopDelay
function LoopAsync(delay, callback) loopDelay, loopCallback = delay, callback end

-- Run a temp copy of the mod so the real folder is untouched.
local tmp = os.tmpname()
os.remove(tmp)
local dir = tmp .. "/PelicanConsole"
os.execute("mkdir -p '" .. dir .. "/Scripts'")
local source = assert(io.open("mods/PelicanConsole/Scripts/main.lua")):read("a")
local copy = dir .. "/Scripts/main.lua"
assert(io.open(copy, "w")):write(source):close()

local function writeCommands(text, file)
    assert(io.open(dir .. "/" .. (file or "commands.txt"), "a")):write(text):close()
end
local function exists(file)
    local handle = io.open(dir .. "/" .. file)
    if handle then handle:close() return true end
    return false
end
local function consoleLog()
    local handle = io.open(dir .. "/console.log")
    if not handle then return "" end
    local text = handle:read("a")
    handle:close()
    return text
end

-- Commands left over from before the start must be dropped, not run.
writeCommands("ShutdownServer\n")
writeCommands("Stale\n", "commands.processing")

dofile(copy)

check("loop registered every second", loopDelay == 1000 and loopCallback ~= nil)
check("stale commands.txt removed at startup", not exists("commands.txt"))
check("stale commands.processing removed at startup", not exists("commands.processing"))
check("ready message in console.log", string.find(consoleLog(), "[PelicanConsole] Ready.", 1, true) ~= nil)
check("ready message printed to UE4SS log", string.find(table.concat(log), "Ready.", 1, true) ~= nil)

-- Nothing queued: nothing runs and the loop keeps going.
check("loop keeps running", loopCallback() == false)
check("no commands, no calls", #calls == 0 and gameThreadRuns == 0)

-- Typed commands, with and without "#", blank lines and Windows line endings.
writeCommands("ListPlayers\n\n   \n#Announce Hello world\r\n##SetTime 12\n")
loopCallback()
check("three commands run", #calls == 3)
check("prefix added", calls[1] and calls[1].command == "#ListPlayers")
check("existing prefix kept once, CR trimmed", calls[2] and calls[2].command == "#Announce Hello world")
check("repeated prefix collapsed", calls[3] and calls[3].command == "#SetTime 12")
check("world passed as context", calls[1] and calls[1].context == world)
check("run on the game thread", gameThreadRuns == 3)
check("queue file consumed", not exists("commands.txt") and not exists("commands.processing"))
check("result logged", string.find(consoleLog(), "Ran: #ListPlayers", 1, true) ~= nil)
check("log lines timestamped", string.find(consoleLog(), "%d%d:%d%d:%d%d %[PelicanConsole%] Ran: #ListPlayers") ~= nil)

-- Same commands are not replayed on the next tick.
loopCallback()
check("commands run once", #calls == 3)

-- A leftover processing file (e.g. from a crash mid-read) must not block new commands.
writeCommands("Leftover\n", "commands.processing")
writeCommands("ListPlayers\n")
loopCallback()
check("new commands still run after leftover processing file", #calls == 4)

-- Game call throws: reported, not fatal.
processorFails = true
writeCommands("Kick Bob\n")
loopCallback()
check("failure reported", string.find(consoleLog(), "Failed: #Kick Bob (", 1, true) ~= nil)
processorFails = false

-- World not loaded yet.
worldAvailable = false
writeCommands("ListPlayers\n")
loopCallback()
check("world missing reported", string.find(consoleLog(), "game world is not loaded yet", 1, true) ~= nil)
check("no call without a world", #calls == 4)
worldAvailable = true

-- Processor missing (game update renamed it).
processorValid = false
writeCommands("ListPlayers\n")
loopCallback()
check("processor missing reported", string.find(consoleLog(), "admin command processor was not found", 1, true) ~= nil)
check("no call without a processor", #calls == 4)
processorValid = true

-- Falls back to the game mode if the world lookup gives nothing.
local gameMode = { IsValid = function() return true end }
function FindFirstOf(className)
    if className == "BP_ConZGameMode_C" then return gameMode end
    return nil
end
writeCommands("ListPlayers\n")
loopCallback()
check("game mode used as fallback context", calls[5] and calls[5].context == gameMode)

-- Started from an unexpected path: disabled with a message instead of erroring.
log, loopCallback = {}, nil
local strayPath = tmp .. "/stray.lua"
assert(io.open(strayPath, "w")):write(source):close()
dofile(strayPath)
check("unknown folder disables the mod", loopCallback == nil)
check("unknown folder reported", string.find(table.concat(log), "Could not work out the mod folder", 1, true) ~= nil)

os.execute("rm -rf '" .. tmp .. "'")
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
