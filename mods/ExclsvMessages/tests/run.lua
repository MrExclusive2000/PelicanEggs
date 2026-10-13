--[[
    Runs main.lua against a fake UE4SS runtime. Run from the repo root:
        lua5.4 mods/ExclsvMessages/tests/run.lua
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
local hud = {}
local gameModeAvailable = true
local gameMode = object()
function gameMode:SendHUDMessageToAll(message, beep) assert(beep == false) hud[#hud + 1] = message end
-- UE4SS FindObjects: object searches must leave out objects still loading or being destroyed.
function FindObjects(count, className, name, required, banned, exact)
    if className == "Class" then return {} end
    local unsafe = 0x400 | 0x1000 | 0x8000 | 0x10000
    assert(banned & unsafe == unsafe, "object searches must leave out objects being destroyed")
    if banned & (0x10 | 0x20) == 0 then templateSearches = (templateSearches or 0) + 1 end
    liveSearches = (liveSearches or 0) + 1
    return FindAllOf(className) or {}
end
function FindFirstOf(className)
    if className == "World" then return world end
    if className == "ConZGameMode" and gameModeAvailable then return gameMode end
end
function StaticFindObject(path)
    if path == "/Script/SCUM.Default__MiscStatics" and processorAvailable then return processor end
    return nil
end
function ExecuteInGameThread(callback) callback() end
local tick
-- UE4SS game-thread timer; LoopAsync would run Lua on a background thread.
function LoopAsync() error("timers must run on the game thread (LoopInGameThreadWithDelay)") end
function LoopInGameThreadWithDelay(delay, callback) assert(delay == 1000) tick = callback end

-- ------------------------------------------------------------------ mod copy
local tmp = os.tmpname()
os.remove(tmp)
local mods = tmp .. "/Mods"
local dir = mods .. "/ExclsvMessages"
os.execute("mkdir -p '" .. dir .. "/Scripts' '" .. mods .. "/ExclsvConsole'")
local source = assert(io.open("mods/ExclsvMessages/Scripts/main.lua")):read("a")
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
assert(io.open(mods .. "/ExclsvConsole/console.log", "w")):close()
writeConfig(assert(io.open("mods/ExclsvMessages/config.lua")):read("a"))
dofile(dir .. "/Scripts/main.lua")
local consoleLog = function() return read(mods .. "/ExclsvConsole/console.log") end
check("startup summary", string.find(consoleLog(), "Active. Welcome on, 1 announcement(s) every 30 min, join/leave log on, 0 restart time(s).", 1, true) ~= nil)

-- A player connects; the name arrives a moment later, the character later still.
local alice = Player("", nil)
players = { alice }
advance(5)
check("no join logged before the name is known", string.find(consoleLog(), "joined", 1, true) == nil)

alice.name = "Alice"
advance(5)
check("join logged to console", string.find(consoleLog(), "Alice joined.", 1, true) ~= nil)
check("join logged to players.log with date", string.find(read(dir .. "/players.log"), "%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d %[ExclsvMessages%] Alice joined%.") ~= nil)
check("no join announcement by default", #commands == 0 and #hud == 0)

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
check("announcement after interval", hud[1] == "Server rules: no cheating, no exploiting, respect other players.")
check("announcement not sent as an admin command", #commands == 0)

-- Leave.
players = {}
advance(5)
check("leave logged", string.find(consoleLog(), "Alice left.", 1, true) ~= nil)

local before = #hud
advance(31 * 60)
check("no announcements to an empty server", #hud == before)

-- ------------------------------------------------------------------ scenario 2: custom config
players, commands, private, hud, clock = {}, {}, {}, {}, 5000
os.remove(mods .. "/ExclsvConsole/console.log")
writeConfig([[return {
    welcome = "",
    joinAnnouncement = "{name} joined ({players} online)",
    intervalMinutes = 1,
    announcements = { "One", "Two" },
    onlyWhenPlayersOnline = false,
    logJoinsAndLeaves = false,
}]])
dofile(dir .. "/Scripts/main.lua")
check("no Pelican console mirror without ExclsvConsole", read(mods .. "/ExclsvConsole/console.log") == "")

local bob = Player("Bob", Pawn("BP_Prisoner_C"))
players = { bob, Player("Carol", nil) }
advance(5)
check("join announced with count", hud[1] == "Bob joined (2 online)")
advance(20)
check("welcome off", #private == 0)

players = {}
local logSize = #read(dir .. "/players.log")
advance(5)
check("join/leave log off", #read(dir .. "/players.log") == logSize)

local start = #hud
advance(60)
advance(60)
advance(60)
check("rotation wraps", hud[start + 1] == "One" and hud[start + 2] == "Two" and hud[start + 3] == "One")

-- Without a game mode, the announcement is not shown and the log says so (no admin command).
gameModeAvailable = false
advance(60)
check("no game mode: reported, no admin command", #commands == 0 and string.find(table.concat(log), "Could not show the announcement (the game world is not ready): Two", 1, true) ~= nil)
gameModeAvailable = true

-- ------------------------------------------------------------------ restart warnings and reload
-- clock 0 is 00:00:00 UTC; restart at 01:00 ("25:00" is invalid and ignored).
players, hud, clock = {}, {}, 0
writeConfig([[return { restartTimes = { "01:00", "25:00" }, restartWarnings = { 30, 5 }, restartMessage = "Restart in {minutes} min!" }]])
dofile(dir .. "/Scripts/main.lua")
advance(29 * 60)
check("no warning too early", #hud == 0)
advance(60)
check("30 minute warning", hud[1] == "Restart in 30 min!")
advance(25 * 60)
check("5 minute warning, each once", hud[2] == "Restart in 5 min!" and #hud == 2)
-- 00:55 -> next day 00:31, passing 00:30.
advance(23 * 3600 + 36 * 60)
check("next day warned again", hud[3] == "Restart in 30 min!")

writeConfig([[return { restartTimes = { "23:00" }, restartWarnings = { 1 } }]])
advance(31)
check("settings reloaded", string.find(table.concat(log), "Settings reloaded.", 1, true) ~= nil)
hud = {}
-- Now 00:31:31; pass 22:59.
advance(22 * 3600 + 28 * 60)
check("reloaded restart time used", hud[1] == "Server restart in 1 minute(s).")

-- ------------------------------------------------------------------ scenario 3: failures
players, commands, private, clock, log = {}, {}, {}, 9000, {}
writeConfig([[return { announcements = {}, joinAnnouncement = "{name} joined" }]])
processorAvailable = false
gameModeAvailable = false
sendFails = true
dofile(dir .. "/Scripts/main.lua")
local dave = Player("Dave", Pawn("BP_Prisoner_C"))
players = { dave }
advance(20)
local logText = table.concat(log)
check("announcement without a game world reported", string.find(logText, "Could not show the announcement (the game world is not ready): Dave joined", 1, true) ~= nil)
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

-- ------------------------------------------------------------------ scenario 4: a UE4SS that cannot filter
-- FindObjects finds nothing with the filter although a player is online: fall back to FindAllOf.
writeConfig("return {}")
log, sendFails, processorAvailable, gameModeAvailable = {}, false, true, true
local savedFindObjects, savedFindFirst = FindObjects, FindFirstOf
function FindObjects() return {} end
function FindFirstOf(className)
    if className == "ConZPlayerController" then return players[1] end
    return savedFindFirst(className)
end
dofile(dir .. "/Scripts/main.lua")
players = { Player("Frank", Pawn("BP_Prisoner_C")) }
advance(20)
check("unfiltered fallback announced", string.find(table.concat(log), "cannot leave out objects being destroyed; using FindAllOf", 1, true) ~= nil)
check("players still found on the fallback", string.find(read(dir .. "/players.log"), "Frank joined", 1, true) ~= nil)
FindObjects, FindFirstOf = savedFindObjects, savedFindFirst

os.execute("rm -rf '" .. tmp .. "'")
check("player searches leave out objects being destroyed (FindObjects, not FindAllOf)", (liveSearches or 0) > 0)
check("player searches leave out class default objects and archetypes", templateSearches == nil)
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
