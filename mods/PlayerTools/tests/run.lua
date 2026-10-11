--[[
    Runs main.lua against a fake UE4SS runtime and a fake SCUM folder. Run from the repo root:
        lua5.4 mods/PlayerTools/tests/run.lua
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

local private = {}   -- messages to one player: { to = name, text = ... }
local hud = {}       -- announcements
local kicks, adminCommands = {}, {}

local function Pawn(owner, x, y, z)
    local pawn = object({ owner = owner, x = x or 0, y = y or 0, z = z or 0 })
    function pawn:GetClass() return { GetFName = function() return { ToString = function() return "BP_Prisoner_C" end } end } end
    function pawn:K2_GetActorLocation() return { X = self.x * 100, Y = self.y * 100, Z = self.z * 100 } end
    function pawn:SendMessageToClient(message) private[#private + 1] = { to = self.owner, text = message } end
    return pawn
end

local function Player(name, admin)
    local controller = object({ name = name, admin = admin or false, yaw = 0 })
    controller.PlayerState = { GetPlayerName = function() return { ToString = function() return controller.name end } end }
    controller.pawn = Pawn(name)
    function controller:K2_GetPawn() return self.pawn end
    function controller:IsUserAdmin() return self.admin end
    function controller:GetControlRotation() return { Yaw = self.yaw, Pitch = 0 } end
    local channel = object({ owner = controller })
    function channel:GetOwner() return self.owner end
    function channel:Chat_Server_ProcessAdminCommand(command) adminCommands[#adminCommands + 1] = { by = controller.name, command = command } end
    controller.channel = channel
    return controller
end

-- ------------------------------------------------------------------ fake UE4SS globals
local players = {}
local clock = 1000
local log = {}

function print(text) log[#log + 1] = text end
os.time = function() return clock end
local gameMode = object()
function gameMode:SendHUDMessageToAll(message, beep) assert(beep == false) hud[#hud + 1] = message end
function gameMode:KickPlayer(controller, reason) kicks[#kicks + 1] = { name = controller.name, reason = reason } return true end

function FindAllOf(className)
    if className == "ConZPlayerController" then return players end
    if className == "PlayerRpcChannel" then
        local channels = {}
        for _, controller in ipairs(players) do channels[#channels + 1] = controller.channel end
        return channels
    end
    return nil
end
function FindFirstOf(className)
    if className == "ConZGameMode" then return gameMode end
    return nil
end
function ExecuteInGameThread(callback) callback() end
local loop
function LoopAsync(delay, callback) assert(delay == 1000) loop = callback end

local gameLogFiles = {}
io.popen = function(command)
    local prefix = string.match(command, "\\([%a_]+)%*%.log")
    local name = gameLogFiles[prefix]
    return { read = function() return name end, close = function() end }
end

-- ------------------------------------------------------------------ fake SCUM folder
local tmp = os.tmpname()
os.remove(tmp)
local scum = tmp .. "/SCUM"
local mods = scum .. "/Binaries/Win64/ue4ss/Mods"
local dir = mods .. "/PlayerTools"
local gameLogDir = scum .. "/Saved/SaveFiles/Logs"
os.execute("mkdir -p '" .. dir .. "/Scripts' '" .. mods .. "/PelicanConsole' '" .. scum .. "/Saved/Logs' '" .. gameLogDir .. "'")
local source = assert(io.open("mods/PlayerTools/Scripts/main.lua")):read("a")
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
local function has(text, needle) return string.find(text, needle, 1, true) ~= nil end
local function step(seconds)
    for _ = 1, seconds or 1 do
        clock = clock + 1
        loop()
    end
end
local function login(id, name)
    write(scum .. "/Saved/Logs/SCUM.log", "LogSCUM: '1.2.3.4 " .. id .. ":" .. name .. "(2)' logged in at: X=1 Y=2 Z=3\n", "a")
end
local function chat(id, name, text)
    write(gameLogDir .. "/" .. gameLogFiles.chat_, utf16("2026.10.11-13.00.00: '" .. id .. ":" .. name .. "(2)' 'Global: " .. text .. "'\n"), "a")
end
local function lastPrivate(name)
    for index = #private, 1, -1 do
        if private[index].to == name then return private[index].text end
    end
    return ""
end
local function anyHud(needle)
    for _, message in ipairs(hud) do
        if has(message, needle) then return true end
    end
    return false
end

write(scum .. "/Saved/Logs/SCUM.log", "Log file open\n")
write(mods .. "/PelicanConsole/console.log", "")
write(gameLogDir .. "/chat_1.log", utf16("2026.10.11-12.00.00: '76561198000000009:Old(9)' 'Global: !help'\n"))
write(gameLogDir .. "/kill_1.log", "")
gameLogFiles.chat_, gameLogFiles.kill_ = "chat_1.log", "kill_1.log"

-- An existing record from an earlier run.
write(dir .. "/players.tsv", "76561198000000005\tVeteran\t10\t2\t7200\t350\t\t1\n")

-- ------------------------------------------------------------------ start with a test config
write(dir .. "/config.lua", [[return {
    chatCommands = { rules = { "Be nice." }, discord = "discord.gg/test" },
    afk = { enabled = true, minutes = 3, warnMinutesBefore = 1 },
    voting = { minVotes = 1, percentNeeded = 50, durationSeconds = 30, cooldownMinutes = 5,
        options = { { name = "day", label = "make it daytime", command = "SetTime 10" } } },
    newPlayers = { messages = { "Welcome {name}! Type !help." }, starterKit = true,
        starterKitCommands = { 'SpawnItem Water 1 Location "{location}"', "ChangeCurrencyBalance Normal 500 {steamId}" },
        starterKitMessage = "Kit for {name}." },
}]])
dofile(dir .. "/Scripts/main.lua")
check("loop registered", loop ~= nil)
check("startup summary", has(read(dir .. "/playertools.log"), "Active: chat commands, kill feed, stats, AFK kick after 3 min, voting, starter kit, kill streaks."))
check("startup in Pelican console", has(read(mods .. "/PelicanConsole/console.log"), "[PlayerTools] Active"))

step()
check("old chat lines ignored", #private == 0)

-- ------------------------------------------------------------------ new player, no admin online
login("76561198000000001", "Alice")
local alice = Player("Alice")
alice.pawn.x, alice.pawn.y, alice.pawn.z = 10, 20, 5
players = { alice }
step(5)
check("no welcome right after spawn", #private == 0)
step(10)
check("new player message", lastPrivate("Alice") == "Welcome Alice! Type !help.")
check("kit waits for an admin", #adminCommands == 0 and has(read(dir .. "/playertools.log"), "Starter kit for Alice is waiting: no admin is online."))
step(5)
check("new player message sent once", #private == 1)

-- An admin comes online: the kit is given at Alice's position, once.
login("76561198000000002", "Bob")
local bob = Player("Bob", true)
players = { alice, bob }
step(2)
check("kit item at the player's location", adminCommands[1] and adminCommands[1].by == "Bob"
    and adminCommands[1].command == '#SpawnItem Water 1 Location "X=1000 Y=2000 Z=550"')
check("kit runs every command", adminCommands[2] and adminCommands[2].command == "#ChangeCurrencyBalance Normal 500 76561198000000001")
check("kit message", lastPrivate("Alice") == "Kit for Alice.")
local kitCommands = #adminCommands
step(20)
check("kit given once (plus new player Bob's own kit)", #adminCommands == kitCommands + 2)

-- ------------------------------------------------------------------ chat commands
private = {}
chat("76561198000000001", "Alice", "!rules")
step()
check("rules", lastPrivate("Alice") == "Server rules:\n1. Be nice.")
chat("76561198000000001", "Alice", "!discord")
step()
check("discord", lastPrivate("Alice") == "Discord: discord.gg/test")
chat("76561198000000001", "Alice", "!online")
step()
check("online list", lastPrivate("Alice") == "2 online: Alice, Bob")
chat("76561198000000001", "Alice", "!HELP")
step()
check("help lists enabled commands", has(lastPrivate("Alice"), "!stats [name], !top") and has(lastPrivate("Alice"), "!vote <option>"))
chat("76561198000000001", "Alice", "hello everyone")
step()
check("normal chat ignored", lastPrivate("Alice") == lastPrivate("Alice") and #private == 4)

-- ------------------------------------------------------------------ kills, kill feed and stats
write(gameLogDir .. "/kill_1.log", '2026.10.11-13.01.00: {"Killer":{"ServerLocation":{"X":0,"Y":0,"Z":0},"ProfileName":"Alice","UserId":"76561198000000001"},"Victim":{"ServerLocation":{"X":25000,"Y":0,"Z":0},"ProfileName":"Bob","UserId":"76561198000000002"},"Weapon":"BP_Weapon_AK47_C [Projectile]"}\n'
    .. "2026.10.11-13.01.00: Died: Bob (76561198000000002), Killer: Alice (76561198000000001) Weapon: BP_Weapon_AK47_C [Projectile] S[KillerLoc : 0, 0, 0 VictimLoc: 25000, 0, 0, Distance: 250.00 m]\n", "a")
step()
check("kill feed", hud[#hud] == "Alice killed Bob with Weapon AK47 (250 m)" or hud[#hud] == "Alice killed Bob with AK47 (250 m)")
check("kill counted once", #hud == 1)
check("no errors so far", not has(read(dir .. "/playertools.log"), "failed"))
private = {}
chat("76561198000000001", "Alice", "!stats")
step()
check("own stats", has(lastPrivate("Alice"), "Kills 1, deaths 0, K/D 1") and has(lastPrivate("Alice"), "Longest kill 250 m, best streak 1"))
chat("76561198000000002", "Bob", "!stats veteran")
step()
check("stats by name", has(lastPrivate("Bob"), "Stats for Veteran:") and has(lastPrivate("Bob"), "Kills 10, deaths 2, K/D 5.00"))
chat("76561198000000002", "Bob", "!top")
step()
check("leaderboard", lastPrivate("Bob") == "Top killers:\n1. Veteran - 10 kills\n2. Alice - 1 kills")

-- ------------------------------------------------------------------ voting
hud = {}
chat("76561198000000001", "Alice", "!vote")
step()
check("vote options listed", lastPrivate("Alice") == "Vote for: day. Example: !vote day")
chat("76561198000000001", "Alice", "!vote day")
step()
check("vote announced", anyHud("Alice wants to make it daytime. Type !yes or !no in chat (30 s)."))
chat("76561198000000002", "Bob", "!vote day")
step()
check("second vote refused", lastPrivate("Bob") == "A vote is already running. Type !yes or !no.")
chat("76561198000000002", "Bob", "!yes")
step()
check("vote counted", lastPrivate("Bob") == "Vote counted: yes.")
local before = #adminCommands
step(30)
check("passed vote runs as admin", adminCommands[before + 1] and adminCommands[before + 1].command == "#SetTime 10")
check("vote result announced", anyHud("Vote passed (2 votes): make it daytime."))
chat("76561198000000001", "Alice", "!vote day")
step()
check("vote cooldown", has(lastPrivate("Alice"), "The next vote can start in"))

-- A passed vote with no admin online says why it did nothing.
step(5 * 60)
players = { alice }
chat("76561198000000001", "Alice", "!vote day")
step(31)
check("no admin: vote cannot apply", anyHud("Vote passed, but it cannot be applied right now: no admin is online."))

-- A failed vote.
players = { alice, bob }
step(5 * 60)
chat("76561198000000001", "Alice", "!vote day")
step()
chat("76561198000000002", "Bob", "!no")
step()
alice.admin = false
local third = Player("Carol")
players = { alice, bob, third }
step(31)
check("failed vote", anyHud("Vote to make it daytime failed: 1 of 2 needed votes."))
players = { alice, bob }

-- ------------------------------------------------------------------ AFK
private, kicks = {}, {}
-- Alice keeps moving; Bob is an admin (ignored); Carol stands still.
local carol = Player("Carol")
players = { alice, bob, carol }
for _ = 1, 125 do
    alice.pawn.x = alice.pawn.x + 2
    step()
end
check("AFK warning before the kick", lastPrivate("Carol") == "You will be kicked for being AFK in 1 min. Move to stay.")
check("not kicked yet", #kicks == 0)
for _ = 1, 60 do
    alice.yaw = alice.yaw + 5
    step()
end
check("AFK player kicked", kicks[1] and kicks[1].name == "Carol" and kicks[1].reason == "Kicked for being AFK.")
check("moving and turning players not kicked", #kicks == 1)
check("admins not kicked", lastPrivate("Bob") == "")
check("AFK kick logged", has(read(dir .. "/playertools.log"), "Kicked Carol for being AFK."))

-- ------------------------------------------------------------------ saving, playtime and reload
step(60)
local saved = read(dir .. "/players.tsv")
check("players saved", has(saved, "76561198000000001\tAlice\t1\t0\t"))
check("existing record kept", has(saved, "76561198000000005\tVeteran\t10\t2\t7200\t350\t"))
check("kit marked given", string.match(saved, "76561198000000001\tAlice\t1\t0\t%d+\t250\tgiven\t") ~= nil)
local playtime = tonumber(string.match(saved, "76561198000000001\tAlice\t1\t0\t(%d+)"))
check("playtime counted", playtime and playtime > 600)

write(dir .. "/config.lua", "return { killFeed = { enabled = false }, chatCommands = { prefix = '/' } }")
step(31)
check("settings reloaded", has(read(dir .. "/playertools.log"), "Settings reloaded."))
hud = {}
write(gameLogDir .. "/kill_1.log", "2026.10.11-14.00.00: Died: Alice (76561198000000001), Killer: Bob (76561198000000002) Weapon: Knife S[Distance: 1.00 m]\n", "a")
private = {}
chat("76561198000000001", "Alice", "/online")
step()
check("kill feed turned off by reload", #hud == 0)
check("new prefix after reload", lastPrivate("Alice") == "3 online: Alice, Bob, Carol")

-- A broken config keeps working with defaults.
write(dir .. "/config.lua", "return {")
step(31)
check("no update errors", not has(read(dir .. "/playertools.log"), "Update failed"))
check("broken config reported", has(read(dir .. "/playertools.log"), "config.lua could not be read, using defaults"))

-- Game logs rotate: a new chat log is read from the start.
gameLogFiles.chat_ = "chat_2.log"
write(gameLogDir .. "/chat_2.log", utf16("2026.10.11-15.00.00: '76561198000000002:Bob(2)' 'Local: !discord'\n"))
private = {}
step(61)
check("new chat log read", lastPrivate("Bob") == "No Discord link has been set.")


-- ================================================================== rewards, streaks, bounties, teleports, info, reports
private, hud, adminCommands, kicks = {}, {}, {}, {}
write(dir .. "/players.tsv", "76561198000000010\tDave\t5\t0\t3600\t100\t\t1\n")   -- older 8-column format
os.execute("mkdir -p '" .. mods .. "/ServerMessages'")
write(mods .. "/ServerMessages/config.lua", 'return { restartTimes = { "06:00" } }')
write(dir .. "/config.lua", [[return {
    playtimeRewards = { enabled = true, everyMinutes = 1, commands = { "Pay {steamId}" }, message = "+cash",
        dailyCommands = { "Daily {steamId}" }, dailyMessage = "Daily bonus for {name}" },
    killStreaks = { announceAt = { 2, 3 }, endedMinimum = 2, ignoreSameVictimMinutes = 10 },
    bounties = { enabled = true, streakBountyAt = 3, streakBountyAmount = 500, streakBountyIncrease = 100,
        playerBounties = true, minAmount = 100, maxAmount = 1000 },
    teleports = { enabled = true, standStillSeconds = 5, cooldownMinutes = 10,
        locations = { { name = "trader", x = 100, y = 200, z = 300, price = 50 }, { name = "bad" } } },
    info = { lines = { "Have fun" } },
    reports = { cooldownSeconds = 60 },
}]])
dofile(dir .. "/Scripts/main.lua")
check("new features in startup summary", has(read(dir .. "/playertools.log"), "playtime rewards, kill streaks, bounties, teleports."))

login("76561198000000010", "Dave")
login("76561198000000011", "Eve")
local dave, eve = Player("Dave"), Player("Eve", true)
players = { dave, eve }
step(11)
check("welcome back with stats", lastPrivate("Dave") == "Welcome back Dave! 1.0 h played, 5 kills, 0 deaths.")
local function ran(command)
    for _, entry in ipairs(adminCommands) do
        if entry.command == command then return entry end
    end
    return nil
end
check("daily bonus run as the admin", ran("#Daily 76561198000000010") and ran("#Daily 76561198000000010").by == "Eve")
check("daily bonus message", has(table.concat((function() local t = {} for _, m in ipairs(private) do if m.to == "Dave" then t[#t + 1] = m.text end end return t end)(), "|"), "Daily bonus for Dave"))
check("old records do not get back pay", ran("#Pay 76561198000000010") == nil)
step(60)
check("hourly reward after the interval", ran("#Pay 76561198000000010") ~= nil)
local pays = 0
for _, entry in ipairs(adminCommands) do if entry.command == "#Pay 76561198000000010" then pays = pays + 1 end end
step(10)
local paysLater = 0
for _, entry in ipairs(adminCommands) do if entry.command == "#Pay 76561198000000010" then paysLater = paysLater + 1 end end
check("reward once per interval", pays == 1 and paysLater == 1)
check("daily bonus once a day", (function() local n = 0 for _, e in ipairs(adminCommands) do if e.command == "#Daily 76561198000000010" then n = n + 1 end end return n end)() == 1)

-- Kill streaks and the streak bounty.
local killTime = 0
local function kill(killerId, killerName, victimId, victimName)
    killTime = killTime + 1
    write(gameLogDir .. "/kill_1.log", string.format("2026.10.11-16.00.%02d: Died: %s (%s), Killer: %s (%s) Weapon: AK47 S[Distance: 50.00 m]\n",
        killTime, victimName, victimId, killerName, killerId), "a")
    step()
end
hud = {}
kill("76561198000000010", "Dave", "76561198000000021", "V1")
kill("76561198000000010", "Dave", "76561198000000022", "V2")
check("streak announced", anyHud("Dave is on a 2 kill streak!"))
kill("76561198000000010", "Dave", "76561198000000023", "V3")
check("streak 3 announced", anyHud("Dave is on a 3 kill streak!"))
check("streak bounty placed", anyHud("Bounty on Dave is now 500. Kill them to collect!"))
local hudCount = #hud
kill("76561198000000010", "Dave", "76561198000000023", "V3")
check("same victim again does not count", #hud == hudCount + 1)   -- only the kill feed line
kill("76561198000000011", "Eve", "76561198000000010", "Dave")
check("streak end announced", anyHud("Eve ended Dave's 3 kill streak!"))
check("bounty collected", anyHud("Eve collected the 500 bounty on Dave!"))
step()
check("bounty paid to the killer", ran("#ChangeCurrencyBalance Normal 500 76561198000000011") ~= nil and lastPrivate("Eve") == "Bounty paid: 500 added to your account.")

-- Player bounties.
chat("76561198000000010", "Dave", "!bounty Eve 5000")
step()
check("bounty limits", lastPrivate("Dave") == "Bounties must be between 100 and 1000.")
chat("76561198000000010", "Dave", "!bounty Dave 200")
step()
check("no bounty on yourself", lastPrivate("Dave") == "You cannot put a bounty on yourself.")
chat("76561198000000010", "Dave", "!bounty Eve 200")
step()
check("bounty charged to the placer", ran("#ChangeCurrencyBalance Normal -200 76561198000000010") ~= nil)
check("bounty announced", anyHud("Dave put a 200 bounty on Eve. Total: 200."))
chat("76561198000000010", "Dave", "!bounty")
step()
check("bounty list", lastPrivate("Dave") == "Bounties:\nEve - 200\nPlace one: !bounty <name> <amount>")

-- Teleports.
chat("76561198000000010", "Dave", "!tp")
step()
check("teleport list skips incomplete places", lastPrivate("Dave") == "Teleports (!tp <name>):\ntrader - 50")
chat("76561198000000010", "Dave", "!tp trader")
step()
check("teleport waits", lastPrivate("Dave") == "Teleporting to trader in 5 s. Do not move." and ran("#Teleport 100 200 300 76561198000000010") == nil)
step(5)
check("teleport charged", ran("#ChangeCurrencyBalance Normal -50 76561198000000010") ~= nil)
check("teleported", ran("#Teleport 100 200 300 76561198000000010") ~= nil and lastPrivate("Dave") == "Teleported to trader (50 paid).")
chat("76561198000000010", "Dave", "!tp trader")
step()
check("teleport cooldown", has(lastPrivate("Dave"), "You can teleport again in"))
chat("76561198000000011", "Eve", "!tp trader")
step()
eve.pawn.x = eve.pawn.x + 5
step()
check("moving cancels the teleport", lastPrivate("Eve") == "Teleport cancelled: you moved.")

-- Info, where, reports.
chat("76561198000000010", "Dave", "!info")
step()
local info = lastPrivate("Dave")
check("info", has(info, "UTC, up for") and has(info, "2 player(s) online") and has(info, "Next restart in") and has(info, "(06:00 UTC)") and has(info, "Have fun"))
chat("76561198000000011", "Eve", "!where")
step()
check("admins get their position", has(lastPrivate("Eve"), "You are at x="))
local before = lastPrivate("Dave")
chat("76561198000000010", "Dave", "!where")
step()
check("players do not", lastPrivate("Dave") == before)
chat("76561198000000010", "Dave", "!report Bob was flying around")
step()
check("report acknowledged", lastPrivate("Dave") == "Thanks, your report was sent to the admins.")
check("report sent to online admins", lastPrivate("Eve") == "Report from Dave about Bob: was flying around")
check("report logged", has(read(dir .. "/reports.log"), "Dave (76561198000000010) reported Bob: was flying around | at X="))
check("report in the console", has(read(mods .. "/PelicanConsole/console.log"), "REPORT"))
chat("76561198000000010", "Dave", "!report Bob again")
step()
check("report cooldown", has(lastPrivate("Dave"), "You can send another report in"))

-- Without an admin online, paid actions say so and rewards wait.
players = { dave }
chat("76561198000000010", "Dave", "!bounty Eve 200")
step()
check("bounty needs an admin", lastPrivate("Dave") == "Bounties cannot be placed right now (no admin is online).")

step(60)
local saved = read(dir .. "/players.tsv")
local fields = {}
for field in string.gmatch(string.match(saved, "76561198000000010[^\n]*") .. "\t", "([^\t]*)\t") do fields[#fields + 1] = field end
check("saved with the new columns", #fields == 13)
check("daily date saved", fields[10] == "1970-01-01")
check("best streak saved", fields[11] == "3")
check("bounty on Dave cleared", fields[12] == "0")
check("no errors", not has(read(dir .. "/playertools.log"), "failed"))

os.execute("rm -rf '" .. tmp .. "'")
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
