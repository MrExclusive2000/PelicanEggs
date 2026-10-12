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
    playtimeRewards = { enabled = false }, bounties = { enabled = false }, teleports = { enabled = false },
    featureTips = { onJoin = false, announceEveryMinutes = 0 },
    manhunt = { enabled = false }, koth = { enabled = false },
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
    and adminCommands[1].command == 'SpawnItem Water 1 Location "X=1000 Y=2000 Z=550"')
check("kit runs every command", adminCommands[2] and adminCommands[2].command == "ChangeCurrencyBalance Normal 500 76561198000000001")
check("kit message", lastPrivate("Alice") == "Kit for Alice.")
local kitCommands = #adminCommands
step(20)
check("kit given once (plus new player Bob's own kit)", #adminCommands == kitCommands + 2)

-- ------------------------------------------------------------------ chat commands
private = {}
chat("76561198000000001", "Alice", "!rules")
step()
check("rules", lastPrivate("Alice") == "Server rules:\n1. Be nice.")
check("chat command logged", has(table.concat(log, "\n"), "Chat command from Alice: !rules"))
check("first chat lines logged as-is", has(table.concat(log, "\n"), "Chat log line: 2026.10.11-13.00.00: '76561198000000001:Alice(2)' 'Global: !rules'"))
write(gameLogDir .. "/" .. gameLogFiles.chat_, utf16("2026.10.11-13.00.00: something 'unexpected'\n"), "a")
step()
check("unreadable chat line reported", has(table.concat(log, "\n"), "Could not read chat line: 2026.10.11-13.00.00: something 'unexpected'"))
chat("76561198000000077", "Stranger", "!rules")
step()
check("unmatched chat logged", has(table.concat(log, "\n"), "Ignored !rules from Stranger (76561198000000077)"))
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
check("passed vote runs as admin", adminCommands[before + 1] and adminCommands[before + 1].command == "SetTime 10")
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
    featureTips = { onJoin = false, announceEveryMinutes = 0 },
}]])
dofile(dir .. "/Scripts/main.lua")
check("new features in startup summary", has(read(dir .. "/playertools.log"), "playtime rewards, kill streaks, bounties, teleports, manhunt, King of the Hill."))

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
check("daily bonus run as the admin", ran("Daily 76561198000000010") and ran("Daily 76561198000000010").by == "Eve")
check("daily bonus message", has(table.concat((function() local t = {} for _, m in ipairs(private) do if m.to == "Dave" then t[#t + 1] = m.text end end return t end)(), "|"), "Daily bonus for Dave"))
check("old records do not get back pay", ran("Pay 76561198000000010") == nil)
step(60)
check("hourly reward after the interval", ran("Pay 76561198000000010") ~= nil)
local pays = 0
for _, entry in ipairs(adminCommands) do if entry.command == "Pay 76561198000000010" then pays = pays + 1 end end
step(10)
local paysLater = 0
for _, entry in ipairs(adminCommands) do if entry.command == "Pay 76561198000000010" then paysLater = paysLater + 1 end end
check("reward once per interval", pays == 1 and paysLater == 1)
check("daily bonus once a day", (function() local n = 0 for _, e in ipairs(adminCommands) do if e.command == "Daily 76561198000000010" then n = n + 1 end end return n end)() == 1)

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
check("bounty paid to the killer", ran("ChangeCurrencyBalance Normal 500 76561198000000011") ~= nil and lastPrivate("Eve") == "Bounty paid: 500 added to your account.")

-- Player bounties.
chat("76561198000000010", "Dave", "!bounty Eve 5000")
step()
check("bounty limits", lastPrivate("Dave") == "Bounties must be between 100 and 1000.")
chat("76561198000000010", "Dave", "!bounty Dave 200")
step()
check("no bounty on yourself", lastPrivate("Dave") == "You cannot put a bounty on yourself.")
chat("76561198000000010", "Dave", "!bounty Eve 200")
step()
check("bounty charged to the placer", ran("ChangeCurrencyBalance Normal -200 76561198000000010") ~= nil)
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
check("teleport waits", lastPrivate("Dave") == "Teleporting to trader in 5 s. Do not move." and ran("Teleport 76561198000000010 100 200 300") == nil)
step(5)
check("teleport charged", ran("ChangeCurrencyBalance Normal -50 76561198000000010") ~= nil)
check("teleported", ran("Teleport 76561198000000010 100 200 300") ~= nil and lastPrivate("Dave") == "Teleported to trader (50 paid).")
chat("76561198000000010", "Dave", "!tp trader")
step()
check("teleport cooldown", has(lastPrivate("Dave"), "You can teleport again in"))
chat("76561198000000011", "Eve", "!tp trader")
step()
eve.pawn.x = eve.pawn.x + 5
step()
check("moving cancels the teleport", lastPrivate("Eve") == "Teleport cancelled: you moved.")

-- Teleport to a player: they have to accept, and you land next to where they are then.
chat("76561198000000010", "Dave", "!tpaccept")
step()
check("accept with no request", lastPrivate("Dave") == "Nobody is asking to teleport to you.")
chat("76561198000000011", "Eve", "!tpto nobody")
step()
check("tpto unknown player", lastPrivate("Eve") == "No player online called nobody.")
chat("76561198000000011", "Eve", "!tpto da")
step()
check("tpto asks the other player", lastPrivate("Dave") == "Eve wants to teleport to you. Type !tpaccept or !tpdeny (60 s).")
check("tpto confirms the request", lastPrivate("Eve") == "Asked Dave. They have 60 s to accept.")
chat("76561198000000010", "Dave", "!tpdeny")
step()
check("tpdeny tells the asker", lastPrivate("Eve") == "Dave said no to your teleport.")
check("no teleport after a no", ran("Teleport 76561198000000011 1150 0 50") == nil)
chat("76561198000000011", "Eve", "!tpto Dave")
step()
chat("76561198000000010", "Dave", "!tpaccept")
step()
check("tpaccept starts the teleport", lastPrivate("Eve") == "Dave accepted. Teleporting in 5 s. Do not move.")
dave.pawn.x = 10   -- Dave walks off; Eve lands where he is when the teleport happens
step(5)
check("teleported next to the player", ran("Teleport 76561198000000011 1150 0 50") ~= nil
    and lastPrivate("Eve") == "Teleported to Dave.")
chat("76561198000000011", "Eve", "!tpto Dave")
step()
check("tpto has the teleport cooldown", has(lastPrivate("Eve"), "You can teleport again in"))

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
check("saved with the new columns", #fields == 15)
check("daily date saved", fields[10] == "1970-01-01")
check("best streak saved", fields[11] == "3")
check("bounty on Dave cleared", fields[12] == "0")
check("no errors", not has(read(dir .. "/playertools.log"), "failed"))


-- ================================================================== feature tips
private, hud = {}, {}
write(dir .. "/config.lua", [[return {
    voting = { options = { { name = "day", label = "make it day", command = "SetTime 10" } } },
    teleports = { locations = { { name = "trader", x = 1, y = 2, z = 3, price = 10 } } },
    chatCommands = { discord = "discord.gg/x" },
    featureTips = { onJoin = true, announceEveryMinutes = 1, extraTips = { "Be nice." } },
}]])
dofile(dir .. "/Scripts/main.lua")
local fay = Player("Fay")
login("76561198000000030", "Fay")
players = { fay }
step(12)
check("feature summary on join", has(table.concat((function() local t = {} for _, m in ipairs(private) do t[#t + 1] = m.text end return t end)(), "|"),
    "This server has: kill feed, stats (!stats, !top), kill streaks, bounties, playtime rewards, votes (!vote), teleports (!tp), reports (!report), manhunts (!manhunt). Type !help for all commands."))
local told = #private
step(20)
check("summary sent once", #private == told)
hud = {}
step(60)
check("rotating tip", hud[1] == "Tip: Type !help in chat to see all server commands.")
step(60)
check("tips rotate", hud[2] and has(hud[2], "!stats"))
local all = {}
for _ = 1, 12 do step(60) end
for _, message in ipairs(hud) do all[#all + 1] = message end
local text = table.concat(all, "|")
check("tips cover the features", has(text, "Get a 5 kill streak and the server puts a 500 bounty") and has(text, "!vote day")
    and has(text, "!tp trader") and has(text, "discord.gg/x") and has(text, "Tip: Be nice."))
check("no tip for switched-off features", not has(text, "AFK"))
players = {}
local quiet = #hud
step(120)
check("no tips to an empty server", #hud == quiet)


-- ================================================================== experimental: items, direct teleports, balance checks
private, hud, adminCommands = {}, {}, {}
local waterClass = object()
function FindObject(className, name)
    if className == "BlueprintGeneratedClass" and name == "BP_Water_05l_C" then return waterClass end
    return nil
end
local spawned = {}
local statics = object()
function statics:BeginDeferredActorSpawnFromClass(w, class, transform)
    local actor = object({ class = class, at = transform.Translation })
    spawned[#spawned + 1] = actor
    return actor
end
function statics:FinishSpawningActor() end
function StaticFindObject(path)
    if path == "/Script/Engine.Default__GameplayStatics" then return statics end
    return nil
end
local oldFindFirst = FindFirstOf
local world = object()
function FindFirstOf(className)
    if className == "World" then return world end
    return oldFindFirst(className)
end
write(dir .. "/config.lua", [[return {
    itemRewards = { enabled = true },
    newPlayers = { starterKit = true, starterKitItems = { { item = "Water_05l", amount = 2 }, { item = "Nope", amount = 1 } },
        starterKitCommands = {}, starterKitMessage = "Kit!" },
    playtimeRewards = { enabled = false },
    teleports = { method = "direct", checkBalance = true, standStillSeconds = 1, cooldownMinutes = 0,
        locations = { { name = "b4", x = 10, y = 20, z = 30, price = 300 } } },
    bounties = { checkBalance = true, playerBounties = true, minAmount = 100, maxAmount = 1000 },
    featureTips = { onJoin = false, announceEveryMinutes = 0 },
}]])
dofile(dir .. "/Scripts/main.lua")
local gus = Player("Gus")
local inventory = {}
function gus.pawn:PlaceItemInInventoryOrHolster(item) inventory[#inventory + 1] = item end
local teleported = nil
function gus.pawn:K2_TeleportTo(location) teleported = location return true end
local money = "250"
function gus:GetCurrencyBalanceText() return { ToString = function() return money end } end
login("76561198000000040", "Gus")
players = { gus }
step(12)
check("kit items without an admin", #spawned == 2 and #inventory == 2 and spawned[1].class == waterClass and #adminCommands == 0)
check("kit message", lastPrivate("Gus") == "Kit!")
check("unknown kit item reported", has(read(dir .. "/playertools.log"), "Item Nope has not been loaded on this server yet; skipped."))
step(20)
check("kit items given once", #spawned == 2)

-- With item rewards switched off, a new player's kit of items only is skipped.
write(dir .. "/config.lua", (read(dir .. "/config.lua"):gsub("itemRewards = { enabled = true }", "itemRewards = { enabled = false }")))
step(31)
login("76561198000000042", "Ned")
local ned = Player("Ned")
players = { gus, ned }
local spawnedBefore = #spawned
step(12)
check("no items while item rewards are off", #spawned == spawnedBefore and lastPrivate("Ned") ~= "Kit!")
write(dir .. "/config.lua", (read(dir .. "/config.lua"):gsub("itemRewards = { enabled = false }", "itemRewards = { enabled = true }")))
step(31)
players = { gus }

chat("76561198000000040", "Gus", "!tp b4")
step(3)
check("teleport refused when broke", lastPrivate("Gus") == "Teleport cancelled: you need 300 and have 250." and teleported == nil)
money = "1,250"
login("76561198000000041", "Hal")
local admin = Player("Hal", true)
players = { gus, admin }
chat("76561198000000040", "Gus", "!tp b4")
step(3)
check("direct teleport", teleported and teleported.X == 10 and teleported.Z == 30)
check("teleport charged through the admin", ran("ChangeCurrencyBalance Normal -300 76561198000000040") ~= nil)
check("no Teleport admin command with the direct method", ran("Teleport 76561198000000040 10 20 30") == nil)

money = "50"
chat("76561198000000040", "Gus", "!bounty Hal 200")
step()
check("bounty refused when broke", lastPrivate("Gus") == "You cannot place that bounty: you need 200 and have 50.")
money = "?"
chat("76561198000000040", "Gus", "!bounty Hal 200")
step()
check("unreadable balance refuses", lastPrivate("Gus") == "You cannot place that bounty: your balance could not be read.")
-- An item type not in memory is loaded from the path PelicanConsole recorded in items.txt.
write(mods .. "/PelicanConsole/items.txt", "BP_Apple_C\t/Game/ConZ_Files/Items/Food/BP_Apple.BP_Apple_C\n")
local appleClass = object()
local requested = nil
function LoadAsset(path) requested = path return path == "/Game/ConZ_Files/Items/Food/BP_Apple.BP_Apple_C" and appleClass or nil end
write(dir .. "/config.lua", (read(dir .. "/config.lua"):gsub('{ item = "Nope", amount = 1 }', '{ item = "Apple", amount = 1 }')))
step(31)
login("76561198000000043", "Ola")
players = { gus, Player("Ola") }
local before = #spawned
step(12)
check("item loaded from items.txt path", requested == "/Game/ConZ_Files/Items/Food/BP_Apple.BP_Apple_C"
    and spawned[#spawned].class == appleClass and #spawned == before + 3)
FindFirstOf = oldFindFirst
players = {}


-- ================================================================== no admin online: SCUM's command helper
private, hud, adminCommands = {}, {}, {}
local helperSent, helperWorks, helperForm = {}, true, ""
local balance = 1000
local miscStatics = object()
function miscStatics:Test_ProcessAdminCommand(context, text)
    helperSent[#helperSent + 1] = text
    if not helperWorks then return end
    local form, amount, id = string.match(text, "^(#?)ChangeCurrencyBalance Normal (%-?%d+) (%d+)$")
    if form == helperForm and id == "76561198000000050" then balance = balance + tonumber(amount) end
end
local savedStatic, savedFirst = StaticFindObject, FindFirstOf
function StaticFindObject(path) if path == "/Script/SCUM.Default__MiscStatics" then return miscStatics end return nil end
local helperWorld = object()
function FindFirstOf(className) if className == "World" then return helperWorld end return savedFirst(className) end
local function startHelperRun()
    write(dir .. "/players.tsv", "")
    write(dir .. "/config.lua", [[return {
        newPlayers = { starterKit = false },
        playtimeRewards = { enabled = true, everyMinutes = 0, commands = {},
            dailyCommands = { "ChangeCurrencyBalance Normal 200 {steamId}" }, dailyMessage = "Daily!" },
        featureTips = { onJoin = false, announceEveryMinutes = 0 },
    }]])
    dofile(dir .. "/Scripts/main.lua")
    local ivy = Player("Ivy")
    function ivy:GetCurrencyBalanceText() return { ToString = function() return tostring(balance) end } end
    login("76561198000000050", "Ivy")
    players = { ivy }
end

-- The helper works (here only with the "#"): found by a 1-coin round trip, then used.
helperForm = "#"
startHelperRun()
step(20)
local helperLog = read(dir .. "/playertools.log")
check("helper tested with a 1-coin round trip", helperSent[1] == "ChangeCurrencyBalance Normal 1 76561198000000050"
    and helperSent[2] == "#ChangeCurrencyBalance Normal 1 76561198000000050")
check("helper found to work", has(helperLog, "SCUM runs commands without an admin online."))
check("test coin taken back, daily bonus paid without an admin", balance == 1200 and lastPrivate("Ivy") == "Daily!")

-- The helper is ignored: rewards keep waiting for an admin.
helperWorks, balance, helperSent, private = false, 1000, {}, {}
startHelperRun()
step(20)
check("ignored helper reported", has(read(dir .. "/playertools.log"), "SCUM ignores commands sent without an admin online."))
check("nothing paid when the helper is ignored", balance == 1000 and lastPrivate("Ivy") ~= "Daily!")
local sentWhenIgnored = #helperSent
step(10)
check("helper not tried again once ignored", #helperSent == sentWhenIgnored)
StaticFindObject, FindFirstOf = savedStatic, savedFirst
players = {}

-- The ready-made starter kit is used while no kit items are set.
StaticFindObject, FindFirstOf = savedStatic, oldFindFirst
function StaticFindObject(path) if path == "/Script/Engine.Default__GameplayStatics" then return statics end return nil end
function FindFirstOf(className) if className == "World" then return world end return oldFindFirst(className) end
write(dir .. "/players.tsv", "")
write(dir .. "/config.lua", [[return {
    itemRewards = { enabled = true },
    newPlayers = { starterKit = true, starterKitCommands = {}, starterKitMessage = "Kit!" },
    playtimeRewards = { enabled = false },
    featureTips = { onJoin = false, announceEveryMinutes = 0 },
}]])
dofile(dir .. "/Scripts/main.lua")
login("76561198000000060", "Kim")
players = { Player("Kim") }
local spawnedBeforeKit = #spawned
step(12)
local kitLog = read(dir .. "/playertools.log")
check("basic kit given while no items are set", #spawned == spawnedBeforeKit + 4 and spawned[spawnedBeforeKit + 1].class == waterClass
    and lastPrivate("Kim") == "Kit!")
check("basic kit asks for the rest of its items", has(kitLog, "Item Emergency_bandage has not been loaded")
    and has(kitLog, "Item Improvised_Bag_Small_01 has not been loaded"))
StaticFindObject, FindFirstOf = savedStatic, savedFirst
players = {}

-- ================================================================== death recap, hotspots, !seen, manhunt, king of the hill
private, hud, adminCommands, kicks = {}, {}, {}, {}
-- Bankers at the outposts: rows A..Z along +X, columns 0..4 along +Y (cell = 3048 m).
local CELL = 304800
local function centre(row, column) return -904800 + (row + 0.5) * CELL, -904800 + (column + 0.5) * CELL end
local bankers = {}
for _, rc in ipairs({ { 0, 0 }, { 1, 4 }, { 2, 2 }, { 4, 3 } }) do
    local x, y = centre(rc[1], rc[2])
    local banker = object({ x = x, y = y })
    function banker:K2_GetActorLocation() return { X = self.x, Y = self.y, Z = 0 } end
    bankers[#bankers + 1] = banker
end
local plainFindAll = FindAllOf
function FindAllOf(className)
    if className == "Banker" then return bankers end
    return plainFindAll(className)
end
write(dir .. "/config.lua", [[return {
    playtimeRewards = { enabled = false }, bounties = { enabled = false }, killFeed = { enabled = false },
    featureTips = { onJoin = false, announceEveryMinutes = 0 },
    hotspots = { kills = 2, withinMinutes = 5, radius = 500, cooldownMinutes = 10 },
    manhunt = { everyMinutes = 1, durationMinutes = 2, revealEveryMinutes = 1, minPlayers = 2,
        hunterCommands = { "Pay {steamId} 1000" }, survivorCommands = { "Pay {steamId} 1000" } },
    koth = { everyMinutes = 1, durationMinutes = 2, updateEveryMinutes = 1, minPlayers = 2, minSeconds = 30,
        zones = { { name = "hill", x = 0, y = 0, z = 0, radius = 50 } }, rewardCommands = { "Pay {steamId} 500" } },
}]])
dofile(dir .. "/Scripts/main.lua")
login("76561198000000050", "Ivy")
login("76561198000000051", "Jay")
local ivy, jay = Player("Ivy"), Player("Jay", true)
ivy.pawn.x, ivy.pawn.y = 0, 0
jay.pawn.x, jay.pawn.y = 5000, 5000
players = { ivy, jay }
step(2)
check("map sectors from the outposts", has(read(dir .. "/playertools.log"), "Map sectors worked out from the outposts."))

-- !seen
chat("76561198000000050", "Ivy", "!seen jay")
step()
check("seen online", lastPrivate("Ivy") == "Jay is online now.")
chat("76561198000000050", "Ivy", "!seen Nobody")
step()
check("seen unknown", lastPrivate("Ivy") == "No player called Nobody.")

-- Volunteer for manhunts before the first one starts.
chat("76561198000000050", "Ivy", "!manhunt join")
step()
check("manhunt join", has(lastPrivate("Ivy"), "You can now be picked as the manhunt target."))

-- Death recap and hotspot: two kills in sector B2 (row 1, column 2), in metres in the kill log.
local bx, by = centre(1, 2)
local killNo = 0
local function killAt(killerId, killerName, victimId, victimName, x, y)
    killNo = killNo + 1
    write(gameLogDir .. "/kill_1.log", string.format('2026.10.11-17.00.%02d: {"Killer":{"ServerLocation":{"X":%d,"Y":%d,"Z":0},"ProfileName":"%s","UserId":"%s"},"Victim":{"ServerLocation":{"X":%d,"Y":%d,"Z":0},"ProfileName":"%s","UserId":"%s"},"Weapon":"BP_Weapon_M1911_C"}\n',
        killNo, x - 3000, y, killerName, killerId, x, y, victimName, victimId), "a")
    step()
end
killAt("76561198000000051", "Jay", "76561198000000060", "Kim", bx, by)
check("no hotspot after one kill", #hud == 0 or not anyHud("Heavy fighting"))
killAt("76561198000000051", "Jay", "76561198000000061", "Lou", bx + 10000, by)
check("hotspot announced by sector", anyHud("Heavy fighting reported in sector B2!"))
killAt("76561198000000051", "Jay", "76561198000000050", "Ivy", 0, 0)
check("death recap with streak", lastPrivate("Ivy") == "You were killed by Jay with M1911 from 30 m. They are on a 3 kill streak.")

-- Manhunt starts on the volunteer; her sector is revealed; Jay kills her and is paid.
hud = {}
step(60)
check("manhunt started", anyHud("MANHUNT! Ivy is the target for 2 minutes."))
check("target revealed by sector", anyHud("Manhunt: Ivy was last seen in sector "))
check("target told", lastPrivate("Ivy") == "You are the manhunt target! Survive 2 minutes to win.")
check("king of the hill started", anyHud("KING OF THE HILL at hill"))
killAt("76561198000000051", "Jay", "76561198000000050", "Ivy", 0, 0)
check("manhunt won by the killer", anyHud("Manhunt over: Jay killed Ivy!"))
step()
check("hunter paid as the admin", ran("Pay 76561198000000051 1000") ~= nil and lastPrivate("Jay") == "You won the manhunt. Reward received!")

-- King of the Hill: Ivy stands in the zone, Jay does not.
step(60)
check("koth update", anyHud("King of the Hill at hill: Ivy leads with"))
step(60)
check("koth winner", anyHud("King of the Hill over: Ivy held hill for"))
step()
check("koth reward", ran("Pay 76561198000000050 500") ~= nil and lastPrivate("Ivy") == "You won King of the Hill. Reward received!")

-- A target who survives wins.
local before = #hud
step(60)
check("second manhunt", anyHud("MANHUNT! Ivy is the target"))
step(125)
check("survivor wins", anyHud("Manhunt over: Ivy survived and wins the reward!"))

-- !seen after leaving.
players = { ivy }
step(120)
chat("76561198000000050", "Ivy", "!seen Jay")
step()
check("seen offline", has(lastPrivate("Ivy"), "Jay was last online 2 min ago."))
check("no errors in events", not has(read(dir .. "/playertools.log"), "failed"))
FindAllOf = plainFindAll
players = {}


-- ================================================================== sectors from outpost destinations
write(dir .. "/config.lua", [[return {
    featureTips = { onJoin = false, announceEveryMinutes = 0 }, playtimeRewards = { enabled = false },
    teleports = { locations = {
        -- Trader positions found on a live server (rows Z, A, B, C, D along +Y, columns along +X).
        { name = "a0", x = -628501, y = -564653, z = 123, price = 0 },
        { name = "b4", x = 571094, y = -229415, z = 284, price = 0 },
        { name = "c2", x = -157342, y = 289458, z = 69620, price = 0 },
        { name = "z3", x = 17828, y = -675066, z = 268, price = 0 },
    } },
}]])
local function countWorkedOut()
    local n = 0
    for _ in read(dir .. "/playertools.log"):gmatch("Map sectors worked out from the outposts%.") do n = n + 1 end
    return n
end
local workedOutBefore = countWorkedOut()
dofile(dir .. "/Scripts/main.lua")
players = { Player("Solo") }
step(2)
check("sectors from destinations named after the outposts", countWorkedOut() == workedOutBefore + 1)
players = {}

-- ================================================================== daily backups of players.tsv
local function backupName(time) return dir .. "/players.backup-" .. os.date("!%Y-%m-%d", time) .. ".tsv" end
local function exists(path) local f = io.open(path) if f then f:close() return true end return false end
write(dir .. "/config.lua", "return {}")
write(dir .. "/players.tsv", "76561198000000070\tZed\t1\t0\t0\t0\t\t1\n")
os.remove(backupName(clock))
dofile(dir .. "/Scripts/main.lua")
login("76561198000000070", "Zed")
players = { Player("Zed") }
step(61)
check("backup taken on the first save of the day", has(read(backupName(clock)), "76561198000000070\tZed"))
local firstDay = clock
for _ = 1, 8 do
    clock = clock + 86400
    step(61)
end
check("one backup per day", exists(backupName(clock)) and exists(backupName(clock - 86400)))
check("backups older than 7 days removed", not exists(backupName(firstDay)) and exists(backupName(firstDay + 2 * 86400)))
players = {}

os.execute("rm -rf '" .. tmp .. "'")
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
