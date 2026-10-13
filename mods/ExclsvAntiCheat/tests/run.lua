--[[
    Runs main.lua against a fake UE4SS runtime and a fake SCUM folder. Run from the repo root:
        lua5.4 mods/ExclsvAntiCheat/tests/run.lua
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
    controller.yaw, controller.pitch = 0, 0
    function controller:GetControlRotation() return { Yaw = self.yaw, Pitch = self.pitch } end
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
os.clock = function() return clock end  -- movement and aim timing
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
    if className == "BP_ConZGameMode_C" then return gameMode end
    return nil
end
function StaticFindObject(path)
    if path == "/Script/Engine.Default__GameplayStatics" then return statics end
    if path == "/Script/SCUM.Default__MiscStatics" then return processor end
    return nil
end
function ExecuteInGameThread(callback) callback() end
local tick, aimTick
-- UE4SS game-thread timer; LoopAsync would run Lua on a background thread.
function LoopAsync() error("timers must run on the game thread (LoopInGameThreadWithDelay)") end
function LoopInGameThreadWithDelay(delay, callback)
    if delay == 1000 then tick = callback elseif delay == 100 then aimTick = callback else error("unexpected delay " .. delay) end
end

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
local dir = mods .. "/ExclsvAntiCheat"
local configDir = scum .. "/Saved/Config/WindowsServer"
local gameLogDir = scum .. "/Saved/SaveFiles/Logs"
os.execute("mkdir -p '" .. dir .. "/Scripts' '" .. mods .. "/ExclsvConsole' '" .. configDir .. "' '" .. scum .. "/Saved/Logs' '" .. gameLogDir .. "'")
local source = assert(io.open("mods/ExclsvAntiCheat/Scripts/main.lua")):read("a")
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
write(mods .. "/ExclsvConsole/console.log", "")

-- ------------------------------------------------------------------ scenario 1: shipped config (log only)
start(read("mods/ExclsvAntiCheat/config.lua"))
check("loop registered", tick ~= nil)
check("startup line lists checks", has(acLog(), "Active. action=log, 3 strikes in 60 s. Checks: speed, teleport, flying, hovering, mapBounds, unauthorizedAdmin, names, watchlist, gameLogs, killLog, aimSnap, magicBullet, adminLog."))
check("startup line mirrored to Pelican console", has(read(mods .. "/ExclsvConsole/console.log"), "Active."))

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
check("speeder flagged with SteamID from SCUM.log", has(text, "Speeder (76561198000000002): moving 40.0 m/s on foot (limit 21)"))
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
local paid = Player("Paid Traveller", Pawn("BP_Prisoner_C", 0, 0, 0))
admin.admin = true
login("76561198000000001", "RealAdmin")
players = { jumper, summoned, admin, paid }
tick()
jumper.pawn.x = 2000
summoned.teleporting = true
summoned.pawn.x = 5000
admin.pawn.x = 5000
-- A teleport made by ExclsvPlayerTools or ExclsvConsole is announced in allowed_teleports.txt.
write(dir .. "/allowed_teleports.txt", clock .. " Paid Traveller\n", "a")
paid.pawn.x = 5000
step()
text = acLog()
check("teleport by our own mods ignored", not has(text, "Paid Traveller"))
check("allowed teleports file consumed", read(dir .. "/allowed_teleports.txt") == "")
check("teleport flagged", has(text, "Jumper: teleported 2000 m in 1.0 s"))
check("game teleport ignored", not has(text, "Summoned"))
check("admin in AdminUsers.ini (UTF-16, with permissions) ignored", not has(text, "RealAdmin"))

-- A passenger's character rides attached to the vehicle; its position jumps about while seated
-- and when getting out. That is not a teleport. Once settled on foot, a real teleport still counts.
local rider = Player("Rider", Pawn("BP_Prisoner_C", 0, 0, 0))
local car = Pawn("BPC_Rager_C", 0, 0, 0)
players = { rider }
tick()
rider.pawn.parent = car
step()
rider.pawn.x = 2000
step()
rider.pawn.x = 4000
step()
rider.pawn.parent = nil
rider.pawn.x = 6000
step()
rider.pawn.x = 6015
step()
check("passenger not flagged while riding or getting out", not has(acLog(), "Rider"))
step(5)
rider.pawn.x = 1000
step()
check("teleport on foot after settling still flagged", has(acLog(), "Rider: teleported 5015 m"))

-- A pilot possesses the plane: high up and fast is fine, and so is the ground covered while the
-- server stalls for a few seconds. A jump no plane could make still counts.
local pilot = Player("Pilot", Pawn("BPC_Airplane_C", 0, 0, 1500))
players = { pilot }
tick()
for _ = 1, 3 do pilot.pawn.x = pilot.pawn.x + 80 step() end
pilot.pawn.x = pilot.pawn.x + 320
step(4)
check("plane flying fast and high not flagged", not has(acLog(), "Pilot"))
pilot.pawn.x = pilot.pawn.x + 900
step()
check("jump no plane could make reported", has(acLog(), "Possible vehicle glitch, not counted as a strike: Pilot: teleported 900 m"))

-- Vehicles get extra room past the map edge; on foot the edge is where it is.
local flyer = Player("Flyer", Pawn("BPC_Airplane_C", 6600, 0, 1500))
local swimmer = Player("Swimmer", Pawn("BP_Prisoner_C", 6690, 0, 0))
players = { flyer, swimmer }
tick()
flyer.pawn.x = 6680; swimmer.pawn.x = 6695
step()
flyer.pawn.x = 6760
step()
check("plane just past the map edge not flagged", not has(acLog(), "Flyer: outside the map"))
check("player on foot past the map edge flagged", has(acLog(), "Swimmer: outside the map"))
flyer.pawn.x = 9700; flyer.teleporting = true
step()
flyer.teleporting = false
for _ = 1, 3 do flyer.pawn.x = flyer.pawn.x + 80 step() end
check("plane far past the margin flagged", has(acLog(), "Flyer: outside the map"))

-- Dying and respawning: the new body can sit at the very address the dead one had. Its
-- creation time differs, so it is a new character, not a teleport.
local reborn = Player("Reborn", Pawn("BP_Prisoner_C", -2000, -2000, 0))
reborn.pawn.CreationTime = 100
players = { reborn }
tick()
step()
reborn.pawn.x, reborn.pawn.y, reborn.pawn.CreationTime = 4000, 3000, 900   -- same object/address, new body
step()
step()
check("respawn at the same address not a teleport", not has(acLog(), "Reborn"))
step(6)
reborn.pawn.x = 6000
step()
check("teleport after respawning still flagged", has(acLog(), "Reborn: teleported"))

-- Vehicles are never asked for functions only characters have (UE4SS name lookups on objects
-- that lack the name are its least-tested path).
local driverCar = Pawn("BPC_WolfsWagen_C", 0, -5000, 0)
local askedCar = false
driverCar.IsTeleportInProgress = function() askedCar = true return false end
local driver = Player("Driver", driverCar)
players = { driver }
tick()
driverCar.x = 10
step()
check("vehicle not asked IsTeleportInProgress", not askedCar)

-- A glitching car jumps about: reported, but not a strike unless vehicleMovementStrikes is on.
local glitcher = Player("Glitcher", Pawn("BPC_Rager_C", 0, -3000, 0))
players = { glitcher }
tick()
glitcher.pawn.x = 900
step()
glitcher.pawn.x = 0
step()
check("car glitch reported", has(acLog(), "Possible vehicle glitch, not counted as a strike: Glitcher"))
check("car glitch not a strike", not string.find(acLog(), "Glitcher: teleported[^\n]*%[strike"))

-- A passed-out body ragdolls (no movement mode of its own) and gets thrown out of the car.
local sleeper = Player("Sleeper", Pawn("BP_Prisoner_C", 0, -4000, 0))
players = { sleeper }
tick()
sleeper.pawn.CharacterMovement.MovementMode = 0
sleeper.pawn.x = 900
step()
sleeper.pawn.x = 1800
step()
sleeper.pawn.CharacterMovement.MovementMode = 1
step()
sleeper.pawn.x = 1805
step()
check("unconscious body thrown about not flagged", not has(acLog(), "Sleeper"))
step(5)
sleeper.pawn.x = 3000
step()
check("teleport after waking up still flagged", has(acLog(), "Sleeper: teleported"))

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

-- KickPlayer fails: said so (SCUM ignores admin commands sent without an admin, so no fallback).
kickWorks = false
local other = Player("Other", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { other }
tick()
for _ = 1, 2 do other.pawn.x = other.pawn.x + 20 step() end
check("failed kick reported, no admin command sent", has(acLog(), "Could not kick Other") and adminCommands[1] == nil)
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
write(gameLogDir .. "/admin_1.log", "2026.10.11-12.39.00: Game version: 1.3.4.2.161892\n2026.10.11-12.40.00: '76561198000000001:Admin(1)' Command: 'ListPlayers'\n", "a")
banMe.pawn.x = 1000
step()
text = acLog()
check("ban action bans immediately", has(read(configDir .. "/BannedUsers.ini"), "76561198000000006"))
check("game violation shown (UTF-16 decoded)", has(text, "SCUM violation: 2026.10.11-12.40.00: Ammo count mismatch 76561198000000007"))
check("admin log header skipped", not has(text, "Game version"))
check("admin command shown", has(text, "SCUM admin command: 2026.10.11-12.40.00: '76561198000000001:Admin(1)' Command: 'ListPlayers'"))
check("game violation counted as strike", has(text, "Reported (76561198000000007): SCUM reported:"))

-- A command ExclsvConsole ran for a regular player (no-admin route) is allowed, exactly once.
local payee = Player("Payee", Pawn("BP_Prisoner_C", 0, 0, 0))
login("76561198000000012", "Payee")
players = { payee }
tick()
write(dir .. "/allowed_commands.txt", clock .. " ChangeCurrencyBalance Normal 1 76561198000000012\n", "a")
write(gameLogDir .. "/admin_1.log", "2026.10.11-12.40.30: '76561198000000012:Payee(4)' Command: 'ChangeCurrencyBalance Normal 1 76561198000000012'\n", "a")
step()
step()
check("command run by our console allowed", has(acLog(), "Allowed: run by ExclsvConsole without an admin")
    and not has(acLog(), "Payee (76561198000000012) ran an admin command") and not has(read(configDir .. "/BannedUsers.ini"), "76561198000000012"))
check("allowed commands file consumed", read(dir .. "/allowed_commands.txt") == "")
write(gameLogDir .. "/admin_1.log", "2026.10.11-12.40.40: '76561198000000012:Payee(4)' Command: 'ChangeCurrencyBalance Normal 1 76561198000000012'\n", "a")
step()
step()
check("the same command again is not allowed", has(acLog(), "Payee (76561198000000012) ran an admin command but is not in AdminUsers.ini"))

-- An admin command in SCUM's admin log from a player who is not in AdminUsers.ini.
local rogueAdmin = Player("Sneaky", Pawn("BP_Prisoner_C", 0, 0, 0))
login("76561198000000009", "Sneaky")
players = { rogueAdmin }
tick()
write(gameLogDir .. "/admin_1.log", "2026.10.11-12.41.00: '76561198000000009:Sneaky(3)' Command: 'SpawnItem Weapon_M82A1'\n", "a")
step()
step()
check("admin command from a non-admin acted on", has(acLog(), "Sneaky (76561198000000009) ran an admin command but is not in AdminUsers.ini")
    and has(read(configDir .. "/BannedUsers.ini"), "76561198000000009"))

-- A new game log file (after SCUM rotates it) is read from the start.
gameLogFiles.violations_ = "violations_2.log"
write(gameLogDir .. "/violations_2.log", "first line of new file 76561198000000008\n")
step(61)
check("new game log read in full", has(acLog(), "SCUM violation: first line of new file"))

-- ------------------------------------------------------------------ scenario 4: aimbot checks from the kill log
local function vec(x, y, z) return string.format('{"X":%.1f,"Y":%.1f,"Z":%.1f}', x * 100, y * 100, z * 100) end
local function jsonKill(stamp, killerId, killerName, killerPos, clientPos, victimId, victimName, victimPos, weapon, immortal)
    return string.format('%s: {"Killer":{"ServerLocation":%s,"ClientLocation":%s,"IsInGameEvent":false,"ProfileName":"%s","UserId":"%s","HasImmortality":%s},'
        .. '"Victim":{"ServerLocation":%s,"ClientLocation":%s,"IsInGameEvent":false,"ProfileName":"%s","UserId":"%s"},"Weapon":"%s","TimeOfDay":"12:00:00"}\n',
        stamp, vec(table.unpack(killerPos)), vec(table.unpack(clientPos or killerPos)), killerName, killerId, immortal and "true" or "false",
        vec(table.unpack(victimPos)), vec(table.unpack(victimPos)), victimName, victimId, weapon)
end
local function textKill(stamp, killerId, killerName, victimId, victimName, weapon, distance)
    return string.format("%s: Died: %s (%s), Killer: %s (%s) Weapon: %s S[KillerLoc : 0, 0, 0 VictimLoc: 0, 0, 0, Distance: %.2f m] C[...]\n",
        stamp, victimName, victimId, killerName, killerId, weapon, distance)
end

local killLog = gameLogDir .. "/kill_1.log"
write(killLog, utf16(textKill("2026.10.11-12.00.00", "76561198000000010", "Old", "76561198000000011", "OldVictim", "Weapon_AK47_C [Projectile]", 2000)))
gameLogFiles.kill_ = "kill_1.log"
gameLogFiles.violations_, gameLogFiles.admin_ = nil, nil
start([[return { killRateKills = 3, killRateMinutes = 5 }]])
check("kill log: old kills before start ignored", not has(acLog(), "Old"))
check("startup lists aimbot checks", has(acLog(), "killLog, aimSnap, magicBullet, adminLog."))
check("aim sampler registered", aimTick ~= nil)

local sniper = Player("Sniper", Pawn("BP_Prisoner_C", 0, 0, 0))
local victim = Player("Victim", Pawn("BP_Prisoner_C", 100, 0, 0))
login("76561198000000020", "Sniper")
login("76561198000000021", "Victim")
players = { sniper, victim }
tick()

-- Same kill in JSON and text form counts once; long range with a rifle is flagged.
write(killLog, utf16(jsonKill("2026.10.11-12.41.00", "76561198000000020", "Sniper", { 0, 0, 0 }, nil, "76561198000000021", "Victim", { 1200, 0, 0 }, "Weapon_M82A1_C [Projectile]")
    .. textKill("2026.10.11-12.41.00", "76561198000000020", "Sniper", "76561198000000021", "Victim", "Weapon_M82A1_C [Projectile]", 1200)), "a")
step()
text = acLog()
check("long-range rifle kill flagged", has(text, "SUSPECT Sniper (76561198000000020): killed Victim at 1200 m with Weapon_M82A1_C [Projectile] (limit for any weapon: 800 m)"))
check("JSON + text of one kill counted once", select(2, string.gsub(text, "killed Victim at 1200 m", "")) == 1)

-- Pistol at 300 m: weapon limit. Melee at 20 m: kill aura. Trap far away: fine.
write(killLog, utf16(textKill("2026.10.11-12.41.10", "76561198000000020", "Sniper", "76561198000000022", "P", "Weapon_M1911_C [Projectile]", 300)
    .. textKill("2026.10.11-12.41.20", "76561198000000020", "Sniper", "76561198000000023", "M", "1H_KitchenKnife_C [Melee]", 20)
    .. textKill("2026.10.11-12.41.30", "76561198000000030", "Trapper", "76561198000000024", "T", "Improvised_Mine_C [Explosion]", 900)), "a")
step()
text = acLog()
check("pistol range limit", has(text, "killed P at 300 m with Weapon_M1911_C [Projectile] (limit for 1911: 150 m)"))
check("melee from afar flagged", has(text, "killed M at 20 m with 1H_KitchenKnife_C [Melee] (limit for melee: 8 m)"))
check("trap kills not range-checked", not has(text, "Trapper"))
check("kill rate flagged at the third kill", has(text, "SUSPECT Sniper (76561198000000020): 3 kills within 5 minutes"))
check("aimbot flags do not strike by default", not has(text, "[strike"))

-- God mode and client/server position mismatch (JSON only).
write(killLog, utf16(jsonKill("2026.10.11-12.42.00", "76561198000000040", "Godly", { 0, 0, 0 }, { 200, 0, 0 }, "76561198000000021", "Victim", { 10, 0, 0 }, "Weapon_AK47_C [Projectile]", true)), "a")
step()
text = acLog()
check("god mode kill flagged (offline killer named from log)", has(text, "SUSPECT Godly (76561198000000040): had god mode (immortality) while killing Victim"))
check("position mismatch flagged", has(text, "killed Victim while the client was 200 m from where the server had them"))

-- Aim snaps right before kills, reported once it becomes a pattern.
local snapper = Player("Snapper", Pawn("BP_Prisoner_C", 0, 0, 0))
login("76561198000000050", "Snapper")
players = { snapper, victim }
tick()
local function snapKill(n)
    snapper.yaw = 0
    clock = clock + 0.1; aimTick()
    snapper.yaw = 170
    clock = clock + 0.1; aimTick()
    write(killLog, utf16(textKill("2026.10.11-12.43.0" .. n, "76561198000000050", "Snapper", "7656119800000006" .. n, "V" .. n, "Weapon_AK47_C [Projectile]", 50)), "a")
    step()
end
snapKill(1)
check("snap before kill reported", has(acLog(), "Snapper (76561198000000050) snapped 170 degrees in 0.10 s right before killing V1."))
snapKill(2)
check("no pattern after two", not has(acLog(), "aim snapped onto the target"))
snapKill(3)
check("pattern reported after three snap kills", has(acLog(), "SUSPECT Snapper (76561198000000050): aim snapped onto the target before 3 of 3 kills"))

-- A slow turn is not a snap; an old snap does not count for a later kill.
local calm = Player("Calm", Pawn("BP_Prisoner_C", 0, 0, 0))
login("76561198000000070", "Calm")
players = { calm }
tick()
for i = 1, 10 do calm.yaw = i * 17; clock = clock + 0.1; aimTick() end
calm.yaw = 0; clock = clock + 0.1; aimTick(); calm.yaw = 170; clock = clock + 0.1; aimTick()
clock = clock + 5
write(killLog, utf16(textKill("2026.10.11-12.44.00", "76561198000000070", "Calm", "76561198000000071", "W", "Weapon_AK47_C [Projectile]", 50)), "a")
step()
check("slow turns and old snaps not counted", not has(acLog(), "Calm (76561198000000070) snapped"))

-- Magic bullets: firearm kills while never aiming anywhere near the victim.
local silent = Player("Silent", Pawn("BP_Prisoner_C", 0, 0, 0))
local honest = Player("Honest", Pawn("BP_Prisoner_C", 0, 0, 0))
login("76561198000000080", "Silent")
login("76561198000000081", "Honest")
players = { silent, honest }
tick()
local function aimFor(seconds, yawSilent, yawHonest)
    for _ = 1, seconds * 10 do
        silent.yaw, honest.yaw = yawSilent, yawHonest
        clock = clock + 0.1; aimTick()
    end
end
local function shoot(n, killerId, killerName)
    -- Victim due east (+X) of the killer, 100 m away.
    write(killLog, utf16(jsonKill("2026.10.11-12.50.0" .. n, killerId, killerName, { 0, 0, 0 }, nil,
        "7656119800000090" .. n, "Target" .. n, { 100, 0, 0 }, "Weapon_AK47_C [Projectile]")), "a")
    step()
end
aimFor(2, 180, 10)   -- Silent looks west the whole time; Honest looks (nearly) east
shoot(1, "76561198000000080", "Silent")
shoot(2, "76561198000000081", "Honest")
text = acLog()
check("kill without aiming at the victim reported", has(text, "Silent (76561198000000080) killed Target1 at 100 m while aiming at least 180 degrees away"))
check("kill while aiming at the victim not reported", not has(text, "Honest (76561198000000081) killed"))
check("no magic bullet suspect after one", not has(text, "magic bullet"))
aimFor(2, 180, 10)
shoot(3, "76561198000000080", "Silent")
check("magic bullet pattern reported", has(acLog(), "SUSPECT Silent (76561198000000080): 2 kills without aiming at the victim (magic bullet / silent aim)"))
-- Close kills and melee are not judged.
aimFor(2, 180, 10)
write(killLog, utf16(jsonKill("2026.10.11-12.51.00", "76561198000000080", "Silent", { 0, 0, 0 }, nil,
    "76561198000000095", "Close", { 3, 0, 0 }, "Weapon_AK47_C [Projectile]")), "a")
write(killLog, utf16(jsonKill("2026.10.11-12.51.01", "76561198000000080", "Silent", { 0, 0, 0 }, nil,
    "76561198000000096", "Stabbed", { 6, 0, 0 }, "1H_KitchenKnife_C [Melee]")), "a")
step()
check("close and melee kills not judged", not has(acLog(), "killed Close") and not has(acLog(), "killed Stabbed"))

-- strikeOnKillFlags turns suspicions into strikes.
start([[return { strikeOnKillFlags = true, strikesToAct = 1, action = "kick", banAfterKicks = 0 }]])
local far = Player("Far", Pawn("BP_Prisoner_C", 0, 0, 0))
login("76561198000000080", "Far")
players = { far }
tick()
write(killLog, utf16(textKill("2026.10.11-12.45.00", "76561198000000080", "Far", "76561198000000081", "X", "Weapon_AK47_C [Projectile]", 1500)), "a")
step()
check("kill flag can strike and kick", has(acLog(), "Far (76561198000000080): killed X at 1500 m") and has(acLog(), "Kicked Far (76561198000000080)"))
gameLogFiles.kill_ = nil

-- ------------------------------------------------------------------ crash regression
-- A player who disconnects between full checks must not be touched by the aim sampler.
start([[return {}]])
local leaver = Player("Leaver", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { leaver }
tick()
leaver.valid = false
function leaver:GetControlRotation() error("called into a destroyed controller") end
clock = clock + 0.1
aimTick()
check("aim sampler skips destroyed controllers", not has(acLog(), "Aim sampling failed"))
-- Once the game has freed it, even IsValid on it would crash: the sampler must not keep it at all.
local gone = Player("Gone", Pawn("BP_Prisoner_C", 0, 0, 0))
players = { gone }
tick()
players = {}
local touched = false
function gone:IsValid() touched = true error("freed memory") end
function gone:GetControlRotation() touched = true error("freed memory") end
clock = clock + 0.1
aimTick()
check("aim sampler never touches a controller from an earlier tick", not touched)
check("no game world is used for timing", not string.find(source, "GetRealTimeSeconds", 1, true))

-- ------------------------------------------------------------------ wallhack tracking (experimental)
local viewBlockedNow, traces, losBroken = true, 0, false
local function canSee(controller, other, viewPoint, alternate)
    traces = traces + 1
    if losBroken then error("bad parameters") end
    assert(other ~= nil and viewPoint.X == 0 and alternate == false)
    return not viewBlockedNow
end
start([[return { checks = { wallTracking = true } }]])
check("wall tracking listed when on", has(acLog(), "wallTracking."))
local watcher = Player("Watcher", Pawn("BP_Prisoner_C", 0, 0, 0))
local hider = Player("Hider", Pawn("BP_Prisoner_C", 50, 0, 0))
watcher.LineOfSightTo, hider.LineOfSightTo = canSee, canSee
login("76561198000000101", "Watcher")
login("76561198000000102", "Hider")
players = { watcher, hider }
watcher.yaw, watcher.pitch = 0, 0     -- looking east, straight at Hider
hider.yaw = 180                       -- looking west, away from Watcher's cover... and at Watcher
tick()
-- Hider is behind a wall and moving; Watcher's aim follows for 4 s.
for _ = 1, 4 do hider.pawn.x = hider.pawn.x + 2 step() end
text = acLog()
check("aim following a hidden moving player flagged", has(text,
    "SPECTATE Watcher (76561198000000101): aim followed Hider behind cover for 4 s at"))
check("wall tracking is never a strike", not string.find(text, "Watcher[^\n]*%[strike"))
-- Flagged once per pair, then a cooldown.
for _ = 1, 6 do hider.pawn.x = hider.pawn.x + 2 step() end
local _, flags = string.gsub(acLog(), "SPECTATE Watcher", "")
check("same pair not flagged again right away", flags == 1)

-- In plain view: no flag. Hidden but standing still (a known bush): no flag.
start([[return { checks = { wallTracking = true } }]])
players = { watcher, hider }
viewBlockedNow = false
tick()
for _ = 1, 5 do hider.pawn.x = hider.pawn.x + 2 step() end
check("aim on a visible player not flagged", not has(acLog(), "SPECTATE"))
viewBlockedNow = true
for _ = 1, 6 do step() end
check("hidden but not moving not flagged", not has(acLog(), "SPECTATE Watcher"))
-- Aim pointing elsewhere: the game is not even asked.
watcher.yaw, hider.yaw = 90, 90
local tracesBefore = traces
for _ = 1, 3 do hider.pawn.x = hider.pawn.x + 2 step() end
check("no view check without aim on someone", traces == tracesBefore)

-- If the game cannot be asked, the check switches itself off once.
losBroken = true
watcher.yaw, hider.yaw = 0, 180
start([[return { checks = { wallTracking = true } }]])
players = { watcher, hider }
tick()
for _ = 1, 3 do hider.pawn.x = hider.pawn.x + 2 step() end
local _, offs = string.gsub(acLog(), "Wall tracking check switched off", "")
check("broken view check switches itself off once", offs == 1 and has(acLog(), "bad parameters"))

-- Off by default.
start("return {}")
check("wall tracking off by default", not has(acLog(), "wallTracking"))
players = {}

-- ------------------------------------------------------------------ scenario 5: broken config
start("return {")
check("broken config reported", has(acLog(), "config.lua could not be read, using defaults"))
check("defaults used", has(acLog(), "action=log"))
start([[return { action = "nuke" }]])
check("unknown action falls back to log", has(acLog(), "Unknown action 'nuke'"))

-- Settings are re-read while the server runs.
write(dir .. "/config.lua", 'return { action = "kick" }')
step(31)
check("settings reloaded", has(acLog(), "Settings reloaded (action=kick)."))

-- ------------------------------------------------------------------ players from the game's player list
-- With a game state, players come from its PlayerArray: no search through every object (that
-- made the server lag 10 times a second), and the checks still work.
local searchesBefore = liveSearches or 0
local function PlayerList(entries)
    return { ForEach = function(_, callback)
        for index, entry in ipairs(entries()) do callback(index, { get = function() return entry end }) end
    end }
end
local gameState = object()
gameState.PlayerArray = PlayerList(function()
    local states = {}
    for _, controller in ipairs(players) do states[#states + 1] = { GetOwner = function() return controller end } end
    return states
end)
local findFirstBefore = FindFirstOf
function FindFirstOf(className)
    if className == "BP_ConZGameState_C" then return gameState end
    return findFirstBefore(className)
end
start('return { action = "log" }')
local runner = Player("Runner", Pawn("BP_Prisoner_C", 0, 0, 0))
login("76561198000000031", "Runner")
players = { runner }
tick()
for _ = 1, 3 do
    runner.pawn.x = runner.pawn.x + 40
    for _ = 1, 10 do aimTick() end
    step()
end
check("players found from the game's player list", has(table.concat(log), "Finding players through the game's player list."))
check("checks still work from the list", has(acLog(), "Runner (76561198000000031): moving 40.0 m/s on foot"))
local searchesAfter = liveSearches or 0
check("no search through every object, even at 10 aim samples a second", searchesAfter == searchesBefore)

-- A list whose entries have no controller: falls back to the search, and says so once.
gameState.PlayerArray = PlayerList(function() return { { GetOwner = function() return nil end } } end)
start('return { action = "log" }')
players = { Player("Hidden", Pawn("BP_Prisoner_C", 0, 0, 0)) }
step()
check("unreadable list falls back to the search", has(table.concat(log), "searching for players instead") and (liveSearches or 0) > searchesAfter)
FindFirstOf = findFirstBefore

os.execute("rm -rf '" .. tmp .. "'")
check("player searches leave out objects being destroyed (FindObjects, not FindAllOf)", (liveSearches or 0) > 0)
check("player searches leave out class default objects and archetypes", templateSearches == nil)
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
