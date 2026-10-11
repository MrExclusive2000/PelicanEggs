--[[
    Runs main.lua against a fake UE4SS runtime and a fake SCUM folder. Run from the repo root:
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
    pawn.CharacterMovement = object({ MovementMode = 1 })
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
os.time = function() return clock end   -- file refreshes use os.time
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

-- SCUM's game logs are listed with "dir"; answer from a table instead.
local gameLogFiles = {}
local popenCommands = {}
io.popen = function(command)
    popenCommands[#popenCommands + 1] = command
    local prefix = string.match(command, "\\([%a_]+)%*%.log")
    local name = gameLogFiles[prefix]
    return { read = function() return name end, close = function() end }
end

-- ------------------------------------------------------------------ fake SCUM folder
local tmp = os.tmpname()
os.remove(tmp)
local scum = tmp .. "/SCUM"
local mods = scum .. "/Binaries/Win64/ue4ss/Mods"
local dir = mods .. "/ScumAntiCheat"
local configDir = scum .. "/Saved/Config/WindowsServer"
local gameLogDir = scum .. "/Saved/SaveFiles/Logs"
os.execute("mkdir -p '" .. dir .. "/Scripts' '" .. mods .. "/PelicanConsole' '" .. configDir .. "' '" .. scum .. "/Saved/Logs' '" .. gameLogDir .. "'")
local source = assert(io.open("mods/ScumAntiCheat/Scripts/main.lua")):read("a")
assert(io.open(dir .. "/Scripts/main.lua", "w")):write(source):close()

local function write(path, text, mode) assert(io.open(path, mode or "w")):write(text):close() end
local function read(path)
    local file = io.open(path)
    if not file then return "" end
    local text = file:read("a")
    file:close()
    return text
end
local function utf16(text) return "\255\254" .. string.gsub(text, ".", "%0\0") end
local function acLog() return read(dir .. "/anticheat.log") end
local function has(text, needle) return string.find(text, needle, 1, true) ~= nil end
local function step(seconds) clock = clock + (seconds or 1) tick() end
local function login(id, name) write(scum .. "/Saved/Logs/SCUM.log", "LogSCUM: '1.2.3.4 " .. id .. ":" .. name .. "(2)' logged in at: X=1 Y=2 Z=3\n", "a") end
local function start(configText)
    players, kicks, adminCommands, log, clock = {}, {}, {}, {}, 100
    os.remove(dir .. "/anticheat.log")
    write(dir .. "/config.lua", configText)
    dofile(dir .. "/Scripts/main.lua")
end

write(configDir .. "/AdminUsers.ini", utf16("76561198000000001[SetGodMode]\r\n"))
write(configDir .. "/BannedUsers.ini", "76561198000000099")
write(scum .. "/Saved/Logs/SCUM.log", "Log file open\n")
write(mods .. "/PelicanConsole/console.log", "")

-- ------------------------------------------------------------------ scenario 1: shipped config (log only)
start(read("mods/ScumAntiCheat/config.lua"))
check("loop registered", tick ~= nil)
check("startup line lists checks", has(acLog(), "Active. action=log, 3 strikes in 60 s. Checks: speed, teleport, flying, hovering, mapBounds, unauthorizedAdmin, names, watchlist, gameLogs."))
check("startup line mirrored to Pelican console", has(read(mods .. "/PelicanConsole/console.log"), "Active."))

local walker = Player("Walker", Pawn("BP_Prisoner_C", 0, 0, 0))
local speeder = Player("Speeder", Pawn("BP_Prisoner_C", 1000, 0, 0))
login("76561198000000002", "Speeder")
players = { walker, speeder }
tick()
for _ = 1, 3 do
    walker.pawn.x = walker.pawn.x + 6
    speeder.pawn.x = speeder.pawn.x + 40
    step()
end
local text = acLog()
check("walker never flagged", not has(text, "Walker"))
check("speeder flagged with SteamID from SCUM.log", has(text, "Speeder (76561198000000002): moving 40.0 m/s on foot (limit 15)"))
check("strikes counted", has(text, "[strike 3/3]"))
check("log mode does not kick", #kicks == 0 and has(text, "reached 3 strikes. action = \"log\", so nothing was done."))
check("watching count logged", has(table.concat(log), "Watching 2 player(s)."))

-- Vehicles get the higher limit; passengers are attached to the vehicle.
local driver = Player("Driver", Pawn("BPC_Dirtbike_C", 5000, 0, 0))
local passenger = Player("Passenger", Pawn("BP_Prisoner_C", 3000, 0, 0))
passenger.pawn.parent = object()
players = { driver, passenger }
tick()
for _ = 1, 3 do driver.pawn.x = driver.pawn.x + 50; passenger.pawn.x = passenger.pawn.x + 50 step() end
check("50 m/s in a vehicle is fine", not has(acLog(), "Driver"))
check("attached prisoner treated as passenger", not has(acLog(), "Passenger"))

-- Falling / parachuting players are skipped by the speed check and are not hovering.
local skydiver = Player("Skydiver", Pawn("BP_Prisoner_C", 0, 1000, 2000))
skydiver.pawn.CharacterMovement.MovementMode = 3
players = { skydiver }
tick()
for _ = 1, 12 do skydiver.pawn.y = skydiver.pawn.y + 30; skydiver.pawn.z = skydiver.pawn.z - 50 step() end
check("falling skipped", not has(acLog(), "Skydiver"))

-- Hovering: falling mode without losing height.
local hover = Player("Hover", Pawn("BP_Prisoner_C", 0, 0, 200))
hover.pawn.CharacterMovement.MovementMode = 3
players = { hover }
tick()
for _ = 1, 7 do step() end
check("short hover not flagged", not has(acLog(), "Hover"))
step()
check("hovering flagged after 8 s", has(acLog(), "Hover: hovering in the air for 8 s at 0, 0, 200 [strike 1/3]"))

-- Flying mode (fly hack); a short ladder climb is fine.
local ladder = Player("Ladder", Pawn("BP_Prisoner_C", 0, 0, 0))
local flyer = Player("Flyer", Pawn("BP_Prisoner_C", 100, 0, 0))
players = { ladder, flyer }
tick()
ladder.pawn.CharacterMovement.MovementMode = 5
flyer.pawn.CharacterMovement.MovementMode = 5
for _ = 1, 5 do step() end
ladder.pawn.CharacterMovement.MovementMode = 1
for _ = 1, 6 do step() end
check("short flying (ladder) not flagged", not has(acLog(), "Ladder"))
check("flying flagged after 10 s", has(acLog(), "Flyer: flying for 10 s"))

-- Outside the island and under the map; repeated only every 5 s.
local outside = Player("Outside", Pawn("BP_Prisoner_C", 8000, 0, 0))
local under = Player("Under", Pawn("BP_Prisoner_C", 0, 0, -500))
players = { outside, under }
tick()
for _ = 1, 4 do step() end
local outsideText = acLog()
check("outside the map flagged", has(outsideText, "Outside: outside the map at 8000, 0, 0 [strike 1/3]"))
check("below the map flagged", has(outsideText, "Under: below the map at 0, 0, -500 [strike 1/3]"))
check("bounds strike not repeated within 5 s", not has(outsideText, "Outside: outside the map at 8000, 0, 0 [strike 2/3]"))
step()
check("bounds strike repeats after 5 s", has(acLog(), "Outside: outside the map at 8000, 0, 0 [strike 2/3]"))

-- Teleports, game teleports and admins.
local jumper = Player("Jumper", Pawn("BP_Prisoner_C", 0, 0, 0))
local summoned = Player("Summoned", Pawn("BP_Prisoner_C", 0, 0, 0))
local admin = Player("RealAdmin", Pawn("BP_Prisoner_C", 0, 0, 0))
admin.admin = true
login("76561198000000001", "RealAdmin")
players = { jumper, summoned, admin }
tick()
jumper.pawn.x = 2000
summoned.teleporting = true
summoned.pawn.x = 5000
admin.pawn.x = 5000
step()
text = acLog()
check("teleport flagged", has(text, "Jumper: teleported 2000 m in 1.0 s"))
check("game teleport ignored", not has(text, "Summoned"))
check("admin in AdminUsers.ini (UTF-16, with permissions) ignored", not has(text, "RealAdmin"))

-- Admin rights without being in AdminUsers.ini.
local rogue = Player("Rogue", Pawn("BP_Prisoner_C", 0, 0, 0))
rogue.admin = true
login("76561198000000003", "Rogue")
players = { rogue }
tick()
text = acLog()
check("unauthorized admin flagged", has(text, "Rogue (76561198000000003) has admin rights but is not in AdminUsers.ini."))
check("unauthorized admin acted on", has(text, "Rogue (76561198000000003): unauthorized admin rights. action = \"log\""))
rogue.pawn.x = 5000
step()
check("unauthorized admin is not exempt from checks", has(acLog(), "Rogue (76561198000000003): teleported"))

-- Staff impersonation, but not for real admins.
local fake = Player("Server ADMIN", Pawn("BP_Prisoner_C", 0, 0, 0))
local realNamed = Player("AdminBob", Pawn("BP_Prisoner_C", 0, 0, 0))
realNamed.admin = true
login("76561198000000001", "AdminBob")
players = { fake, realNamed }
tick()
step()
text = acLog()
check("impersonating name flagged once", has(text, "Server ADMIN: name contains 'admin'") and select(2, string.gsub(text, "name contains 'admin'", "")) == 1)
check("real admin with admin in name not flagged", not has(text, "AdminBob"))

-- Respawn and server hitches.
local respawner = Player("Respawner", Pawn("BP_Prisoner_C", 0, 0, 0))
local lagger = Player("Lagger", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { respawner, lagger }
tick()
respawner.pawn = Pawn("BP_Prisoner_C", 3000, 3000, 0)
step()
lagger.pawn.x = 400
step(30)
check("respawn not flagged", not has(acLog(), "Respawner"))
check("long gap ignored", not has(acLog(), "Lagger"))

-- Players still connecting (no name), dead players and broken objects don't stop the loop.
local connecting = Player("", Pawn("BP_Prisoner_C", 0, 0, 0))
local dead = Player("Dead", nil)
local broken = setmetatable({}, { __index = function() error("access violation") end })
local stillChecked = Player("StillChecked", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { connecting, dead, broken, stillChecked }
tick()
stillChecked.pawn.x = 1000
step()
check("others still checked past broken objects", has(acLog(), "StillChecked: teleported"))

-- ------------------------------------------------------------------ scenario 2: kick, escalate to ban
start([[return { action = "kick", strikesToAct = 2, banAfterKicks = 2, maxFootSpeed = 10, ignoreNames = { "friend" }, ignoreSteamIds = { "76561198000000005" }, watchlist = { "76561198000000004" } }]])
check("custom config applied, nested defaults kept", has(acLog(), "Active. action=kick, 2 strikes in 60 s. Checks: speed, teleport"))

local cheater = Player("Cheater", Pawn("BP_Prisoner_C", 0, 0, 0))
local friend = Player("Friend", Pawn("BP_Prisoner_C", 0, 0, 0))
local trusted = Player("Trusted", Pawn("BP_Prisoner_C", 0, 0, 0))
login("76561198000000004", "Cheater")
login("76561198000000005", "Trusted")
players = { cheater, friend, trusted }
tick()
check("watchlisted player announced", has(acLog(), "Watchlisted player online: Cheater (76561198000000004)."))
for _ = 1, 2 do
    cheater.pawn.x = cheater.pawn.x + 20; friend.pawn.x = friend.pawn.x + 20; trusted.pawn.x = trusted.pawn.x + 20
    step()
end
check("kicked via game mode", #kicks == 1 and kicks[1].controller == cheater)
check("kick reason passed", kicks[1] and has(kicks[1].reason, "anti-cheat"))
check("kick logged with SteamID", has(acLog(), "Kicked Cheater (76561198000000004): reached 2 strikes."))
check("ignored name skipped", not has(acLog(), "Friend"))
check("ignored SteamID skipped", not has(acLog(), "Trusted"))
check("kick counted in offenses.txt", has(read(dir .. "/offenses.txt"), "76561198000000004 1"))
check("not banned after first kick", not has(read(configDir .. "/BannedUsers.ini"), "76561198000000004"))

for _ = 1, 2 do cheater.pawn.x = cheater.pawn.x + 20 step() end
local banned = read(configDir .. "/BannedUsers.ini")
check("banned after second kick", has(banned, "76561198000000099\n76561198000000004\n"))
check("ban logged", has(acLog(), "Banned Cheater (76561198000000004) (added to BannedUsers.ini)"))
check("kicked again with the ban", #kicks == 2)

-- Strikes outside the window expire.
local slow = Player("Slow", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { slow }
tick()
slow.pawn.x = 20 step()
for _ = 1, 60 do step() end
slow.pawn.x = slow.pawn.x + 20 step()
check("old strikes expire", has(acLog(), "Slow: moving 20.0 m/s on foot (limit 10) at 40, 0, 0 [strike 1/2]"))

-- KickPlayer fails: falls back to the admin command.
kickWorks = false
local other = Player("Other", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { other }
tick()
for _ = 1, 2 do other.pawn.x = other.pawn.x + 20 step() end
check("falls back to #Kick", adminCommands[1] == "#Kick Other")
kickWorks = true

-- ------------------------------------------------------------------ scenario 3: ban action and game logs
write(gameLogDir .. "/violations_1.log", utf16("old violation before start\n"))
gameLogFiles.violations_ = "violations_1.log"
gameLogFiles.admin_ = "admin_1.log"
write(gameLogDir .. "/admin_1.log", "")
start([[return { action = "ban", strikesToAct = 1, strikeOnGameViolations = true }]])
check("game logs listed with dir", has(popenCommands[#popenCommands], 'dir /b /o-d "'))
check("old game log lines skipped", not has(acLog(), "old violation"))

local banMe = Player("BanMe", Pawn("BP_Prisoner_C", 0, 0, 0))
local reported = Player("Reported", Pawn("BP_Prisoner_C", 0, 0, 0))
login("76561198000000006", "BanMe")
login("76561198000000007", "Reported")
players = { banMe, reported }
tick()
write(gameLogDir .. "/violations_1.log", utf16("2026.10.11-12.40.00: Ammo count mismatch 76561198000000007\n"), "a")
write(gameLogDir .. "/admin_1.log", "2026.10.11-12.40.00: '76561198000000001:Admin(1)' Command: 'ListPlayers'\n", "a")
banMe.pawn.x = 1000
step()
text = acLog()
check("ban action bans immediately", has(read(configDir .. "/BannedUsers.ini"), "76561198000000006"))
check("game violation shown (UTF-16 decoded)", has(text, "SCUM violation: 2026.10.11-12.40.00: Ammo count mismatch 76561198000000007"))
check("admin command shown", has(text, "SCUM admin command: 2026.10.11-12.40.00: '76561198000000001:Admin(1)' Command: 'ListPlayers'"))
check("game violation counted as strike", has(text, "Reported (76561198000000007): SCUM reported:"))

-- A new game log file (after SCUM rotates it) is read from the start.
gameLogFiles.violations_ = "violations_2.log"
write(gameLogDir .. "/violations_2.log", "first line of new file\n")
step(61)
check("new game log read in full", has(acLog(), "SCUM violation: first line of new file"))

-- ------------------------------------------------------------------ scenario 4: broken config
start("return {")
check("broken config reported", has(acLog(), "config.lua could not be read, using defaults"))
check("defaults used", has(acLog(), "action=log"))
start([[return { action = "nuke" }]])
check("unknown action falls back to log", has(acLog(), "Unknown action 'nuke'"))

os.execute("rm -rf '" .. tmp .. "'")
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
