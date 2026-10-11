--[[
    Runs main.lua against a fake UE4SS runtime. Run from the repo root:
        lua5.4 mods/ScumAntiCheat/tests/run.lua
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

local function FString(value) return { ToString = function() return value end } end

local function Pawn(class, x, y, z)
    local pawn = object({ class = class, x = x, y = y, z = z, teleporting = false, parent = nil })
    function pawn:GetClass() local c = self.class return { GetFName = function() return { ToString = function() return c end } end } end
    function pawn:K2_GetActorLocation() return { X = self.x * 100, Y = self.y * 100, Z = self.z * 100 } end
    function pawn:GetAttachParentActor() return self.parent end
    function pawn:IsTeleportInProgress() return self.teleporting end
    return pawn
end

local function Player(name, pawn)
    local controller = object({ pawn = pawn, admin = false, teleporting = false })
    controller.PlayerState = { GetPlayerName = function() return FString(name) end }
    function controller:K2_GetPawn() return self.pawn end
    function controller:IsUserAdmin() return self.admin end
    function controller:IsTeleportInProgress() return self.teleporting end
    return controller
end

-- ------------------------------------------------------------------ fake UE4SS globals
local players = {}
local clock = 100
local kicks, adminCommands = {}, {}
local kickWorks = true
local log = {}

function print(text) log[#log + 1] = text end
local world = object()
local gameMode = object()
function gameMode:KickPlayer(controller, reason)
    if not kickWorks then error("no") end
    kicks[#kicks + 1] = { controller = controller, reason = reason }
    return true
end
local statics = object()
function statics:GetRealTimeSeconds(w) assert(w == world) return clock end
local processor = object()
function processor:Test_ProcessAdminCommand(_, command) adminCommands[#adminCommands + 1] = command end

function FindAllOf(className)
    if className == "ConZPlayerController" or className == "PlayerController" then return players end
    return nil
end
function FindFirstOf(className)
    if className == "World" then return world end
    if className == "BP_ConZGameMode_C" then return gameMode end
    return nil
end
function StaticFindObject(path)
    if path == "/Script/Engine.Default__GameplayStatics" then return statics end
    if path == "/Script/SCUM.Default__MiscStatics" then return processor end
    return nil
end
function ExecuteInGameThread(callback) callback() end
local tick
function LoopAsync(delay, callback) assert(delay == 1000) tick = callback end

-- ------------------------------------------------------------------ mod copy
local tmp = os.tmpname()
os.remove(tmp)
local mods = tmp .. "/Mods"
local dir = mods .. "/ScumAntiCheat"
os.execute("mkdir -p '" .. dir .. "/Scripts' '" .. mods .. "/PelicanConsole'")
local source = assert(io.open("mods/ScumAntiCheat/Scripts/main.lua")):read("a")
assert(io.open(dir .. "/Scripts/main.lua", "w")):write(source):close()

local function writeConfig(text) assert(io.open(dir .. "/config.lua", "w")):write(text):close() end
local function read(path)
    local file = io.open(path)
    if not file then return "" end
    local text = file:read("a")
    file:close()
    return text
end
local function acLog() return read(dir .. "/anticheat.log") end
local function step(seconds) clock = clock + (seconds or 1) tick() end
local function reset()
    players, kicks, adminCommands, log, clock = {}, {}, {}, {}, 100
    os.remove(dir .. "/anticheat.log")
    os.remove(mods .. "/PelicanConsole/console.log")
end

-- ------------------------------------------------------------------ scenario 1: defaults (log only)
assert(io.open(mods .. "/PelicanConsole/console.log", "w")):close()
writeConfig(assert(io.open("mods/ScumAntiCheat/config.lua")):read("a"))
dofile(dir .. "/Scripts/main.lua")

check("loop registered", tick ~= nil)
check("startup line in anticheat.log", string.find(acLog(), "Active. action=log, foot limit 15 m/s", 1, true) ~= nil)
check("startup line mirrored to Pelican console", string.find(read(mods .. "/PelicanConsole/console.log"), "Active.", 1, true) ~= nil)

local walker = Player("Walker", Pawn("BP_Prisoner_C", 0, 0, 0))
local speeder = Player("Speeder", Pawn("BP_Prisoner_C", 1000, 0, 0))
players = { walker, speeder }

tick()                                   -- first sample, nothing to compare yet
for _ = 1, 3 do
    walker.pawn.x = walker.pawn.x + 6     -- sprinting
    speeder.pawn.x = speeder.pawn.x + 40  -- 40 m/s on foot
    step()
end
local text = acLog()
check("walker never flagged", string.find(text, "Walker", 1, true) == nil)
check("speeder flagged with speed", string.find(text, "Speeder: moving 40.0 m/s on foot (limit 15)", 1, true) ~= nil)
check("strikes counted", string.find(text, "[strike 3/3]", 1, true) ~= nil)
check("log mode does not kick", #kicks == 0 and string.find(text, "nothing was done", 1, true) ~= nil)
check("watching count logged", string.find(table.concat(log), "Watching 2 player(s).", 1, true) ~= nil)

-- Vehicles get the higher limit.
local driver = Player("Driver", Pawn("BPC_Dirtbike_C", 5000, 0, 0))
players = { driver }
tick()
for _ = 1, 3 do driver.pawn.x = driver.pawn.x + 50 step() end
check("50 m/s in a vehicle is fine", string.find(acLog(), "Driver", 1, true) == nil)

-- Passengers are attached to the vehicle.
local passenger = Player("Passenger", Pawn("BP_Prisoner_C", 8000, 0, 0))
passenger.pawn.parent = object()
players = { passenger }
tick()
for _ = 1, 2 do passenger.pawn.x = passenger.pawn.x + 50 step() end
check("attached prisoner treated as passenger", string.find(acLog(), "Passenger", 1, true) == nil)

-- Falling / parachuting players are skipped.
local skydiver = Player("Skydiver", Pawn("BP_Prisoner_C", 0, 9000, 2000))
players = { skydiver }
tick()
for _ = 1, 3 do skydiver.pawn.y = skydiver.pawn.y + 30; skydiver.pawn.z = skydiver.pawn.z - 50 step() end
check("falling skipped", string.find(acLog(), "Skydiver", 1, true) == nil)

-- Teleports.
local jumper = Player("Jumper", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { jumper }
tick()
jumper.pawn.x = 2000 step()
check("teleport flagged", string.find(acLog(), "Jumper: teleported 2000 m in 1.0 s", 1, true) ~= nil)

local summoned = Player("Summoned", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { summoned }
tick()
summoned.teleporting = true
summoned.pawn.x = 5000 step()
check("game teleport ignored", string.find(acLog(), "Summoned", 1, true) == nil)

local admin = Player("Admin", Pawn("BP_Prisoner_C", 0, 0, 0))
admin.admin = true
players = { admin }
tick()
admin.pawn.x = 5000 step()
check("admins ignored", string.find(acLog(), "Admin:", 1, true) == nil)

-- Respawn: new pawn far away is not a teleport.
local respawner = Player("Respawner", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { respawner }
tick()
respawner.pawn = Pawn("BP_Prisoner_C", 9000, 9000, 0) step()
respawner.pawn.x = respawner.pawn.x + 5 step()
check("respawn not flagged", string.find(acLog(), "Respawner", 1, true) == nil)

-- Server hitch: a long gap is discarded, not compared.
local lagger = Player("Lagger", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { lagger }
tick()
lagger.pawn.x = 400 step(30)
check("long gap ignored", string.find(acLog(), "Lagger", 1, true) == nil)

-- Dead player (no pawn) and a broken object don't stop the loop.
local dead = Player("Dead", nil)
local broken = setmetatable({}, { __index = function() error("access violation") end })
local stillChecked = Player("StillChecked", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { dead, broken, stillChecked }
tick()
stillChecked.pawn.x = 1000 step()
check("others still checked past broken objects", string.find(acLog(), "StillChecked: teleported", 1, true) ~= nil)

-- ------------------------------------------------------------------ scenario 2: kick mode
reset()
writeConfig([[return { action = "kick", strikesToAct = 2, maxFootSpeed = 10, ignoreNames = { "friend" } }]])
dofile(dir .. "/Scripts/main.lua")
check("custom config applied", string.find(acLog(), "action=kick, foot limit 10 m/s", 1, true) ~= nil)
check("no Pelican console mirror without PelicanConsole", read(mods .. "/PelicanConsole/console.log") == "")

local cheater = Player("Cheater", Pawn("BP_Prisoner_C", 0, 0, 0))
local friend = Player("Friend", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { cheater, friend }
tick()
for _ = 1, 2 do cheater.pawn.x = cheater.pawn.x + 20; friend.pawn.x = friend.pawn.x + 20 step() end
check("kicked via game mode", #kicks == 1 and kicks[1].controller == cheater)
check("kick reason passed", kicks[1] and string.find(kicks[1].reason, "anti-cheat", 1, true) ~= nil)
check("kick logged", string.find(acLog(), "Kicked Cheater.", 1, true) ~= nil)
check("ignored names (case-insensitive) skipped", string.find(acLog(), "Friend", 1, true) == nil)

-- Strikes outside the window expire.
local slow = Player("Slow", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { slow }
tick()
slow.pawn.x = 20 step()
for _ = 1, 60 do step() end            -- stands still for a minute
slow.pawn.x = slow.pawn.x + 20 step()
check("old strikes expire", string.find(acLog(), "Slow: moving 20.0 m/s on foot (limit 10) at 40, 0, 0 [strike 1/2]", 1, true) ~= nil)

-- KickPlayer fails: falls back to the admin command.
kickWorks = false
local other = Player("Other", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { other }
tick()
for _ = 1, 2 do other.pawn.x = other.pawn.x + 20 step() end
check("falls back to #Kick", adminCommands[1] == "#Kick Other")

-- ------------------------------------------------------------------ scenario 3: broken config
reset()
writeConfig("return {")
dofile(dir .. "/Scripts/main.lua")
check("broken config reported", string.find(acLog(), "config.lua could not be read, using defaults", 1, true) ~= nil)
check("defaults used", string.find(acLog(), "action=log, foot limit 15", 1, true) ~= nil)

writeConfig([[return { action = "ban" }]])
dofile(dir .. "/Scripts/main.lua")
check("unknown action falls back to log", string.find(acLog(), "Unknown action 'ban'", 1, true) ~= nil)

os.execute("rm -rf '" .. tmp .. "'")
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
