--[[
    Runs main.lua against a fake UE4SS runtime. Run from the repo root:
        lua5.4 mods/ServerMessages/tests/run.lua
]]

local failures, count = 0, 0
local function check(name, condition)
    count = count + 1
    if not condition then
        failures = failures + 1
        io.stdout:write("FAIL: " .. name .. "\n")
    end
end

-- ------------------------------------------------------------------ fake game objects
local nextAddress = 0
local function object(fields)
    nextAddress = nextAddress + 1
    local o = { address = nextAddress, valid = true }
    function o:IsValid() return self.valid end
    function o:GetAddress() return self.address end
    for key, value in pairs(fields or {}) do o[key] = value end
    return o
end

local private = {}
local sendFails = false
local function Pawn(class)
    local pawn = object({ class = class })
    function pawn:GetClass() local c = self.class return { GetFName = function() return { ToString = function() return c end } end } end
    function pawn:SendMessageToClient(message, audio)
        if sendFails then error("no") end
        private[#private + 1] = { pawn = self, message = message, audio = audio }
    end
    return pawn
end

local function Player(name, pawn)
    local controller = object({ name = name, pawn = pawn })
    controller.PlayerState = { GetPlayerName = function() return { ToString = function() return controller.name end } end }
    function controller:K2_GetPawn() return self.pawn end
    return controller
end

-- ------------------------------------------------------------------ fake UE4SS globals
local players = {}
local clock = 1000
local commands = {}
local log = {}
local processorAvailable = true

os.time = function() return clock end
function print(text) log[#log + 1] = text end
local world = object()
local processor = object()
function processor:Test_ProcessAdminCommand(context, command)
    assert(context == world)
    commands[#commands + 1] = command
end
function FindAllOf(className)
    if className == "ConZPlayerController" then return players end
    return nil
end
function FindFirstOf(className) if className == "World" then return world end end
function StaticFindObject(path)
    if path == "/Script/SCUM.Default__MiscStatics" and processorAvailable then return processor end
    return nil
end
function ExecuteInGameThread(callback) callback() end
local tick
function LoopAsync(delay, callback) assert(delay == 1000) tick = callback end

-- ------------------------------------------------------------------ mod copy
local tmp = os.tmpname()
os.remove(tmp)
local mods = tmp .. "/Mods"
local dir = mods .. "/ServerMessages"
os.execute("mkdir -p '" .. dir .. "/Scripts' '" .. mods .. "/PelicanConsole'")
local source = assert(io.open("mods/ServerMessages/Scripts/main.lua")):read("a")
assert(io.open(dir .. "/Scripts/main.lua", "w")):write(source):close()

local function writeConfig(text) assert(io.open(dir .. "/config.lua", "w")):write(text):close() end
local function read(path)
    local file = io.open(path)
    if not file then return "" end
    local text = file:read("a")
    file:close()
    return text
end
local function advance(seconds)
    -- The mod scans every 5 seconds; tick once per second like UE4SS does.
    for _ = 1, seconds do clock = clock + 1 tick() end
end

-- ------------------------------------------------------------------ scenario 1: shipped config
assert(io.open(mods .. "/PelicanConsole/console.log", "w")):close()
writeConfig(assert(io.open("mods/ServerMessages/config.lua")):read("a"))
dofile(dir .. "/Scripts/main.lua")
local consoleLog = function() return read(mods .. "/PelicanConsole/console.log") end
check("startup summary", string.find(consoleLog(), "Active. Welcome on, 1 announcement(s) every 30 min, join/leave log on.", 1, true) ~= nil)

-- A player connects; the name arrives a moment later, the character later still.
local alice = Player("", nil)
players = { alice }
advance(5)
check("no join logged before the name is known", string.find(consoleLog(), "joined", 1, true) == nil)

alice.name = "Alice"
advance(5)
check("join logged to console", string.find(consoleLog(), "Alice joined.", 1, true) ~= nil)
check("join logged to players.log with date", string.find(read(dir .. "/players.log"), "%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d %[ServerMessages%] Alice joined%.") ~= nil)
check("no join announcement by default", #commands == 0)

alice.pawn = Pawn("BP_Prisoner_C")
advance(5)
check("welcome waits after spawn", #private == 0)
advance(10)
check("welcome sent once", #private == 1)
check("welcome personalised", private[1] and private[1].message == "Welcome to the server, Alice! Be fair, have fun.")
check("welcome sent to the character", private[1] and private[1].pawn == alice.pawn)
advance(30)
check("welcome not repeated", #private == 1)

-- Announcements: first one after the interval, then rotating.
advance(30 * 60)
check("announcement after interval", commands[1] == "#Announce Server rules: no cheating, no exploiting, respect other players.")

-- Leave.
players = {}
advance(5)
check("leave logged", string.find(consoleLog(), "Alice left.", 1, true) ~= nil)

local before = #commands
advance(31 * 60)
check("no announcements to an empty server", #commands == before)

-- ------------------------------------------------------------------ scenario 2: custom config
players, commands, private, clock = {}, {}, {}, 5000
os.remove(mods .. "/PelicanConsole/console.log")
writeConfig([[return {
    welcome = "",
    joinAnnouncement = "{name} joined ({players} online)",
    intervalMinutes = 1,
    announcements = { "One", "Two" },
    onlyWhenPlayersOnline = false,
    logJoinsAndLeaves = false,
    commandPrefix = "",
}]])
dofile(dir .. "/Scripts/main.lua")
check("no Pelican console mirror without PelicanConsole", read(mods .. "/PelicanConsole/console.log") == "")

local bob = Player("Bob", Pawn("BP_Prisoner_C"))
players = { bob, Player("Carol", nil) }
advance(5)
check("join announced with count and prefix setting", commands[1] == "Announce Bob joined (2 online)")
advance(20)
check("welcome off", #private == 0)

players = {}
local logSize = #read(dir .. "/players.log")
advance(5)
check("join/leave log off", #read(dir .. "/players.log") == logSize)

local start = #commands
advance(60)
advance(60)
advance(60)
check("rotation wraps", commands[start + 1] == "Announce One" and commands[start + 2] == "Announce Two" and commands[start + 3] == "Announce One")

-- ------------------------------------------------------------------ scenario 3: failures
players, commands, private, clock, log = {}, {}, {}, 9000, {}
writeConfig([[return { announcements = {}, joinAnnouncement = "{name} joined" }]])
processorAvailable = false
sendFails = true
dofile(dir .. "/Scripts/main.lua")
local dave = Player("Dave", Pawn("BP_Prisoner_C"))
players = { dave }
advance(20)
local logText = table.concat(log)
check("missing processor reported", string.find(logText, "admin command processor is not available; cannot send: #Announce Dave joined", 1, true) ~= nil)
check("default welcome off when config omits it", string.find(logText, "Could not send the welcome", 1, true) == nil)

writeConfig([[return { welcome = "Hi {name}" }]])
dofile(dir .. "/Scripts/main.lua")
players = { Player("Erin", Pawn("BP_Prisoner_C")) }
advance(20)
check("failed private message reported", string.find(table.concat(log), "Could not send the welcome message to Erin.", 1, true) ~= nil)

writeConfig("return {")
log = {}
dofile(dir .. "/Scripts/main.lua")
check("broken config reported", string.find(table.concat(log), "config.lua could not be read, using defaults", 1, true) ~= nil)

os.execute("rm -rf '" .. tmp .. "'")
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
