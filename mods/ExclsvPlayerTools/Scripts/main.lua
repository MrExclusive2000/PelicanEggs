--[[
    ExclsvPlayerTools - quality-of-life features for SCUM players.

      - Chat commands: !help, !rules, !discord, !online, !stats, !top, !vote, !yes, !no
      - Kill feed:     announces kills to everyone
      - Stats:         kills, deaths, longest kill and playtime per player, with a leaderboard
      - AFK kicker:    kicks players who have not moved for a while (warns first)
      - Voting:        players vote to change the time or weather
      - New players:   welcome messages and a one-time starter kit
      - Welcome back:  a returning player's stats when they join
      - Playtime:      a reward for every hour played and a daily login bonus
      - Kill streaks:  "Alice is on a 5 kill streak!" and who ended it
      - Bounties:      a server bounty on players with a kill streak (and, optionally, bounties
                       players place with !bounty), paid to whoever kills them
      - Teleports:     !tp <place> for a price, after standing still for a few seconds;
                       !tpto <name> to another player who accepts with !tpaccept
      - Info:          !info with uptime, players online and the next restart
      - Reports:       !report <name> <reason>, logged to reports.log and sent to online admins
      - Feature tips:  what the server offers, to each player on joining and as rotating tips
      - Death recap:   who killed you, with what, from how far
      - Hotspots:      "Heavy fighting reported in sector B2!" after several kills close together
      - !seen <name>:  when a player was last online
      - Manhunt:       a volunteer (!manhunt join) is hunted; their sector is revealed every few
                       minutes; the killer, or the target if they survive, gets a reward
      - King of the Hill: hold a zone longest to win a reward

    Chat and kills come from SCUM's own logs (SCUM/Saved/SaveFiles/Logs/chat_*.log and
    kill_*.log). Messages to one player use Prisoner.SendMessageToClient, announcements use
    ConZGameMode.SendHUDMessageToAll. Votes, starter kits, rewards, bounty payouts and
    teleports run SCUM admin commands through an online admin's chat command channel, so they
    need an admin (AdminUsers.ini) online; until then they wait (votes and teleports say so).

    Settings: config.lua in this mod's folder (re-read every 30 seconds).
    Data:     players.tsv in this mod's folder (stats, rewards, bounties, starter kits),
              reports.log (player reports).
]]

local TAG = "[ExclsvPlayerTools] "
local CONTROLLER_CLASSES = { "BP_ConZPlayerController_C", "ConZPlayerController" }
local GAME_MODE_CLASSES = { "BP_ConZGameMode_C", "ConZGameMode" }
local CM_PER_M = 100
local MAX_READ = 1024 * 1024       -- bytes read from a log per second
local CONFIG_CHECK = 30            -- seconds between looks at config.lua
local SAVE_EVERY = 60              -- seconds between writes of players.tsv
local BACKUP_DAYS = 7              -- daily copies of players.tsv kept (players.backup-<date>.tsv)
-- Seconds between looks for a newer chat or kill log. Looking runs Windows' "dir", and starting
-- a process under Wine stalls the server for a moment; SCUM starts new logs when the server
-- starts, so after finding them a look every half hour is plenty.
local LOG_REFRESH = 30 * 60
local SPAWN_DELAY = 10             -- seconds after spawning before new-player messages and kits
local AFK_MOVE = 1                 -- metres
local AFK_TURN = 2                 -- degrees

local DEFAULTS = {
    chatCommands = { enabled = true, prefix = "!", rules = {}, discord = "" },
    killFeed = { enabled = true, message = "{killer} killed {victim} with {weapon} ({distance} m)", minDistance = 0 },
    stats = { enabled = true, topCount = 3, announceTopEveryMinutes = 0 },
    afk = { enabled = false, minutes = 20, warnMinutesBefore = 2, onlyWhenPlayersAtLeast = 0, ignoreAdmins = true, kickReason = "Kicked for being AFK." },
    voting = { enabled = true, durationSeconds = 60, cooldownMinutes = 15, percentNeeded = 50, minVotes = 2, options = {} },
    newPlayers = { messages = {}, starterKit = false, starterKitPreset = "basic", starterKitItems = {}, starterKitCommands = {}, starterKitMessage = "" },
    welcomeBack = { enabled = true, message = "Welcome back {name}! {hours} played, {kills} kills, {deaths} deaths." },
    playtimeRewards = {
        enabled = true, everyMinutes = 60, dailyEnabled = true,
        commands = { "ChangeCurrencyBalance Normal 100 {steamId}" },
        message = "+100 cash for an hour on the server. Thanks for playing!",
        dailyCommands = { "ChangeCurrencyBalance Normal 200 {steamId}" },
        dailyMessage = "Daily login bonus: +200 cash.",
        items = {}, dailyItems = {},
    },
    killStreaks = {
        enabled = true, announceAt = { 3, 5, 10, 15, 20 }, message = "{name} is on a {count} kill streak!",
        endedMessage = "{killer} ended {victim}'s {count} kill streak!", endedMinimum = 3,
        ignoreSameVictimMinutes = 30,
    },
    bounties = {
        enabled = true, streakBountyAt = 5, streakBountyAmount = 500, streakBountyIncrease = 100,
        playerBounties = false, minAmount = 100, maxAmount = 5000,
        payCommand = "ChangeCurrencyBalance Normal {amount} {steamId}",
        chargeCommand = "ChangeCurrencyBalance Normal -{amount} {steamId}",
        checkBalance = true,
    },
    teleports = {
        enabled = true, cooldownMinutes = 30, standStillSeconds = 10, method = "admin", checkBalance = true,
        command = "Teleport {steamId} {x} {y} {z}",
        chargeCommand = "ChangeCurrencyBalance Normal -{price} {steamId}",
        locations = {},
        toPlayer = true, toPlayerPrice = 0, requestSeconds = 60,
    },
    info = { enabled = true, lines = {} },
    reports = { enabled = true, cooldownSeconds = 60 },
    featureTips = { onJoin = true, announceEveryMinutes = 20, extraTips = {} },
    itemRewards = { enabled = false },
    deathRecap = { enabled = true, message = "You were killed by {killer} with {weapon} from {distance} m." },
    hotspots = {
        enabled = true, kills = 3, withinMinutes = 5, radius = 500, cooldownMinutes = 10,
        message = "Heavy fighting reported {place}!",
    },
    manhunt = {
        enabled = true, everyMinutes = 60, durationMinutes = 15, revealEveryMinutes = 3, minPlayers = 3,
        hunterCommands = { "ChangeCurrencyBalance Normal 1000 {steamId}" }, hunterItems = {},
        survivorCommands = { "ChangeCurrencyBalance Normal 1000 {steamId}" }, survivorItems = {},
    },
    koth = {
        enabled = true, everyMinutes = 90, durationMinutes = 15, updateEveryMinutes = 5, minPlayers = 3,
        minSeconds = 60, zones = {},
        rewardCommands = { "ChangeCurrencyBalance Normal 1000 {steamId}" }, rewardItems = {},
    },
    -- Economy. Money moves with ChangeCurrencyBalance, so these need an admin online or the
    -- no-admin route (ExclsvConsole/no-admin-commands.txt). Spending always checks the balance.
    shop = { enabled = false, maxPerPurchase = 5, items = {} },   -- items: { name, item, amount, price }
    sell = { enabled = false, items = {} },                       -- items: { name, item, price }
    pay = { enabled = false, minAmount = 10, maxAmount = 100000, feePercent = 0 },
    lottery = { enabled = false, ticketPrice = 100, maxTicketsPerPlayer = 10, drawEveryMinutes = 60, housePercent = 10, minTickets = 2 },
    dailyTasks = {
        enabled = false,
        tasks = {
            { kind = "playtime", target = 60, reward = 300, text = "Play for 60 minutes" },
            { kind = "kills", target = 3, reward = 500, text = "Kill 3 players" },
            { kind = "longshot", target = 200, reward = 500, text = "Get a kill from 200 m or more" },
        },
    },
    killRace = { enabled = false, everyMinutes = 120, durationMinutes = 20, minPlayers = 3, prize = 2000 },
    squadBonus = { enabled = false, everyMinutes = 60, amountPerMate = 25, maxMates = 4 },
}

local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

-- UE4SS runs LoopAsync callbacks on a background thread without locking this mod's Lua state,
-- while game-thread callbacks and hooks use it at the same time; together they corrupt the
-- state and crash the server (twice on a live server, inside UE4SS). So timers run on the game
-- thread when this UE4SS has LoopInGameThreadWithDelay; on an older one the background thread
-- only hands the work over. The callback returns true to stop.
local function every(milliseconds, callback)
    if type(LoopInGameThreadWithDelay) == "function" then
        local handle
        handle = LoopInGameThreadWithDelay(milliseconds, function()
            local stop = callback()
            if stop == true and handle ~= nil and type(CancelDelayedAction) == "function" then
                CancelDelayedAction(handle)
            end
            return stop
        end)
        return handle
    end
    local stopped = false
    return LoopAsync(milliseconds, function()
        if not stopped then
            ExecuteInGameThread(function()
                if callback() == true then stopped = true end
            end)
        end
        return stopped
    end)
end

local function modDir()
    local source = string.gsub(debug.getinfo(1, "S").source or "", "^@", "")
    return string.match(source, "^(.*)[/\\]Scripts[/\\]main%.lua$")
end

local DIR = modDir()
if DIR == nil then
    print(TAG .. "Could not work out the mod folder; ExclsvPlayerTools is disabled.\n")
    return
end

-- <SCUM>/Binaries/Win64/ue4ss/Mods/ExclsvPlayerTools -> <SCUM>
local SCUM_DIR = DIR .. "/../../../../.."
local SERVER_LOG = SCUM_DIR .. "/Saved/Logs/SCUM.log"
local GAME_LOG_DIR = SCUM_DIR .. "/Saved/SaveFiles/Logs"
local PLAYERS_FILE = DIR .. "/players.tsv"
local REPORTS_FILE = DIR .. "/reports.log"
local RESTARTS_CONFIG = DIR .. "/../ExclsvMessages/config.lua"
local STARTED_AT = os.time()
local LOG_FILES = { DIR .. "/playertools.log", DIR .. "/../ExclsvConsole/console.log" }

-- ------------------------------------------------------------------ output and config

local function output(message)
    local line = os.date("!%H:%M:%S") .. " " .. TAG .. message
    print(line .. "\n")
    for index, path in ipairs(LOG_FILES) do
        -- Only write to ExclsvConsole's log when that mod is running (it creates the file).
        local existing = index > 1 and io.open(path, "r")
        if existing then existing:close() end
        local file = (index == 1 or existing) and io.open(path, "a")
        if file then
            file:write(line .. "\n")
            file:close()
        end
    end
end

local function readText(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local data = file:read("a")
    file:close()
    return data
end

local function merge(defaults, loaded)
    local result = {}
    for key, value in pairs(defaults) do result[key] = value end
    if type(loaded) == "table" then
        for key, value in pairs(loaded) do
            if type(defaults[key]) == "table" and next(defaults[key]) ~= nil and #defaults[key] == 0 and type(value) == "table" then
                result[key] = merge(defaults[key], value)
            else
                result[key] = value
            end
        end
    end
    return result
end

local configText = nil
local function loadConfig()
    configText = readText(DIR .. "/config.lua")
    local ok, loaded = pcall(dofile, DIR .. "/config.lua")
    if not ok then
        output("config.lua could not be read, using defaults: " .. tostring(loaded))
        loaded = {}
    end
    return merge(DEFAULTS, loaded)
end

local config = loadConfig()

-- ------------------------------------------------------------------ files

-- SCUM writes some logs as UTF-16. Commands and names we act on are plain text, so drop the zero bytes.
local function ascii(data)
    data = string.gsub(data, "^\255\254", "")
    return (string.gsub(data, "%z", ""))
end

local function newTail(path, fromEnd)
    return { path = path, offset = nil, fromEnd = fromEnd, partial = "" }
end

local function readTail(tail)
    local file, err = io.open(tail.path, "rb")
    if not file then
        -- Said once per file, so a log SCUM keeps locked does not fail silently.
        if not tail.reportedOpen then
            tail.reportedOpen = true
            output("Could not open " .. tail.path .. ": " .. tostring(err))
        end
        return {}
    end
    local size = file:seek("end") or 0
    if tail.offset == nil or size < tail.offset then
        tail.offset = (tail.offset == nil and tail.fromEnd) and size or 0
        tail.partial, tail.flushed = "", nil
    end
    local lines = {}
    if size > tail.offset then
        file:seek("set", tail.offset)
        local data = file:read(math.min(size - tail.offset, MAX_READ)) or ""
        tail.offset = tail.offset + #data
        local text = tail.partial .. ascii(data)
        local last, first = 1, true
        for line, finish in string.gmatch(text, "([^\n]*)\n()") do
            line = string.gsub(line, "\r$", "")
            -- Already handled while it was the unfinished last line (see below).
            if not (first and line == tail.flushed) then lines[#lines + 1] = line end
            first, tail.flushed = false, nil
            last = finish
        end
        tail.partial = string.sub(text, last)
    elseif tail.partial ~= "" then
        -- SCUM ends a line only when it writes the next one, so a last line that has stopped
        -- growing is complete: handle it now, once, instead of when the next line arrives.
        local line = string.gsub(tail.partial, "\r$", "")
        if line ~= tail.flushed and string.find(line, "%S") then
            tail.flushed = line
            lines[#lines + 1] = line
        end
    end
    file:close()
    return lines
end

-- Newest SCUM game log with this prefix, e.g. chat_20261011122958.log.
local function newestGameLog(prefix)
    local dir = string.gsub(GAME_LOG_DIR, "/", "\\")
    local listing = safe(function()
        local pipe = io.popen('dir /b /o-d "' .. dir .. '\\' .. prefix .. '*.log" 2>nul')
        if not pipe then return nil end
        local first = pipe:read("l")
        pipe:close()
        return first
    end)
    if listing == nil or listing == "" then return nil end
    return GAME_LOG_DIR .. "/" .. (string.gsub(listing, "%s+$", ""))
end

-- ------------------------------------------------------------------ player records

-- SteamID -> { name, kills, deaths, playtime (s), longest (m), kit ("pending"/"given"), first (os.time),
--   rewarded (playtime already rewarded, s), daily (UTC date of the last daily bonus),
--   bestStreak, bounty (on this player), owed (bounty cash waiting to be paid to this player),
--   credit (lottery, event, task and squad winnings waiting to be paid), tasks (today's task progress) }
-- Not saved: streak (current kill streak), new (first seen joining this session).
local records = {}
local recordsDirty = false
local FIELDS = { "name", "kills", "deaths", "playtime", "longest", "kit", "first", "rewarded", "daily", "bestStreak", "bounty", "owed",
    "lastSeen", "manhunt", "credit", "tasks" }

local function loadRecords()
    local text = readText(PLAYERS_FILE) or ""
    for line in string.gmatch(text, "[^\r\n]+") do
        local parts = {}
        for part in string.gmatch(line .. "\t", "([^\t]*)\t") do parts[#parts + 1] = part end
        local id = parts[1]
        if id and string.match(id, "^%d+$") then
            local playtime = tonumber(parts[5]) or 0
            records[id] = {
                name = parts[2] or "?", kills = tonumber(parts[3]) or 0, deaths = tonumber(parts[4]) or 0,
                playtime = playtime, longest = tonumber(parts[6]) or 0,
                kit = parts[7] or "", first = tonumber(parts[8]) or 0,
                -- Records from before playtime rewards existed start counting from now.
                rewarded = tonumber(parts[9]) or playtime, daily = parts[10] or "",
                bestStreak = tonumber(parts[11]) or 0, bounty = tonumber(parts[12]) or 0,
                owed = tonumber(parts[13]) or 0, lastSeen = tonumber(parts[14]) or 0, manhunt = parts[15] or "",
                credit = tonumber(parts[16]) or 0, tasks = parts[17] or "",
                streak = 0,
            }
        end
    end
end

-- One copy of players.tsv per day, taken before the first save of the day; the oldest go.
local function backupFile(time)
    return DIR .. "/players.backup-" .. os.date("!%Y-%m-%d", time) .. ".tsv"
end

local function backupRecords(time)
    local path = backupFile(time)
    local existing = io.open(path, "r")
    if existing then existing:close() return end
    local text = readText(PLAYERS_FILE)
    if text == nil or text == "" then return end
    local file = io.open(path, "w")
    if not file then return end
    file:write(text)
    file:close()
    for age = BACKUP_DAYS, BACKUP_DAYS + 30 do os.remove(backupFile(time - age * 86400)) end
end

local function saveRecords()
    if not recordsDirty then return end
    pcall(backupRecords, os.time())
    local file = io.open(PLAYERS_FILE, "w")
    if not file then return end
    for id, record in pairs(records) do
        local values = { id }
        for _, field in ipairs(FIELDS) do
            local value = record[field]
            if type(value) == "number" then value = string.format("%d", math.floor(value + 0.5)) end
            values[#values + 1] = (string.gsub(tostring(value or ""), "[\t\r\n]", " "))
        end
        file:write(table.concat(values, "\t") .. "\n")
    end
    file:close()
    recordsDirty = false
end

-- joined: the player is online now. Only players first seen joining count as new and get a
-- starter kit; players first seen in the kill log (e.g. before this mod was installed) do not.
local function record(id, name, joined)
    local entry = records[id]
    if entry == nil then
        entry = {
            name = name or "?", kills = 0, deaths = 0, playtime = 0, longest = 0, kit = joined and "pending" or "",
            first = os.time(), rewarded = 0, daily = "", bestStreak = 0, bounty = 0, owed = 0, lastSeen = 0,
            manhunt = "", credit = 0, tasks = "", streak = 0,
            new = joined or nil,
        }
        records[id] = entry
        recordsDirty = true
    elseif name and name ~= "" and entry.name ~= name then
        entry.name = name
        recordsDirty = true
    end
    return entry
end

loadRecords()

-- ------------------------------------------------------------------ SCUM's logs

local steamIdByName = {}     -- from SCUM.log login lines and chat lines
local pendingKills = {}
local pendingChats = {}
local recentKillKeys = {}
local serverLog = newTail(SERVER_LOG, false)
local gameLogs = {}          -- prefix -> tail

local function number(text) return tonumber(text) end

local function vectorIn(part, key)
    local vector = part and string.match(part, '"' .. key .. '":(%b{})')
    if not vector then return nil end
    local x = number(string.match(vector, '"X":([%-%d%.eE+]+)'))
    local y = number(string.match(vector, '"Y":([%-%d%.eE+]+)'))
    local z = number(string.match(vector, '"Z":([%-%d%.eE+]+)'))
    if not (x and y and z) then return nil end
    return { x = x / CM_PER_M, y = y / CM_PER_M, z = z / CM_PER_M }
end

local function distanceBetween(a, b)
    if not (a and b) then return nil end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- SCUM writes each kill twice: as JSON and as a "Died: ..." line. Either is enough.
local function parseKill(line)
    local killer = string.match(line, '"Killer":(%b{})')
    local victim = string.match(line, '"Victim":(%b{})')
    if killer and victim then
        return {
            killerId = string.match(killer, '"UserId":"(%d+)"'),
            killerName = string.match(killer, '"ProfileName":"(.-)"'),
            victimId = string.match(victim, '"UserId":"(%d+)"'),
            victimName = string.match(victim, '"ProfileName":"(.-)"'),
            weapon = string.match(line, '"Weapon":"(.-)"'),
            distance = distanceBetween(vectorIn(killer, "ServerLocation"), vectorIn(victim, "ServerLocation")),
            victimAt = vectorIn(victim, "ServerLocation"),   -- metres
        }
    end

    local victimName, victimId, killerName, killerId = string.match(line, "Died: (.-) %((%d+)%), Killer: (.-) %((%d+)%)")
    if killerId then
        return {
            killerId = killerId, killerName = killerName, victimId = victimId, victimName = victimName,
            weapon = string.match(line, "Weapon: (.-)%s+[SC]%[") or string.match(line, "Weapon: (%S+)"),
            distance = number(string.match(line, "Distance: ([%d%.]+) m")),
            victimAt = (function()
                local x, y, z = string.match(line, "VictimLoc: (%-?[%d%.]+), (%-?[%d%.]+), (%-?[%d%.]+)")
                if x == nil then return nil end
                return { x = tonumber(x) / CM_PER_M, y = tonumber(y) / CM_PER_M, z = tonumber(z) / CM_PER_M }
            end)(),
        }
    end
    return nil
end

-- Chat log lines look like: 2026.10.11-13.00.00: '76561198000000000:Name(2)' 'Global: !stats'
local function parseChat(line)
    local id, name, message = string.match(line, "'(%d+):(.-)%(%d+%)'%s+'(.*)'%s*$")
    if id == nil then
        id, message = string.match(line, "(%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d).-:%s*(.*)$")
    end
    if id == nil or message == nil then return nil end
    message = string.gsub(message, "^%a+:%s*", "")   -- channel: Global, Local, Squad...
    return { steamId = id, name = name, text = message }
end

-- Every death is in SCUM.log, not just kills by players (those are in the kill log, with the
-- weapon). A death reads:
--   [2026.10.14-02.34.20:784][493]LogSCUM: '7656...:Packet(3)' was killed by '7656...:Packet(3)'   (sometimes)
--   [2026.10.14-02.34.20:786][493]LogSCUM: Updating profile deletion because prisoner died.
--   [2026.10.14-02.34.20:786][493]LogSCUM: Update profile deletion - userProfileId: 3.
-- The profile id is the number after the name in the login line.
local deathLog = {
    profileNames = {},        -- SCUM profile id -> name
    killedBy = {},            -- victim profile id -> { killerId, killerName } from the line before
    waiting = nil,            -- timestamp of a "prisoner died" line waiting for its profile id
    pending = {},             -- deaths from SCUM.log held back for HOLD_SECONDS
    killLog = {},             -- victim SteamID or name -> os.time the kill log named them
    HOLD_SECONDS = 15,
}
local logDeath                -- writes deaths.log; set with the kill feed below

local function handleServerLogLine(line)
    -- LogSCUM: '1.2.3.4 76561198000000000:Name(2)' logged in at: X=...
    local id, name, profile = string.match(line, "'%S+ (%d+):(.*)%((%d+)%)' logged in at:")
    if id then
        steamIdByName[name] = id
        deathLog.profileNames[profile] = name
        return
    end
    local victimId, victimName, victimProfile, killerId, killerName =
        string.match(line, "'(%d+):(.-)%((%d+)%)' was killed by '(%d+):(.-)%(%d+%)'")
    if victimProfile then
        deathLog.profileNames[victimProfile] = victimName
        steamIdByName[victimName] = victimId
        deathLog.killedBy[victimProfile] = { killerId = killerId, killerName = killerName }
        return
    end
    if string.find(line, "because prisoner died", 1, true) then
        deathLog.waiting = string.match(line, "^%[(%d+%.%d+%.%d+%-%d+%.%d+%.%d+)") or ""
        return
    end
    local deleted = string.match(line, "Update profile deletion %- userProfileId: (%d+)")
    if deleted and deathLog.waiting then
        local stamp = deathLog.waiting
        deathLog.waiting = nil
        local name = deathLog.profileNames[deleted] or ("profile " .. deleted)
        local victim = steamIdByName[name]
        local killer = deathLog.killedBy[deleted]
        deathLog.killedBy[deleted] = nil
        -- Kills by another player are logged from the kill log, which has the weapon.
        if killer and killer.killerId ~= victim then return end
        -- Held back a little: if the kill log names this player as killed after all, that line
        -- (with the weapon) is the one kept.
        deathLog.pending[#deathLog.pending + 1] = {
            at = os.time(), stamp = stamp ~= "" and stamp or nil,
            kill = {
                victimName = name, victimId = victim,
                killerName = killer and killer.killerName, killerId = killer and killer.killerId,
                died = killer == nil,
            },
        }
    end
end

deathLog.flush = function(time)
    local keep = {}
    for _, death in ipairs(deathLog.pending) do
        local id, name = death.kill.victimId, death.kill.victimName
        local killed = (id and deathLog.killLog[id]) or deathLog.killLog[name]
        if killed and math.abs(killed - death.at) <= deathLog.HOLD_SECONDS * 2 then
            -- the kill log has it
        elseif time - death.at >= deathLog.HOLD_SECONDS then
            pcall(logDeath, death.kill, death.stamp)
        else
            keep[#keep + 1] = death
        end
    end
    deathLog.pending = keep
end

local function handleKillLine(line)
    local kill = parseKill(line)
    if kill == nil then return end
    local stamp = string.match(line, "^([%d%.%-]+)")
    local key = tostring(kill.killerId) .. ">" .. tostring(kill.victimId) .. "@" .. (stamp or line)
    if recentKillKeys[key] then return end
    recentKillKeys[key] = true
    if kill.victimId then deathLog.killLog[kill.victimId] = os.time() end
    if kill.victimName then deathLog.killLog[kill.victimName] = os.time() end
    if kill.killerId == nil or kill.killerId == kill.victimId then return end
    -- Kills by other players; suicides and every other death come from SCUM.log.
    pcall(logDeath, kill, stamp)
    pendingKills[#pendingKills + 1] = kill
end

local chatLinesShown, unreadChatShown = 0, 0

local function handleChatLine(line)
    local chat = parseChat(line)
    -- The first few chat lines are logged as-is, so a problem with SCUM's chat log shows up.
    if chatLinesShown < 3 and string.find(line, "%S") then
        chatLinesShown = chatLinesShown + 1
        output("Chat log line: " .. line)
    end
    if chat == nil then
        if unreadChatShown < 5 and string.find(line, "'") then
            unreadChatShown = unreadChatShown + 1
            output("Could not read chat line: " .. line)
        end
        return
    end
    if chat.name then steamIdByName[chat.name] = chat.steamId end
    local prefix = config.chatCommands.prefix or "!"
    if string.sub(chat.text, 1, #prefix) == prefix then
        chat.text = string.sub(chat.text, #prefix + 1)
        output("Chat command from " .. tostring(chat.name) .. ": " .. prefix .. chat.text)
        pendingChats[#pendingChats + 1] = chat
    end
end

local LOG_HANDLERS = { kill_ = handleKillLine, chat_ = handleChatLine }
local lastLogRefresh = nil
local missingLogs = {}       -- prefix -> already reported missing

local function refreshLogs(time)
    for _, line in ipairs(readTail(serverLog)) do handleServerLogLine(line) end

    -- Look again sooner while a log has not been found yet (SCUM may create it later).
    local waiting = gameLogs.chat_ == nil or gameLogs.kill_ == nil
    if lastLogRefresh == nil or time - lastLogRefresh >= (waiting and 10 or LOG_REFRESH) then
        local firstRefresh = lastLogRefresh == nil
        lastLogRefresh = time
        for prefix in pairs(LOG_HANDLERS) do
            local path = newestGameLog(prefix)
            if path and (gameLogs[prefix] == nil or gameLogs[prefix].path ~= path) then
                -- Skip what was already in the file when the mod started; read new files in full.
                gameLogs[prefix] = newTail(path, firstRefresh)
                if prefix == "kill_" then recentKillKeys = {} end
                output("Reading " .. path)
            elseif path == nil and not missingLogs[prefix] then
                missingLogs[prefix] = true
                output("No " .. prefix .. "*.log found in " .. GAME_LOG_DIR .. " yet; " .. (prefix == "chat_" and "chat commands" or "the kill feed")
                    .. " will start once SCUM writes one.")
            end
        end
    end

    for prefix, tail in pairs(gameLogs) do
        for _, line in ipairs(readTail(tail)) do LOG_HANDLERS[prefix](line) end
    end
    deathLog.flush(time)
end

-- ------------------------------------------------------------------ game access

local function isValid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end

-- Every live object of a class, searched on the C++ side. FindAllOf also returns objects that
-- are still loading or already being destroyed (a player's connection closing, for one), and
-- turning one of those into a Lua object crashes the server natively, where pcall cannot
-- catch it. FindObjects leaves them out; FindAllOf is only used on a UE4SS that cannot.
local UNSAFE_OBJECT_FLAGS = 0x400 | 0x1000 | 0x8000 | 0x10000 -- NeedLoad, NeedPostLoad, BeginDestroyed, FinishDestroyed
-- Class default objects and archetypes are templates, not players or world objects.
local TEMPLATE_FLAGS = 0x10 | 0x20 -- ClassDefaultObject, ArchetypeObject
local filteredSearchWorks = nil -- nil until a filtered search has found something

local function liveObjects(className, withTemplates)
    if type(FindObjects) == "function" and filteredSearchWorks ~= false then
        local found = safe(function() return FindObjects(0, className, nil, 0, withTemplates and UNSAFE_OBJECT_FLAGS or (UNSAFE_OBJECT_FLAGS | TEMPLATE_FLAGS), false) end)
        if type(found) == "table" and next(found) ~= nil then
            filteredSearchWorks = true
            local list = {}
            for _, object in pairs(found) do list[#list + 1] = object end
            return list
        end
        if filteredSearchWorks or type(found) == "table" and not isValid(safe(function() return FindFirstOf(className) end)) then
            return {}
        end
        filteredSearchWorks = false
        print(TAG .. "This UE4SS cannot leave out objects being destroyed; using FindAllOf.\n")
    end
    return safe(function() return FindAllOf(className) end) or {}
end

local function address(object)
    return safe(function() return object:GetAddress() end) or object
end

local function findAll(classNames)
    local found, seen = {}, {}
    for _, className in ipairs(classNames) do
        for _, object in ipairs(liveObjects(className)) do
            local key = address(object)
            if not seen[key] and isValid(object) then
                seen[key] = true
                found[#found + 1] = object
            end
        end
    end
    return found
end

-- Online players' controllers, from the game state's list of players: a handful of objects,
-- where searching for them means going through every object in the game (tens of thousands),
-- which made the server lag once the mods ran on the game thread. Players who have left are
-- already off the list. If the list cannot be read, the search is used instead (said once).
local playerControllers = (function()
    local GAME_STATE_CLASSES = { "BP_ConZGameState_C", "ConZGameState", "GameStateBase" }
    local gameState, foundAt, listWorks = nil, nil, nil
    return function(search, classes)
        if listWorks ~= false then
            local now = os.time()
            if gameState == nil or foundAt == nil or now - foundAt >= 60 or not isValid(gameState) then
                gameState, foundAt = nil, now
                for _, className in ipairs(GAME_STATE_CLASSES) do
                    local found = safe(function() return FindFirstOf(className) end)
                    if isValid(found) then gameState = found break end
                end
            end
            if gameState ~= nil then
                local list, entries = {}, 0
                local read = safe(function()
                    gameState.PlayerArray:ForEach(function(_, element)
                        entries = entries + 1
                        local controller = safe(function() return element:get():GetOwner() end)
                        if isValid(controller) then list[#list + 1] = controller end
                    end)
                    return true
                end) == true
                if read and (#list > 0 or entries == 0) then
                    if listWorks == nil then
                        listWorks = true
                        print(TAG .. "Finding players through the game's player list.\n")
                    end
                    return list
                end
                if read and entries > 0 then
                    listWorks = false
                    print(TAG .. "The game's player list has no controllers; searching for players instead (slower).\n")
                end
            end
        end
        return search(classes)
    end
end)()

local function findFirst(classNames)
    for _, className in ipairs(classNames) do
        local object = safe(function() return FindFirstOf(className) end)
        if isValid(object) then return object end
    end
    return nil
end

local function playerName(controller)
    local name = safe(function() return controller.PlayerState:GetPlayerName():ToString() end)
    if name == nil or name == "" then return nil end
    return name
end

local function isAdmin(controller)
    return safe(function() return controller:IsUserAdmin() end) == true
end

local function characterOf(controller)
    local pawn = safe(function() return controller:K2_GetPawn() end)
    if not isValid(pawn) then return nil end
    local class = safe(function() return pawn:GetClass():GetFName():ToString() end) or ""
    if string.find(class, "Prisoner", 1, true) == nil then return nil end
    return pawn
end

local function location(pawn)
    local vector = safe(function() return pawn:K2_GetActorLocation() end)
    if vector == nil then return nil end
    local x, y, z = safe(function() return vector.X end), safe(function() return vector.Y end), safe(function() return vector.Z end)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    return { x = x, y = y, z = z }   -- centimetres, as SCUM's commands expect
end

local function yawOf(controller)
    local rotator = safe(function() return controller:GetControlRotation() end)
    local yaw = rotator and safe(function() return rotator.Yaw end)
    return type(yaw) == "number" and yaw or nil
end

local function announce(message)
    local gameMode = findFirst(GAME_MODE_CLASSES)
    if gameMode == nil then return false end
    -- SCUM can read <...> as formatting and show nothing, so placeholders use [...].
    message = string.gsub(string.gsub(tostring(message), "<", "["), ">", "]")
    return pcall(function() gameMode:SendHUDMessageToAll(message, false) end)
end

local function fill(template, values)
    return (string.gsub(template, "{(%w+)}", function(key)
        local value = values[key]
        if value == nil then return "{" .. key .. "}" end
        return tostring(value)
    end))
end

-- ------------------------------------------------------------------ players online

local sessions = {}   -- controller address -> session

local function sessionById(id)
    for _, session in pairs(sessions) do
        if session.steamId == id then return session end
    end
    return nil
end

-- The chat log names the Steam profile; the game may know the player by another name, so
-- fall back to a case-insensitive match and then to the only player online.
local function sessionForChat(chat)
    local session = sessionById(chat.steamId)
    if session then return session end
    local wanted = chat.name and string.lower((string.gsub(chat.name, "^%s*(.-)%s*$", "%1")))
    local only, count = nil, 0
    for _, candidate in pairs(sessions) do
        if wanted and candidate.name and string.lower(candidate.name) == wanted then return candidate end
        count = count + 1
        if candidate.steamId == nil then only = candidate end
    end
    if count == 1 then return only end
    return nil
end

local MESSAGE_MAX = 100   -- characters per private message; longer replies are sent in parts

-- SCUM's chat can read <...> as formatting and show nothing, so placeholders use [...].
local function chatSafe(text)
    return (string.gsub(string.gsub(tostring(text), "<", "["), ">", "]"))
end

-- Players who are driving or dead have no character to receive chat lines; SCUM's own
-- on-screen notice (ConZPlayerController.SendHUDMessageToClient, sent to that player only)
-- reaches them instead.
local function notice(session, text)
    local ok, err = pcall(function() session.controller:SendHUDMessageToClient(text, nil) end)
    if not ok then output("Could not message " .. tostring(session.name) .. ": " .. tostring(err)) end
    return ok
end

local function tell(session, lines)
    if type(lines) == "string" then lines = { lines } end
    local pawn = characterOf(session.controller)
    if pawn == nil then
        local text = {}
        for _, line in ipairs(lines) do text[#text + 1] = chatSafe(line) end
        return notice(session, table.concat(text, "\n"))
    end
    -- Whole lines per message, at most MESSAGE_MAX characters each (a longer line goes alone).
    local parts, current = {}, nil
    for _, line in ipairs(lines) do
        line = chatSafe(line)
        if current ~= nil and #current + 1 + #line > MESSAGE_MAX then
            parts[#parts + 1] = current
            current = nil
        end
        current = current and (current .. "\n" .. line) or line
    end
    if current then parts[#parts + 1] = current end
    for _, part in ipairs(parts) do
        local ok, err = pcall(function() pawn:SendMessageToClient(part, nil) end)
        if not ok then
            output("Could not message " .. tostring(session.name) .. ": " .. tostring(err))
            return false
        end
    end
    return true
end

local function onlineCount()
    local count = 0
    for _ in pairs(sessions) do count = count + 1 end
    return count
end

-- ------------------------------------------------------------------ commands without an admin
-- Same route as ExclsvConsole's (confirmed on a live server): every SCUM admin command keeps the
-- lowest executor level allowed to run it (_requiredExecutorLevel; 0 Regular, 1 Admin, ...).
-- For one of these commands, on the game thread, that level is set to Regular on the command's
-- objects, the command runs through an online player's own command channel, and the levels are
-- put back and checked at once. Player chat is handled on this same thread, so no player can use
-- the command in between. Off unless ue4ss/Mods/ExclsvConsole/no-admin-commands.txt exists
-- (one switch for both mods); a restart always puts SCUM's own levels back.
-- In its own function to keep this file under Lua's 200 locals per function.
local runElevated = (function()
local ELEVATED_COMMANDS = {
    changecurrencybalance = "ChangeCurrencyBalance", changefamepoints = "ChangeFamePoints",
    spawnitem = "SpawnItem", teleport = "Teleport",
    settime = "SetTime", setweather = "SetWeather",   -- !vote day / night / sun
}
local ELEVATED_SWITCH = DIR .. "/../ExclsvConsole/no-admin-commands.txt"
local elevatedBroken = false

local function elevatedEnabled()
    local file = io.open(ELEVATED_SWITCH, "r")
    if file == nil then return false end
    file:close()
    return true
end

local function commandObjects(className)
    local wanted = { [string.lower(className) .. "_c"] = true, ["admincommand_" .. string.lower(className)] = true }
    local found, seen = {}, {}
    local function add(object)
        if not isValid(object) then return end
        local key = address(object)
        if seen[key] then return end
        if type(safe(function() return object._requiredExecutorLevel end)) == "number" then
            seen[key] = true
            found[#found + 1] = object
        end
    end
    for _, class in ipairs({ className .. "_C", "AdminCommand_" .. className }) do
        for _, object in ipairs(liveObjects(class, true)) do add(object) end -- the default object is a template
    end
    local instance = findFirst({ "BP_ConZGameInstance_C", "ConZGameInstance", "GameInstance" })
    local commands = instance and safe(function() return instance._adminCommandRegistry._commands end)
    if commands ~= nil then
        safe(function()
            commands:ForEach(function(_, element)
                local entry = element:get()
                local own = safe(function() return string.lower(entry:GetFName():ToString()) end)
                local classOf = safe(function() return string.lower(entry:GetClass():GetFName():ToString()) end)
                if own and wanted[own] then
                    add(safe(function() return entry:GetCDO() end))
                elseif classOf and wanted[classOf] then
                    add(entry)
                end
            end)
        end)
    end
    return found
end

local function channelOf(controller)
    local key = address(controller)
    for _, channel in ipairs(findAll({ "PlayerRpcChannel" })) do
        local owner = safe(function() return channel:GetOwner() end)
        local ownerOwner = owner and safe(function() return owner:GetOwner() end)
        if (owner ~= nil and address(owner) == key) or (ownerOwner ~= nil and address(ownerOwner) == key) then
            return channel
        end
    end
    return nil
end

-- Runs a whitelisted command as a regular player. Returns ok, detail; nil when not applicable.
local function runElevated(command)
    local name = string.lower(string.match(command, "^#*(%S+)") or "")
    local className = ELEVATED_COMMANDS[name]
    if className == nil or elevatedBroken or not elevatedEnabled() then return nil end

    -- Run it as the player it is for when they are online (SpawnItem and Teleport act on whoever
    -- runs them), otherwise as any online player.
    local steamId = string.match(command, "(7656%d%d%d%d%d%d%d%d%d%d%d%d%d)")
    local executor = nil
    for _, session in pairs(sessions) do
        if session.controller and (executor == nil or (steamId and session.steamId == steamId)) then executor = session end
    end
    if executor == nil then return false, "no player is online to run it" end
    local channel = channelOf(executor.controller)
    local targets = commandObjects(className)
    if channel == nil then return false, "no command channel for " .. tostring(executor.name) end
    if #targets == 0 then return false, "SCUM's " .. className .. " command was not found" end

    local text = (string.gsub(command, "^#+", ""))
    -- SCUM logs the command under the player's name; tell ExclsvAntiCheat (if installed) it was ours.
    local antiCheat = DIR .. "/../ExclsvAntiCheat"
    local probe = io.open(antiCheat .. "/config.lua", "r")
    if probe ~= nil then
        probe:close()
        local file = io.open(antiCheat .. "/allowed_commands.txt", "a")
        if file then
            file:write(os.time() .. " " .. text .. "\n")
            file:close()
        end
    end

    local levels, lowered = {}, true
    for index, target in ipairs(targets) do
        levels[index] = safe(function() return target._requiredExecutorLevel end)
        if safe(function() target._requiredExecutorLevel = 0 return true end) ~= true then lowered = false end
    end
    local ok, err = false, "the admin level could not be changed"
    if lowered then
        ok, err = pcall(function() channel:Chat_Server_ProcessAdminCommand(text) end)
    end
    local restored = true
    for index, target in ipairs(targets) do
        for _ = 1, 3 do
            safe(function() target._requiredExecutorLevel = levels[index] end)
            if safe(function() return target._requiredExecutorLevel end) == levels[index] then break end
        end
        if safe(function() return target._requiredExecutorLevel end) ~= levels[index] then restored = false end
    end
    if not restored then
        elevatedBroken = true
        output("WARNING: could not restore the admin level of " .. className .. ". Restart the server now so players cannot use it.")
    end
    if not ok then return false, tostring(err) end
    return true, "as " .. tostring(executor.name) .. ", without an admin"
end

    return runElevated
end)()

-- Runs an admin command through an online admin's chat command channel, as if they typed it.
-- With no admin online, the no-admin route above runs the commands it covers (when switched on);
-- anything else waits until an admin is online.
local function runAdminCommand(command)
    local admins = {}
    for key, session in pairs(sessions) do
        if isAdmin(session.controller) then admins[key] = session end
    end
    if next(admins) == nil then
        local elevated, how = runElevated(command)
        if elevated ~= nil then return elevated, how end
        return false, "no admin is online"
    end

    for _, channel in ipairs(findAll({ "PlayerRpcChannel" })) do
        local owner = safe(function() return channel:GetOwner() end)
        local admin = owner and admins[address(owner)]
        if admin == nil and owner ~= nil then
            local ownerOwner = safe(function() return owner:GetOwner() end)
            admin = ownerOwner and admins[address(ownerOwner)]
        end
        if admin ~= nil then
            -- Without the "#": the game client strips it before sending, and SCUM answers
            -- "unknown command" when it is left on.
            local text = string.gsub(command, "^#+", "")
            local ok, err = pcall(function() channel:Chat_Server_ProcessAdminCommand(text) end)
            if ok then return true, admin.name end
            return false, tostring(err)
        end
    end
    return false, "the admin's command channel was not found"
end

-- ------------------------------------------------------------------ stats and kill feed

local function weaponName(weapon)
    if weapon == nil or weapon == "" then return "?" end
    weapon = string.gsub(weapon, "%s*%[.-%]", "")
    weapon = string.gsub(weapon, "^BP_", "")
    weapon = string.gsub(weapon, "^Weapon_", "")
    weapon = string.gsub(weapon, "_C$", "")
    return (string.gsub(weapon, "_", " "))
end

-- Every death, newest last, for the panel's Console page (kills from the kill log, everything
-- else from SCUM.log):
--   2026-10-11 13:01:00 | Alice (76561198000000001) killed Bob (76561198000000002) with AK47, 250 m
-- Kept to about 512 KB: the older half moves to deaths.old.log.
local DEATHS_FILE = DIR .. "/deaths.log"
local DEATHS_MAX_BYTES = 512 * 1024

logDeath = function(kill, stamp)
    local y, mo, d, h, mi, se = string.match(stamp or "", "^(%d+)%.(%d+)%.(%d+)%-(%d+)%.(%d+)%.(%d+)")
    local when = y and string.format("%s-%s-%s %s:%s:%s", y, mo, d, h, mi, se) or os.date("!%Y-%m-%d %H:%M:%S")
    local function who(name, id) return tostring(name or "?") .. (id and " (" .. id .. ")" or "") end
    local what
    if kill.died then
        what = who(kill.victimName, kill.victimId) .. " died"
    elseif kill.killerId ~= nil and kill.killerId == kill.victimId then
        what = who(kill.victimName, kill.victimId) .. " killed themselves"
    else
        what = who(kill.killerName, kill.killerId) .. " killed " .. who(kill.victimName, kill.victimId)
    end
    if kill.weapon and kill.weapon ~= "" then what = what .. " with " .. weaponName(kill.weapon) end
    if kill.distance and kill.killerId ~= kill.victimId then what = what .. string.format(", %.0f m", kill.distance) end

    local file = io.open(DEATHS_FILE, "a")
    if not file then return end
    file:write(when .. " | " .. string.gsub(what, "[\r\n]", " ") .. "\n")
    local size = file:seek("end")
    file:close()
    if size and size > DEATHS_MAX_BYTES then
        os.remove(DIR .. "/deaths.old.log")
        os.rename(DEATHS_FILE, DIR .. "/deaths.old.log")
    end
end

local recentVictims = {}   -- "killer>victim" -> time, to stop streak and bounty farming

-- Which squad each player is in (steamId -> squad object address, "" for none), refreshed
-- every 30 s while their character exists and kept after death, so a kill between squadmates
-- can be told apart. Prisoner.GetSquad only reads; the squad object is not kept.
local squadOf = {}
local SQUAD_EVERY = 30
local lastSquadCheck = 0

local function squadTick(time)
    if time - lastSquadCheck < SQUAD_EVERY then return end
    lastSquadCheck = time
    for _, session in pairs(sessions) do
        local pawn = session.steamId and characterOf(session.controller)
        if pawn then
            local squad = safe(function() return pawn:GetSquad() end)
            squadOf[session.steamId] = isValid(squad) and (address(squad) or "") or ""
        end
    end
end

local function sameSquad(killerId, victimId)
    local a, b = killerId and squadOf[killerId], victimId and squadOf[victimId]
    return a ~= nil and a ~= "" and a == b
end
local events = {}          -- filled in further down: onKill(kill, time)

local function handleKill(kill, time)
    if events.onKill then events.onKill(kill, time) end
    local streaks, bounties = config.killStreaks, config.bounties
    local tracked = config.stats.enabled or streaks.enabled or bounties.enabled
    local killer = tracked and record(kill.killerId, kill.killerName)
    local victim = tracked and kill.victimId and record(kill.victimId, kill.victimName)

    if config.stats.enabled then
        killer.kills = killer.kills + 1
        if kill.distance and kill.distance > killer.longest then killer.longest = kill.distance end
        if victim then victim.deaths = victim.deaths + 1 end
    end

    local feed = config.killFeed
    if feed.enabled then
        local minDistance = tonumber(feed.minDistance) or 0
        if minDistance <= 0 or (kill.distance and kill.distance >= minDistance) then
            announce(fill(feed.message, {
                killer = kill.killerName or "?", victim = kill.victimName or "?",
                weapon = weaponName(kill.weapon),
                distance = kill.distance and string.format("%d", math.floor(kill.distance + 0.5)) or "?",
            }))
        end
    end

    if not tracked then return end
    recordsDirty = true

    -- Killing the same player again soon after, or a squadmate, does not count towards
    -- streaks or bounties (the server rules forbid bounty farming with friends).
    local key = kill.killerId .. ">" .. tostring(kill.victimId)
    local window = (tonumber(streaks.ignoreSameVictimMinutes) or 0) * 60
    local farmed = recentVictims[key] ~= nil and time - recentVictims[key] < window
    recentVictims[key] = time
    if sameSquad(kill.killerId, kill.victimId) then
        farmed = true
        output(string.format("Squad kill: %s killed squadmate %s; not counted for streaks or bounties.", killer.name, victim and victim.name or "?"))
    end

    if victim then
        local ended = victim.streak or 0
        victim.streak = 0
        if streaks.enabled and ended >= (tonumber(streaks.endedMinimum) or 1) then
            announce(fill(streaks.endedMessage, { killer = killer.name, victim = victim.name, count = ended }))
        end
        if bounties.enabled and (victim.bounty or 0) > 0 and not farmed then
            killer.owed = (killer.owed or 0) + victim.bounty
            announce(string.format("%s collected the %d bounty on %s!", killer.name, victim.bounty, victim.name))
            output(string.format("Bounty: %s (%s) earned %d for killing %s.", killer.name, kill.killerId, victim.bounty, victim.name))
            victim.bounty = 0
        end
    end

    if farmed then return end
    killer.streak = (killer.streak or 0) + 1
    if killer.streak > (killer.bestStreak or 0) then killer.bestStreak = killer.streak end

    if streaks.enabled then
        for _, count in ipairs(streaks.announceAt or {}) do
            if tonumber(count) == killer.streak then
                announce(fill(streaks.message, { name = killer.name, count = killer.streak }))
            end
        end
    end

    local at = tonumber(bounties.streakBountyAt) or 0
    if bounties.enabled and at > 0 and killer.streak >= at then
        local add = killer.streak == at and (tonumber(bounties.streakBountyAmount) or 0) or (tonumber(bounties.streakBountyIncrease) or 0)
        if add > 0 then
            killer.bounty = (killer.bounty or 0) + add
            announce(string.format("Bounty on %s is now %d. Kill them to collect!", killer.name, killer.bounty))
        end
    end
end

local function hours(seconds)
    return string.format("%.1f h", (seconds or 0) / 3600)
end

local function statsLines(entry)
    local kd = entry.deaths > 0 and string.format("%.2f", entry.kills / entry.deaths) or tostring(entry.kills)
    return {
        "Stats for " .. entry.name .. ":",
        string.format("Kills %d, deaths %d, K/D %s", entry.kills, entry.deaths, kd),
        string.format("Longest kill %d m, best streak %d, playtime %s", math.floor(entry.longest + 0.5), entry.bestStreak or 0, hours(entry.playtime)),
    }
end

local function topLines()
    local list = {}
    for _, entry in pairs(records) do
        if entry.kills > 0 then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.longest > b.longest
    end)
    local lines = { "Top killers:" }
    for index = 1, math.min(tonumber(config.stats.topCount) or 3, #list) do
        lines[#lines + 1] = string.format("%d. %s - %d kills", index, list[index].name, list[index].kills)
    end
    if #lines == 1 then lines[2] = "No kills yet." end
    return lines
end

-- ------------------------------------------------------------------ voting

local vote = nil
local lastVoteEnded = nil

local function voteOptions()
    local options = {}
    for _, option in ipairs(config.voting.options or {}) do
        if type(option) == "table" and option.name and option.command then options[#options + 1] = option end
    end
    return options
end

local function findOption(name)
    for _, option in ipairs(voteOptions()) do
        if string.lower(option.name) == string.lower(name or "") then return option end
    end
    return nil
end

local function voterKey(session)
    return session.steamId or ("name:" .. session.name)
end

local function countVotes(running, choice)
    local count = 0
    for _, value in pairs(running.votes) do
        if value == choice then count = count + 1 end
    end
    return count
end

local function startVote(session, name, time)
    local voting = config.voting
    local option = findOption(name)
    if option == nil then
        local names = {}
        for _, candidate in ipairs(voteOptions()) do names[#names + 1] = candidate.name end
        if #names == 0 then return tell(session, "There is nothing to vote on.") end
        return tell(session, "Vote for: " .. table.concat(names, ", ") .. ". Example: " .. config.chatCommands.prefix .. "vote " .. names[1])
    end
    if vote ~= nil then
        return tell(session, "A vote is already running. Type " .. config.chatCommands.prefix .. "yes or " .. config.chatCommands.prefix .. "no.")
    end
    local cooldown = (tonumber(voting.cooldownMinutes) or 0) * 60
    if lastVoteEnded and time - lastVoteEnded < cooldown then
        return tell(session, string.format("The next vote can start in %d min.", math.ceil((cooldown - (time - lastVoteEnded)) / 60)))
    end

    vote = { option = option, endsAt = time + (tonumber(voting.durationSeconds) or 60), votes = { [voterKey(session)] = "yes" } }
    announce(string.format("%s wants to %s. Type %syes or %sno in chat (%d s).", session.name, option.label or option.name,
        config.chatCommands.prefix, config.chatCommands.prefix, tonumber(voting.durationSeconds) or 60))
end

local function castVote(session, choice)
    if vote == nil then return tell(session, "No vote is running.") end
    vote.votes[voterKey(session)] = choice
    tell(session, "Vote counted: " .. choice .. ".")
end

local function finishVote(time)
    if vote == nil or time < vote.endsAt then return end
    local current = vote
    vote, lastVoteEnded = nil, time

    local yes, online = countVotes(current, "yes"), math.max(onlineCount(), 1)
    local needed = math.max(tonumber(config.voting.minVotes) or 1, math.ceil(online * (tonumber(config.voting.percentNeeded) or 50) / 100))
    local label = current.option.label or current.option.name
    if yes < needed then
        announce(string.format("Vote to %s failed: %d of %d needed votes.", label, yes, needed))
        return
    end

    local ok, detail = runAdminCommand(current.option.command)
    if ok then
        announce(string.format("Vote passed (%d votes): %s.", yes, label))
        output("Vote passed: " .. current.option.command .. " (run as " .. detail .. ")")
    else
        announce(string.format("Vote passed, but it cannot be applied right now: %s.", detail))
        output("Vote passed but " .. current.option.command .. " could not run: " .. detail)
    end
end

-- ------------------------------------------------------------------ direct routes
-- Reading a player's balance (confirmed on a live server), and two routes not yet confirmed
-- there: giving items straight into a player's inventory, and teleporting without the Teleport
-- command. Those two are only used where the settings switch them on (item lists, method = "direct").

-- Money the player has, read from the game (nil when it cannot be read). This is the plain
-- value the controller keeps for the player's screen; calling SCUM's GetCurrencyBalanceText
-- (it builds a formatted text) crashed a live server, so it is not used.
local function balanceOf(session)
    local money = safe(function() return session.controller._moneyBalanceRep end)
    return type(money) == "number" and math.floor(money) or nil
end

local function canAfford(session, price, check)
    if not check or price <= 0 then return true end
    local money = balanceOf(session)
    if money == nil then return false, "your balance could not be read" end
    if money < price then return false, string.format("you need %d and have %d", price, money) end
    return true
end

-- Never keep game objects between calls: SCUM unloads item classes it is not using, and touching
-- an unloaded class crashes the server. Classes are remembered by path and looked up again.
local classPaths = nil   -- every loaded class's path by short name, built on the first miss

local function classAt(path)
    if path == nil or path == "" then return nil end
    local found = safe(function() return StaticFindObject(path) end)
    if not isValid(found) then found = safe(function() return LoadAsset(path) end) end
    if isValid(found) then return found end
    return nil
end

local function findItemClass(name)
    local candidates = { name, name .. "_C", "BP_" .. name .. "_C", "BP_" .. name }
    for _, candidate in ipairs(candidates) do
        local found = safe(function() return FindObject("BlueprintGeneratedClass", candidate) end)
        if isValid(found) then return found, candidate end
    end
    -- FindObject by short name does not work on every UE4SS build: look through the classes.
    if classPaths == nil then
        classPaths = {}
        for _, class in pairs(safe(function() return FindObjects(0, "Class", nil, 0, 0, false) end) or {}) do
            local short = safe(function() return class:GetFName():ToString() end)
            local path = string.match(safe(function() return class:GetFullName() end) or "", "^%S+%s+(.+)$")
            if short and path then classPaths[short] = path end
        end
    end
    -- SCUM loads item types on demand. ExclsvConsole's items.txt records where each item type
    -- seen so far lives, so load it from there.
    local file = io.open(DIR .. "/../ExclsvConsole/items.txt", "r")
    if file then
        for line in file:lines() do
            local itemName, path = string.match(line, "^([%w_]+)\t(%S+)")
            if itemName and classPaths[itemName] == nil then classPaths[itemName] = path end
        end
        file:close()
    end
    for _, candidate in ipairs(candidates) do
        local found = classAt(classPaths[candidate])
        if found then return found, candidate end
    end
    return nil
end

-- Gives { { item = "Water_05l", amount = 2 }, ... } to the player. Items go into the inventory,
-- or at the player's feet when there is no room. Returns the number given, or nil and why.
local function giveItems(session, items, always)
    -- Item rewards have one switch for everything (starter kit, rewards, events); the shop
    -- (always) has its own.
    if (not always and not config.itemRewards.enabled) or items == nil or #items == 0 then return 0 end
    local pawn = characterOf(session.controller)
    local at = pawn and location(pawn)
    if at == nil then return nil, "the player has no character" end
    local statics = safe(function() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end)
    local world = findFirst({ "World" })
    if not isValid(statics) or world == nil then return nil, "the game world is not ready" end

    local given = 0
    for _, entry in ipairs(items) do
        local name = type(entry) == "table" and (entry.item or entry[1]) or entry
        local amount = math.max(1, math.min(tonumber(type(entry) == "table" and (entry.amount or entry[2]) or 1) or 1, 20))
        local class = name and findItemClass(tostring(name))
        if class == nil then
            output("Item " .. tostring(name) .. " has not been loaded on this server yet; skipped. Spawn one once with SpawnItem "
                .. tostring(name) .. " (as an admin) so it can be given.")
        else
            for _ = 1, amount do
                local transform = {
                    Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
                    Translation = { X = at.x, Y = at.y, Z = at.z + 50 },
                    Scale3D = { X = 1, Y = 1, Z = 1 },
                }
                local ok, err = pcall(function()
                    local actor = statics:BeginDeferredActorSpawnFromClass(world, class, transform, 1, nil)
                    if not isValid(actor) then error("the game did not create it") end
                    statics:FinishSpawningActor(actor, transform)
                    pcall(function() pawn:PlaceItemInInventoryOrHolster(actor, true) end)
                end)
                if ok then given = given + 1 else output("Giving " .. tostring(name) .. " failed: " .. tostring(err)) end
            end
        end
    end
    return given
end

-- Commands (need an admin) first, then items (direct). Items are only given once the commands
-- went through, so nothing is handed out twice while waiting for an admin.
local function giveReward(session, commands, items, values)
    for _, command in ipairs(commands or {}) do
        local ok, detail = runAdminCommand(fill(command, values))
        if not ok then return false, detail end
    end
    local given, why = giveItems(session, items)
    if given == nil then return false, why end
    return true
end


-- Tell ExclsvAntiCheat (if installed) that this teleport is ours, so it is not flagged.
local function allowTeleport(name)
    local folder = DIR .. "/../ExclsvAntiCheat"
    local probe = io.open(folder .. "/config.lua", "r")
    if probe == nil then return end
    probe:close()
    local file = io.open(folder .. "/allowed_teleports.txt", "a")
    if file then
        file:write(os.time() .. " " .. name .. "\n")
        file:close()
    end
end

local function teleportDirect(session, x, y, z)
    local pawn = characterOf(session.controller)
    if pawn == nil then return false, "no character" end
    allowTeleport(session.name)
    local ok, result = pcall(function()
        return pawn:K2_TeleportTo({ X = x, Y = y, Z = z }, { Pitch = 0, Yaw = 0, Roll = 0 })
    end)
    if not ok then return false, tostring(result) end
    if result == false then return false, "the game refused" end
    return true
end

-- ------------------------------------------------------------------ info, reports, bounties, teleports

local lastReport = {}   -- SteamID -> time

local function duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h, m = seconds // 3600, (seconds % 3600) // 60
    if h > 0 then return string.format("%d h %d min", h, m) end
    return string.format("%d min", m)
end

-- Next restart from ExclsvMessages' restartTimes ("HH:MM" UTC), or nil.
local function nextRestart(time)
    local ok, settings = pcall(dofile, RESTARTS_CONFIG)
    if not ok or type(settings) ~= "table" then return nil end
    local t = os.date("!*t", time)
    local now, best = t.hour * 3600 + t.min * 60 + t.sec, nil
    for _, clockTime in ipairs(settings.restartTimes or {}) do
        local hour, minute = string.match(tostring(clockTime), "^%s*(%d%d?):(%d%d)%s*$")
        hour, minute = tonumber(hour), tonumber(minute)
        if hour and hour <= 23 and minute <= 59 then
            local delta = hour * 3600 + minute * 60 - now
            if delta <= 0 then delta = delta + 86400 end
            if best == nil or delta < best.delta then best = { delta = delta, at = clockTime } end
        end
    end
    return best
end

local function infoLines(time)
    local lines = {
        "Server time " .. os.date("!%H:%M", time) .. " UTC, up for " .. duration(time - STARTED_AT),
        onlineCount() .. " player(s) online",
    }
    local restart = nextRestart(time)
    if restart then lines[#lines + 1] = "Next restart in " .. duration(restart.delta) .. " (" .. restart.at .. " UTC)" end
    for _, line in ipairs(config.info.lines or {}) do lines[#lines + 1] = tostring(line) end
    return lines
end

local function findPlayerRecord(name)
    local lowered = string.lower(name or "")
    if lowered == "" then return nil end
    for _, session in pairs(sessions) do
        if string.lower(session.name) == lowered and session.steamId then return session.steamId, records[session.steamId] end
    end
    for id, entry in pairs(records) do
        if string.lower(entry.name) == lowered then return id, entry end
    end
    -- Partial match on online players.
    for _, session in pairs(sessions) do
        if string.find(string.lower(session.name), lowered, 1, true) and session.steamId then return session.steamId, records[session.steamId] end
    end
    return nil
end

local function report(session, rest, time)
    local cooldown = tonumber(config.reports.cooldownSeconds) or 60
    local key = session.steamId or session.name
    if lastReport[key] and time - lastReport[key] < cooldown then
        return tell(session, "You can send another report in " .. (cooldown - (time - lastReport[key])) .. " s.")
    end
    local target, reason = string.match(rest, "^(%S+)%s+(.+)$")
    if target == nil then
        return tell(session, "Usage: " .. config.chatCommands.prefix .. "report <name> <what happened>")
    end
    lastReport[key] = time

    local pawn = characterOf(session.controller)
    local position = pawn and location(pawn)
    local line = string.format("%s | %s (%s) reported %s: %s%s", os.date("!%Y-%m-%d %H:%M:%S UTC", time), session.name,
        session.steamId or "?", target, reason,
        position and string.format(" | at X=%.0f Y=%.0f Z=%.0f", position.x, position.y, position.z) or "")
    local file = io.open(REPORTS_FILE, "a")
    if file then
        file:write(line .. "\n")
        file:close()
    end
    output("REPORT " .. line)
    for _, other in pairs(sessions) do
        if other ~= session and isAdmin(other.controller) then
            tell(other, "Report from " .. session.name .. " about " .. target .. ": " .. reason)
        end
    end
    tell(session, "Thanks, your report was sent to the admins.")
end

local function bountyCommand(session, rest)
    local bounties = config.bounties
    local name, amount = string.match(rest, "^(.-)%s+(%d+)$")
    if rest == "" or name == nil then
        local list = {}
        for _, entry in pairs(records) do
            if (entry.bounty or 0) > 0 then list[#list + 1] = entry end
        end
        table.sort(list, function(a, b) return a.bounty > b.bounty end)
        local lines = { "Bounties:" }
        for index = 1, math.min(5, #list) do lines[#lines + 1] = list[index].name .. " - " .. list[index].bounty end
        if #list == 0 then lines[2] = "No bounties right now." end
        if bounties.playerBounties then lines[#lines + 1] = "Place one: " .. config.chatCommands.prefix .. "bounty <name> <amount>" end
        return tell(session, lines)
    end

    if not bounties.playerBounties then return tell(session, "Players cannot place bounties on this server.") end
    amount = tonumber(amount)
    local minimum, maximum = tonumber(bounties.minAmount) or 1, tonumber(bounties.maxAmount) or math.huge
    if amount < minimum or amount > maximum then
        return tell(session, string.format("Bounties must be between %d and %d.", minimum, maximum))
    end
    local targetId, target = findPlayerRecord(name)
    if targetId == nil or target == nil then return tell(session, "No player called " .. name .. ".") end
    if targetId == session.steamId then return tell(session, "You cannot put a bounty on yourself.") end

    local affordable, why = canAfford(session, amount, bounties.checkBalance)
    if not affordable then return tell(session, "You cannot place that bounty: " .. why .. ".") end
    local ok, detail = runAdminCommand(fill(bounties.chargeCommand, { amount = amount, steamId = session.steamId, name = session.name }))
    if not ok then return tell(session, "Bounties cannot be placed right now (" .. detail .. ").") end
    target.bounty = (target.bounty or 0) + amount
    recordsDirty = true
    announce(string.format("%s put a %d bounty on %s. Total: %d.", session.name, amount, target.name, target.bounty))
    output(string.format("Bounty: %s (%s) placed %d on %s.", session.name, session.steamId or "?", amount, target.name))
end

local function teleportLocations()
    local list = {}
    for _, place in ipairs(config.teleports.locations or {}) do
        if type(place) == "table" and place.name and tonumber(place.x) and tonumber(place.y) and tonumber(place.z) then
            list[#list + 1] = place
        end
    end
    return list
end

local function teleportCommand(session, rest, time)
    local teleports = config.teleports
    local places = teleportLocations()
    local place = nil
    for _, candidate in ipairs(places) do
        if string.lower(candidate.name) == string.lower(rest) then place = candidate end
    end
    if place == nil then
        if #places == 0 then return tell(session, "No teleport destinations have been set.") end
        local lines = { "Teleports (" .. config.chatCommands.prefix .. "tp <name>):" }
        for _, candidate in ipairs(places) do
            local price = tonumber(candidate.price) or 0
            lines[#lines + 1] = candidate.name .. (price > 0 and (" - " .. price) or " - free")
        end
        return tell(session, lines)
    end

    local cooldown = (tonumber(teleports.cooldownMinutes) or 0) * 60
    if session.steamId and records[session.steamId] and records[session.steamId].lastTeleport
        and time - records[session.steamId].lastTeleport < cooldown then
        return tell(session, "You can teleport again in " .. duration(cooldown - (time - records[session.steamId].lastTeleport)) .. ".")
    end
    local pawn = characterOf(session.controller)
    if pawn == nil or session.steamId == nil then return tell(session, "You need to be alive to teleport.") end

    local wait = tonumber(teleports.standStillSeconds) or 0
    session.teleport = { place = place, at = time + wait, from = location(pawn) }
    tell(session, string.format("Teleporting to %s in %d s. Do not move.", place.name, wait))
end

-- !tpto <name> asks to teleport to another player; they answer with !tpaccept or !tpdeny.
local function onlineByName(name)
    local wanted = string.lower(name)
    local partial, partials = nil, 0
    for _, candidate in pairs(sessions) do
        local candidateName = string.lower(candidate.name or "")
        if candidateName == wanted then return candidate end
        if wanted ~= "" and string.sub(candidateName, 1, #wanted) == wanted then
            partial, partials = candidate, partials + 1
        end
    end
    return partials == 1 and partial or nil
end

local function playerTeleportCommand(session, word, rest, time)
    local teleports = config.teleports
    local prefix = config.chatCommands.prefix
    if not teleports.toPlayer then return tell(session, "Teleporting to players is turned off on this server.") end

    if word == "tpto" then
        if rest == "" then return tell(session, "Usage: " .. prefix .. "tpto <player name>") end
        local target = onlineByName(rest)
        if target == nil then return tell(session, "No player online called " .. rest .. ".") end
        if target == session then return tell(session, "You cannot teleport to yourself.") end
        local cooldown = (tonumber(teleports.cooldownMinutes) or 0) * 60
        local entry = session.steamId and records[session.steamId]
        if entry and entry.lastTeleport and time - entry.lastTeleport < cooldown then
            return tell(session, "You can teleport again in " .. duration(cooldown - (time - entry.lastTeleport)) .. ".")
        end
        if characterOf(session.controller) == nil or session.steamId == nil then return tell(session, "You need to be alive to teleport.") end
        if target.steamId == nil then return tell(session, target.name .. " cannot be teleported to right now.") end
        local seconds = tonumber(teleports.requestSeconds) or 60
        target.tpRequest = { from = session.steamId, name = session.name, expires = time + seconds }
        local price = tonumber(teleports.toPlayerPrice) or 0
        tell(target, string.format("%s wants to teleport to you. Type %stpaccept or %stpdeny (%d s).", session.name, prefix, prefix, seconds))
        return tell(session, string.format("Asked %s. They have %d s to accept%s.", target.name, seconds,
            price > 0 and (" (costs you " .. price .. ")") or ""))
    end

    local request = session.tpRequest
    session.tpRequest = nil
    if request == nil or time > request.expires then return tell(session, "Nobody is asking to teleport to you.") end
    local requester = sessionById(request.from)
    if requester == nil then return tell(session, request.name .. " is no longer online.") end
    if word == "tpdeny" then
        tell(requester, session.name .. " said no to your teleport.")
        return tell(session, "Teleport refused.")
    end
    local pawn = characterOf(requester.controller)
    if pawn == nil then return tell(session, request.name .. " cannot teleport right now.") end
    local wait = tonumber(teleports.standStillSeconds) or 0
    requester.teleport = {
        place = { name = session.name, price = tonumber(teleports.toPlayerPrice) or 0, toSteamId = session.steamId },
        at = time + wait, from = location(pawn),
    }
    tell(session, request.name .. " will be teleported to you in " .. wait .. " s.")
    tell(requester, string.format("%s accepted. Teleporting in %d s. Do not move.", session.name, wait))
end

local function teleportCheck(session, time)
    local pending = session.teleport
    if pending == nil then return end
    local pawn = characterOf(session.controller)
    local position = pawn and location(pawn)
    if position == nil or (pending.from and math.sqrt((position.x - pending.from.x) ^ 2 + (position.y - pending.from.y) ^ 2) / CM_PER_M > 2) then
        session.teleport = nil
        return tell(session, "Teleport cancelled: you moved.")
    end
    if time < pending.at then return end
    session.teleport = nil

    local place, values = pending.place, nil
    if place.toSteamId then
        -- Teleport to a player: wherever they are now, a step to the side.
        local target = sessionById(place.toSteamId)
        local targetPawn = target and characterOf(target.controller)
        local at = targetPawn and location(targetPawn)
        if at == nil then return tell(session, "Teleport cancelled: " .. place.name .. " is not available right now.") end
        place = { name = place.name, price = place.price, x = math.floor(at.x + 150), y = math.floor(at.y), z = math.floor(at.z + 50) }
    end
    local price = tonumber(place.price) or 0
    values = { x = place.x, y = place.y, z = place.z, price = price, steamId = session.steamId, name = session.name }
    local affordable, why = canAfford(session, price, config.teleports.checkBalance)
    if not affordable then return tell(session, "Teleport cancelled: " .. why .. ".") end
    if price > 0 then
        local ok, detail = runAdminCommand(fill(config.teleports.chargeCommand, values))
        if not ok then return tell(session, "Teleports are not available right now (" .. detail .. ").") end
    end
    local ok, detail
    if config.teleports.method == "direct" then
        ok, detail = teleportDirect(session, tonumber(place.x), tonumber(place.y), tonumber(place.z))
    else
        allowTeleport(session.name)
        ok, detail = runAdminCommand(fill(config.teleports.command, values))
    end
    if not ok then return tell(session, "Teleports are not available right now (" .. detail .. ").") end
    local entry = record(session.steamId, session.name, true)
    entry.lastTeleport = time
    output(string.format("Teleported %s to %s%s.", session.name, place.name, price > 0 and (" for " .. price) or ""))
    tell(session, "Teleported to " .. place.name .. (price > 0 and (" (" .. price .. " paid)") or "") .. ".")
end

-- ------------------------------------------------------------------ feature tips

-- Built from the current settings, so the tips always match what is switched on.
local function featureTips()
    local p = config.chatCommands.prefix
    local tips, features = {}, {}
    local commands = config.chatCommands.enabled

    if commands then tips[#tips + 1] = "Type " .. p .. "help in chat to see all server commands." end
    if config.killFeed.enabled then features[#features + 1] = "kill feed" end
    if config.stats.enabled then
        features[#features + 1] = commands and ("stats (" .. p .. "stats, " .. p .. "top)") or "stats"
        if commands then tips[#tips + 1] = "Type " .. p .. "stats for your kills, deaths and playtime, " .. p .. "top for the leaderboard." end
    end
    if config.killStreaks.enabled then features[#features + 1] = "kill streaks" end
    local bounties = config.bounties
    if bounties.enabled and (tonumber(bounties.streakBountyAt) or 0) > 0 then
        features[#features + 1] = "bounties"
        tips[#tips + 1] = string.format("Get a %d kill streak and the server puts a %d bounty on your head. Whoever kills you collects it.",
            tonumber(bounties.streakBountyAt), tonumber(bounties.streakBountyAmount) or 0)
    end
    local rewards = config.playtimeRewards
    if rewards.enabled and (#(rewards.commands or {}) > 0 or #(rewards.items or {}) > 0) then
        features[#features + 1] = "playtime rewards"
        tips[#tips + 1] = string.format("You earn a reward for every %d minutes played%s.", tonumber(rewards.everyMinutes) or 60,
            rewards.dailyEnabled ~= false and (#(rewards.dailyCommands or {}) > 0 or #(rewards.dailyItems or {}) > 0)
                and ", plus a daily login bonus" or "")
    end
    if config.voting.enabled and commands then
        local names = {}
        for _, option in ipairs(voteOptions()) do names[#names + 1] = option.name end
        if #names > 0 then
            features[#features + 1] = "votes (" .. p .. "vote)"
            tips[#tips + 1] = "Vote to change the server: " .. p .. "vote " .. table.concat(names, " / ") .. "."
        end
    end
    if config.teleports.enabled and commands then
        local names = {}
        for _, place in ipairs(teleportLocations()) do names[#names + 1] = place.name end
        if #names > 0 then
            features[#features + 1] = "teleports (" .. p .. "tp)"
            tips[#tips + 1] = "Teleport for a fee: " .. p .. "tp " .. table.concat(names, " / ") .. ". Type " .. p .. "tp for prices."
        end
    end
    if config.info.enabled and commands then tips[#tips + 1] = "Type " .. p .. "info for the next restart and who is online." end
    if config.reports.enabled and commands then
        features[#features + 1] = "reports (" .. p .. "report)"
        tips[#tips + 1] = "See a cheater or a problem? Type " .. p .. "report <name> <what happened> and the admins are told."
    end
    if config.afk.enabled then tips[#tips + 1] = "Players who are AFK for " .. config.afk.minutes .. " minutes are kicked." end
    if config.manhunt.enabled and commands then
        features[#features + 1] = "manhunts (" .. p .. "manhunt)"
        tips[#tips + 1] = "Feeling brave? " .. p .. "manhunt join and you may become the hunted. Survive and you win."
    end
    local hasZones = false
    for _, zone in ipairs(config.koth.zones or {}) do
        if type(zone) == "table" and zone.name and tonumber(zone.x) then hasZones = true end
    end
    if config.koth.enabled and hasZones then
        features[#features + 1] = "King of the Hill"
        tips[#tips + 1] = "King of the Hill events: hold the announced zone the longest to win."
    end
    if config.hotspots.enabled then tips[#tips + 1] = "Big fights are announced. Follow the gunfire, or stay away from it." end
    if commands then tips[#tips + 1] = "Type " .. p .. "seen <name> to see when a player was last online." end
    if commands and (config.chatCommands.discord or "") ~= "" then tips[#tips + 1] = "Join our Discord: " .. config.chatCommands.discord end
    for _, tip in ipairs(config.featureTips.extraTips or {}) do tips[#tips + 1] = tostring(tip) end

    local summary = nil
    if #features > 0 then
        summary = "This server has: " .. table.concat(features, ", ") .. "." .. (commands and (" Type " .. p .. "help for all commands.") or "")
    end
    return summary, tips
end

local tipIndex, lastTip = 0, nil

local function announceTip(time, online)
    local every = (tonumber(config.featureTips.announceEveryMinutes) or 0) * 60
    if every <= 0 or online == 0 then return end
    lastTip = lastTip or time
    if time - lastTip < every then return end
    lastTip = time
    local _, tips = featureTips()
    if #tips == 0 then return end
    tipIndex = tipIndex % #tips + 1
    announce("Tip: " .. tips[tipIndex])
end

-- ------------------------------------------------------------------ map sectors
-- SCUM's map grid has rows A, B, C, D and Z and columns 0 to 4 over the island. The four
-- outposts are in A0, B4, C2 and Z3, so their bankers (or teleport destinations named a0, b4,
-- c2 and z3) show which way the grid lies on this map.
-- Sector names are only used once all four bankers land in the right sector.

local GRID_MIN, GRID_SIZE = -904800, 1524000   -- cm: five 3048 m sectors each way
local ROW_ORDERS = { { "A", "B", "C", "D", "Z" }, { "Z", "A", "B", "C", "D" } }
local OUTPOST_SECTOR_SET = { A0 = true, B4 = true, C2 = true, Z3 = true }
local grid = nil
local gridTries, lastGridTry = 0, nil
local GRID_TRIES = 30   -- once a minute for half an hour (destinations may be added meanwhile)

local function cell(value, direction)
    local t = (value - GRID_MIN) / GRID_SIZE
    if direction < 0 then t = 1 - t end
    return math.floor(t * 5)
end

local function sectorWith(layout, position)
    local row = cell(position[layout.rowAxis], layout.rowDirection)
    local column = cell(position[layout.columnAxis], layout.columnDirection)
    if row < 0 or row > 4 or column < 0 or column > 4 then return nil end
    return layout.rows[row + 1] .. column
end

local function calibrateGrid(time)
    if grid or gridTries >= GRID_TRIES or (lastGridTry and time - lastGridTry < 60) then return end
    lastGridTry, gridTries = time, gridTries + 1

    local points = {}
    for _, banker in ipairs(findAll({ "BP_Banker_C", "Banker" })) do
        local at = location(banker)
        local duplicate = false
        for _, point in ipairs(points) do
            if at and math.abs(point.x - at.x) < 30000 and math.abs(point.y - at.y) < 30000 then duplicate = true end
        end
        if at and not duplicate then points[#points + 1] = at end
    end
    if #points ~= 4 then
        -- Fall back to teleport destinations named after the outposts (SCUM Manager's
        -- "Add outposts as teleports" names them a0, b4, c2 and z3).
        points = {}
        for _, place in ipairs(teleportLocations()) do
            if OUTPOST_SECTOR_SET[string.upper(place.name)] then
                points[#points + 1] = { x = tonumber(place.x), y = tonumber(place.y), z = tonumber(place.z) }
            end
        end
        if #points ~= 4 then return end
    end

    for _, rows in ipairs(ROW_ORDERS) do
        for _, rowAxis in ipairs({ "x", "y" }) do
            for _, rowDirection in ipairs({ 1, -1 }) do
                for _, columnDirection in ipairs({ 1, -1 }) do
                    local layout = { rows = rows, rowAxis = rowAxis, rowDirection = rowDirection,
                        columnAxis = rowAxis == "x" and "y" or "x", columnDirection = columnDirection }
                    local found = {}
                    for _, point in ipairs(points) do
                        local sector = sectorWith(layout, point)
                        if sector and OUTPOST_SECTOR_SET[sector] then found[sector] = true end
                    end
                    if found.A0 and found.B4 and found.C2 and found.Z3 then
                        grid = layout
                        output("Map sectors worked out from the outposts.")
                        return
                    end
                end
            end
        end
    end
    if gridTries == 1 then output("The outposts do not match SCUM's sector grid; places are described by the nearest destination instead.") end
end

-- "in sector B2", or "near <teleport destination or KotH zone>", or nil. Position in cm.
local function describePlace(position)
    if position == nil then return nil end
    if grid then
        local sector = sectorWith(grid, position)
        if sector then return "in sector " .. sector end
    end
    local best, bestDistance = nil, 300000   -- 3 km
    local candidates = {}
    for _, place in ipairs(teleportLocations()) do candidates[#candidates + 1] = place end
    for _, zone in ipairs(config.koth.zones or {}) do
        if type(zone) == "table" and zone.name and tonumber(zone.x) then candidates[#candidates + 1] = zone end
    end
    for _, place in ipairs(candidates) do
        local d = math.sqrt((tonumber(place.x) - position.x) ^ 2 + (tonumber(place.y) - position.y) ^ 2)
        if d < bestDistance then best, bestDistance = place.name, d end
    end
    return best and ("near " .. best) or nil
end

-- ------------------------------------------------------------------ queued rewards

local pendingRewards = {}   -- rewards that wait for an admin (commands) or for the player to spawn

local function queueReward(steamId, commands, items, message)
    pendingRewards[#pendingRewards + 1] = { steamId = steamId, commands = commands or {}, items = items or {}, message = message }
end

local function payQueuedRewards(session)
    for index = #pendingRewards, 1, -1 do
        local reward = pendingRewards[index]
        if reward.steamId == session.steamId then
            local values = { name = session.name, steamId = session.steamId }
            if giveReward(session, reward.commands, reward.items, values) then
                table.remove(pendingRewards, index)
                if reward.message then tell(session, reward.message) end
            end
        end
    end
end

-- ------------------------------------------------------------------ death recap and hotspots

local recentKillPlaces = {}   -- { time, at (cm) }
local lastHotspot = {}        -- place -> time

local function deathRecap(kill)
    local recap = config.deathRecap
    if not recap.enabled or kill.victimId == nil then return end
    local victim = sessionById(kill.victimId)
    if victim == nil then return end
    local killer = records[kill.killerId]
    local text = fill(recap.message, {
        killer = kill.killerName or "?", weapon = weaponName(kill.weapon),
        distance = kill.distance and string.format("%d", math.floor(kill.distance + 0.5)) or "?",
    })
    -- The killer's streak is counted after this hook, so add this kill.
    local streak = killer and ((killer.streak or 0) + 1) or 0
    if streak >= 2 then text = text .. " They are on a " .. streak .. " kill streak." end
    tell(victim, text)
end

local function hotspotCheck(kill, time)
    local hotspots = config.hotspots
    if not hotspots.enabled or kill.victimAt == nil then return end
    local at = { x = kill.victimAt.x * CM_PER_M, y = kill.victimAt.y * CM_PER_M, z = kill.victimAt.z * CM_PER_M }
    local window = (tonumber(hotspots.withinMinutes) or 5) * 60
    local radius = (tonumber(hotspots.radius) or 500) * CM_PER_M

    local kept = {}
    for _, entry in ipairs(recentKillPlaces) do
        if time - entry.time <= window then kept[#kept + 1] = entry end
    end
    kept[#kept + 1] = { time = time, at = at }
    recentKillPlaces = kept

    local nearby = 0
    for _, entry in ipairs(kept) do
        if math.sqrt((entry.at.x - at.x) ^ 2 + (entry.at.y - at.y) ^ 2) <= radius then nearby = nearby + 1 end
    end
    if nearby < (tonumber(hotspots.kills) or 3) then return end

    local place = describePlace(at)
    if place == nil then return end
    local cooldown = (tonumber(hotspots.cooldownMinutes) or 10) * 60
    if lastHotspot[place] and time - lastHotspot[place] < cooldown then return end
    lastHotspot[place] = time
    announce(fill(hotspots.message, { place = place, kills = nearby }))
end

-- ------------------------------------------------------------------ manhunt

local hunt = nil       -- { targetId, targetName, endsAt, nextReveal }
local lastHunt = nil

local function revealTarget(session)
    local pawn = characterOf(session.controller)
    local place = describePlace(pawn and location(pawn))
    announce(string.format("Manhunt: %s was last seen %s.", session.name, place or "somewhere on the island"))
end

local function manhuntTick(time, online)
    local settings = config.manhunt
    if hunt then
        local target = sessionById(hunt.targetId)
        if target == nil then
            announce("Manhunt over: " .. hunt.targetName .. " left the server.")
            hunt = nil
        elseif time >= hunt.endsAt then
            announce("Manhunt over: " .. hunt.targetName .. " survived and wins the reward!")
            queueReward(hunt.targetId, settings.survivorCommands, settings.survivorItems, "You survived the manhunt. Reward received!")
            output("Manhunt: " .. hunt.targetName .. " survived.")
            hunt = nil
        elseif time >= hunt.nextReveal then
            hunt.nextReveal = time + (tonumber(settings.revealEveryMinutes) or 3) * 60
            revealTarget(target)
        end
        return
    end

    if not settings.enabled or online < (tonumber(settings.minPlayers) or 3) then return end
    lastHunt = lastHunt or time
    if time - lastHunt < (tonumber(settings.everyMinutes) or 60) * 60 then return end
    lastHunt = time

    local candidates = {}
    for _, session in pairs(sessions) do
        local entry = session.steamId and records[session.steamId]
        if entry and entry.manhunt == "1" and characterOf(session.controller) then candidates[#candidates + 1] = session end
    end
    if #candidates == 0 then return end
    table.sort(candidates, function(a, b) return a.name < b.name end)
    local target = candidates[math.random(#candidates)]
    local minutes = tonumber(settings.durationMinutes) or 15
    hunt = { targetId = target.steamId, targetName = target.name, endsAt = time + minutes * 60,
        nextReveal = time + (tonumber(settings.revealEveryMinutes) or 3) * 60 }
    announce(string.format("MANHUNT! %s is the target for %d minutes. Kill them for a reward; if they survive, they win it.", target.name, minutes))
    revealTarget(target)
    tell(target, "You are the manhunt target! Survive " .. minutes .. " minutes to win.")
    output("Manhunt started on " .. target.name .. ".")
end

local function manhuntKill(kill)
    if hunt == nil or kill.victimId ~= hunt.targetId or kill.killerId == hunt.targetId then return end
    announce(string.format("Manhunt over: %s killed %s!", kill.killerName or "?", hunt.targetName))
    queueReward(kill.killerId, config.manhunt.hunterCommands, config.manhunt.hunterItems, "You won the manhunt. Reward received!")
    output("Manhunt: " .. (kill.killerName or "?") .. " killed " .. hunt.targetName .. ".")
    hunt = nil
end

local function manhuntCommand(session, rest)
    local action = string.lower(rest or "")
    local entry = session.steamId and record(session.steamId, session.name, true)
    if entry and action == "join" then
        entry.manhunt, recordsDirty = "1", true
        return tell(session, "You can now be picked as the manhunt target. " .. config.chatCommands.prefix .. "manhunt leave to stop.")
    elseif entry and action == "leave" then
        entry.manhunt, recordsDirty = "", true
        return tell(session, "You will not be picked as the manhunt target.")
    end
    local lines = {}
    if hunt then lines[1] = "Manhunt running: " .. hunt.targetName .. " is the target." else lines[1] = "No manhunt right now." end
    lines[#lines + 1] = "Volunteer as a target: " .. config.chatCommands.prefix .. "manhunt join (" .. ((entry and entry.manhunt == "1") and "you are in" or "you are out") .. ")."
    tell(session, lines)
end

-- ------------------------------------------------------------------ king of the hill

local hill = nil       -- { zone, endsAt, nextUpdate, scores = { id = seconds }, names = { id = name } }
local lastHill = nil

local function kothZones()
    local zones = {}
    for _, zone in ipairs(config.koth.zones or {}) do
        if type(zone) == "table" and zone.name and tonumber(zone.x) and tonumber(zone.y) then zones[#zones + 1] = zone end
    end
    return zones
end

local function hillLeader()
    local bestId, bestScore = nil, 0
    for id, score in pairs(hill.scores) do
        if score > bestScore or (score == bestScore and bestId and id < bestId) then bestId, bestScore = id, score end
    end
    return bestId, bestScore
end

local function kothTick(time, elapsed, online)
    local settings = config.koth
    if hill then
        local zone = hill.zone
        local radius = (tonumber(zone.radius) or 100) * CM_PER_M
        for _, session in pairs(sessions) do
            local pawn = session.steamId and characterOf(session.controller)
            local at = pawn and location(pawn)
            if at and math.sqrt((at.x - tonumber(zone.x)) ^ 2 + (at.y - tonumber(zone.y)) ^ 2) <= radius then
                hill.scores[session.steamId] = (hill.scores[session.steamId] or 0) + elapsed
                hill.names[session.steamId] = session.name
            end
        end

        if time >= hill.endsAt then
            local winner, score = hillLeader()
            if winner and score >= (tonumber(settings.minSeconds) or 60) then
                announce(string.format("King of the Hill over: %s held %s for %s and wins!", hill.names[winner], zone.name, duration(score)))
                queueReward(winner, settings.rewardCommands, settings.rewardItems, "You won King of the Hill. Reward received!")
                output("King of the Hill: " .. hill.names[winner] .. " won.")
            else
                announce("King of the Hill over: nobody held " .. zone.name .. " long enough.")
            end
            hill = nil
        elseif time >= hill.nextUpdate then
            hill.nextUpdate = time + (tonumber(settings.updateEveryMinutes) or 5) * 60
            local leader, score = hillLeader()
            announce(string.format("King of the Hill at %s: %s, %s left.", zone.name,
                leader and (hill.names[leader] .. " leads with " .. duration(score)) or "nobody has held it yet",
                duration(hill.endsAt - time)))
        end
        return
    end

    local zones = kothZones()
    if not settings.enabled or #zones == 0 or online < (tonumber(settings.minPlayers) or 3) then return end
    lastHill = lastHill or time
    if time - lastHill < (tonumber(settings.everyMinutes) or 90) * 60 then return end
    lastHill = time

    local zone = zones[math.random(#zones)]
    local minutes = tonumber(settings.durationMinutes) or 15
    hill = { zone = zone, endsAt = time + minutes * 60, nextUpdate = time + (tonumber(settings.updateEveryMinutes) or 5) * 60,
        scores = {}, names = {} }
    local place = describePlace({ x = tonumber(zone.x), y = tonumber(zone.y), z = tonumber(zone.z) or 0 })
    announce(string.format("KING OF THE HILL at %s%s for %d minutes! Stay within %d m of it longest to win.", zone.name,
        place and place ~= ("near " .. zone.name) and (" (" .. place .. ")") or "", minutes, tonumber(zone.radius) or 100))
    output("King of the Hill started at " .. zone.name .. ".")
end

-- ------------------------------------------------------------------ economy
-- Shop, !pay, lottery, daily tasks, kill race and squad bonus. Money moves with
-- ChangeCurrencyBalance through runAdminCommand (an online admin, or the no-admin route).
-- Spending always checks the balance first; whatever is won is kept in the player's record
-- (credit) until it has been paid, so nothing is lost while they are offline or no route exists.
-- Built inside its own function (Lua allows 200 locals per function and this file is near
-- that); only what the rest of the file uses leaves it, through the economy table.
local economy = (function()

local function moneyCommand(steamId, amount)
    return string.format("ChangeCurrencyBalance Normal %d %s", amount, steamId)
end

-- Takes money from an online player after checking they have it. Returns ok, why.
local function charge(session, amount, what)
    if amount <= 0 then return true end
    if session.steamId == nil then return false, "your SteamID is not known yet; type any ! command and try again" end
    local affordable, why = canAfford(session, amount, true)
    if not affordable then return false, why end
    local ok, detail = runAdminCommand(moneyCommand(session.steamId, -amount))
    if not ok then return false, "money cannot be moved right now (" .. tostring(detail) .. ")" end
    output(string.format("Charged %s %d for %s.", session.name, amount, what))
    return true
end

-- Winnings: paid now when possible, otherwise kept and paid once they are online.
local function credit(steamId, name, amount, why)
    if amount <= 0 then return end
    local entry = record(steamId, name)
    entry.credit = (entry.credit or 0) + amount
    recordsDirty = true
    output(string.format("%s is owed %d (%s).", entry.name, amount, why))
end

local function payCredit(session)
    local entry = session.steamId and records[session.steamId]
    if entry == nil or (entry.credit or 0) <= 0 then return end
    local ok = runAdminCommand(moneyCommand(session.steamId, entry.credit))
    if ok then
        tell(session, string.format("%d added to your account (winnings and rewards).", entry.credit))
        output(string.format("Paid %d to %s.", entry.credit, session.name))
        entry.credit = 0
        recordsDirty = true
    end
end

local function whole(text)
    local value = text ~= nil and tonumber(text) or nil
    if value == nil or value ~= math.floor(value) then return nil end
    return value
end

-- !shop and !buy <name> [count]
local function shopItem(name)
    local wanted = string.lower(name or "")
    for _, entry in ipairs(config.shop.items or {}) do
        if string.lower(tostring(entry.name or entry.item or "")) == wanted then return entry end
    end
    return nil
end

local function shopCommand(session, word, rest)
    local prefix = config.chatCommands.prefix
    local items = config.shop.items or {}
    if word == "shop" then
        if #items == 0 then return tell(session, "The shop is empty.") end
        local lines = { "Shop (" .. prefix .. "buy <name> [count]):" }
        for _, entry in ipairs(items) do
            lines[#lines + 1] = string.format("%s x%d: %d", tostring(entry.name or entry.item), tonumber(entry.amount) or 1, tonumber(entry.price) or 0)
        end
        return tell(session, lines)
    end
    local name, count = string.match(rest or "", "^(.-)%s+(%d+)$")
    if name == nil then name, count = rest, "1" end
    local entry = shopItem(name)
    if entry == nil then return tell(session, "No shop item called " .. tostring(name) .. ". Type " .. prefix .. "shop for the list.") end
    count = math.max(1, math.min(whole(count) or 1, tonumber(config.shop.maxPerPurchase) or 5))
    local price = (tonumber(entry.price) or 0) * count
    if characterOf(session.controller) == nil then return tell(session, "You need to be alive to buy something.") end
    local paid, why = charge(session, price, count .. " x " .. tostring(entry.name or entry.item))
    if not paid then return tell(session, "Purchase cancelled: " .. why .. ".") end
    local given, failure = giveItems(session, { { item = entry.item, amount = (tonumber(entry.amount) or 1) * count } }, true)
    if given == nil or given == 0 then
        credit(session.steamId, session.name, price, "refund: the shop could not hand over " .. tostring(entry.item))
        payCredit(session)
        return tell(session, "The item could not be handed over (" .. tostring(failure or "unknown item") .. "); you have been refunded.")
    end
    tell(session, string.format("Bought %d x %s for %d.", count, tostring(entry.name or entry.item), price))
end

-- !pay <name> <amount>
local function payCommand(session, rest)
    local settings = config.pay
    local name, amount = string.match(rest or "", "^(.-)%s+(%d+)$")
    amount = whole(amount)
    if name == nil or amount == nil then return tell(session, "Usage: " .. config.chatCommands.prefix .. "pay <name> <amount>") end
    local target = onlineByName(name)
    if target == nil or target.steamId == nil then return tell(session, "No player online called " .. name .. ".") end
    if target == session then return tell(session, "You cannot pay yourself.") end
    local low, high = tonumber(settings.minAmount) or 1, tonumber(settings.maxAmount) or 100000
    if amount < low or amount > high then return tell(session, string.format("Amounts from %d to %d.", low, high)) end
    local fee = math.floor(amount * (tonumber(settings.feePercent) or 0) / 100)
    local paid, why = charge(session, amount + fee, "a payment to " .. target.name)
    if not paid then return tell(session, "Payment cancelled: " .. why .. ".") end
    credit(target.steamId, target.name, amount, "payment from " .. session.name)
    payCredit(target)
    tell(session, string.format("Paid %d to %s%s.", amount, target.name, fee > 0 and string.format(" (fee %d)", fee) or ""))
    tell(target, string.format("%s paid you %d.", session.name, amount))
end

-- Lottery: tickets and the next draw are kept in lottery.tsv, so a restart loses nothing.
local LOTTERY_FILE = DIR .. "/lottery.tsv"
local lottery = nil   -- { draw = time, tickets = { steamId = { name, count } } }

local function saveLottery()
    local file = io.open(LOTTERY_FILE, "w")
    if not file then return end
    file:write("draw\t" .. string.format("%d", lottery.draw) .. "\n")
    for steamId, entry in pairs(lottery.tickets) do
        file:write(steamId .. "\t" .. (string.gsub(entry.name, "[\t\r\n]", " ")) .. "\t" .. entry.count .. "\n")
    end
    file:close()
end

local function loadLottery(time)
    lottery = { draw = time + (tonumber(config.lottery.drawEveryMinutes) or 60) * 60, tickets = {} }
    for line in string.gmatch(readText(LOTTERY_FILE) or "", "[^\r\n]+") do
        local first, second, third = string.match(line, "^([^\t]*)\t([^\t]*)\t?([^\t]*)$")
        if first == "draw" then
            lottery.draw = tonumber(second) or lottery.draw
        elseif first and string.match(first, "^%d+$") and tonumber(third) then
            lottery.tickets[first] = { name = second, count = tonumber(third) }
        end
    end
end

local function lotteryTotals()
    local tickets = 0
    for _, entry in pairs(lottery.tickets) do tickets = tickets + entry.count end
    return tickets, tickets * (tonumber(config.lottery.ticketPrice) or 0)
end

local function lotteryCommand(session, rest, time)
    local settings = config.lottery
    if lottery == nil then loadLottery(time) end
    local buying = string.match(rest or "", "^buy%s*(%d*)$")
    local count = buying ~= nil and (whole(buying ~= "" and buying or "1")) or nil
    if count == nil then
        local tickets, pot = lotteryTotals()
        local mine = session.steamId and lottery.tickets[session.steamId]
        return tell(session, {
            string.format("Lottery: %d ticket(s), pot %d, draw in %d min. Ticket %d.", tickets, pot,
                math.max(0, math.ceil((lottery.draw - time) / 60)), tonumber(settings.ticketPrice) or 0),
            string.format("You have %d. Buy with %slottery buy [count].", mine and mine.count or 0, config.chatCommands.prefix),
        })
    end
    local have = session.steamId and lottery.tickets[session.steamId] and lottery.tickets[session.steamId].count or 0
    local limit = tonumber(settings.maxTicketsPerPlayer) or 10
    count = math.max(1, math.min(count, limit - have))
    if have >= limit then return tell(session, "You already have the most tickets allowed (" .. limit .. ").") end
    local paid, why = charge(session, count * (tonumber(settings.ticketPrice) or 0), count .. " lottery ticket(s)")
    if not paid then return tell(session, "No tickets bought: " .. why .. ".") end
    lottery.tickets[session.steamId] = { name = session.name, count = have + count }
    saveLottery()
    tell(session, string.format("Bought %d ticket(s); you have %d. Good luck!", count, have + count))
end

local function lotteryTick(time)
    local settings = config.lottery
    if not settings.enabled then return end
    if lottery == nil then loadLottery(time) end
    if time < lottery.draw then return end
    local tickets, pot = lotteryTotals()
    if tickets > 0 and tickets < (tonumber(settings.minTickets) or 2) then
        for steamId, entry in pairs(lottery.tickets) do
            credit(steamId, entry.name, entry.count * (tonumber(settings.ticketPrice) or 0), "lottery refund, too few tickets")
        end
        announce("Lottery: not enough tickets this time, everyone has been refunded.")
    elseif tickets > 0 then
        local pick, winner = math.random(tickets), nil
        for steamId, entry in pairs(lottery.tickets) do
            pick = pick - entry.count
            if pick <= 0 and winner == nil then winner = { steamId = steamId, name = entry.name } end
        end
        local prize = math.floor(pot * (100 - (tonumber(settings.housePercent) or 0)) / 100)
        credit(winner.steamId, winner.name, prize, "lottery win")
        announce(string.format("LOTTERY: %s wins %d! Next draw in %d min.", winner.name, prize, tonumber(settings.drawEveryMinutes) or 60))
    end
    lottery.tickets = {}
    lottery.draw = time + (tonumber(settings.drawEveryMinutes) or 60) * 60
    saveLottery()
end

-- Daily tasks: progress kept in the record as "date|kind=value,...|done=1,3".
local function taskState(entry, time)
    local date, values, done = string.match(entry.tasks or "", "^([^|]*)|([^|]*)|(.*)$")
    local state = { date = os.date("!%Y-%m-%d", time), values = {}, done = {} }
    if date ~= state.date then return state end
    for kind, value in string.gmatch(values or "", "(%w+)=([%d%.]+)") do state.values[kind] = tonumber(value) end
    for index in string.gmatch(done or "", "(%d+)") do state.done[tonumber(index)] = true end
    return state
end

local function saveTaskState(entry, state)
    local values, done = {}, {}
    for kind, value in pairs(state.values) do values[#values + 1] = kind .. "=" .. string.format("%d", math.floor(value)) end
    for index in pairs(state.done) do done[#done + 1] = tostring(index) end
    table.sort(values)
    table.sort(done)
    entry.tasks = state.date .. "|" .. table.concat(values, ",") .. "|" .. table.concat(done, ",")
    recordsDirty = true
end

-- kind: "playtime" (minutes, added), "kills" (added), "longshot" (metres, best so far).
local function taskProgress(steamId, name, kind, amount, time)
    local settings = config.dailyTasks
    if not settings.enabled or steamId == nil then return end
    local entry = record(steamId, name)
    local state = taskState(entry, time)
    if kind == "longshot" then
        state.values[kind] = math.max(state.values[kind] or 0, amount)
    else
        state.values[kind] = (state.values[kind] or 0) + amount
    end
    for index, task in ipairs(settings.tasks or {}) do
        if task.kind == kind and not state.done[index] and (state.values[kind] or 0) >= (tonumber(task.target) or math.huge) then
            state.done[index] = true
            credit(steamId, entry.name, tonumber(task.reward) or 0, "daily task: " .. tostring(task.text))
            local session = sessionById(steamId)
            if session then tell(session, "Daily task done: " .. tostring(task.text) .. ". Reward: " .. tostring(task.reward) .. ".") end
        end
    end
    saveTaskState(entry, state)
end

local function tasksCommand(session, time)
    local entry = session.steamId and records[session.steamId]
    if entry == nil then return tell(session, "Your tasks start counting once the server knows your SteamID.") end
    local state = taskState(entry, time)
    local lines = { "Daily tasks (reset at midnight UTC):" }
    for index, task in ipairs(config.dailyTasks.tasks or {}) do
        local value = math.floor(state.values[task.kind] or 0)
        lines[#lines + 1] = string.format("%s %s: %d/%d, reward %d", state.done[index] and "[done]" or "[ ]",
            tostring(task.text), math.min(value, tonumber(task.target) or 0), tonumber(task.target) or 0, tonumber(task.reward) or 0)
    end
    tell(session, lines)
end

-- Kill race: most player kills during the race wins the prize.
local race = { state = "idle", nextAt = nil, endsAt = nil, kills = {} }

local function raceTick(time, online)
    local settings = config.killRace
    if not settings.enabled then race.state = "idle" return end
    race.nextAt = race.nextAt or time + (tonumber(settings.everyMinutes) or 120) * 60
    if race.state == "idle" and time >= race.nextAt then
        race.nextAt = time + (tonumber(settings.everyMinutes) or 120) * 60
        if online < (tonumber(settings.minPlayers) or 3) then return end
        race.state, race.endsAt, race.kills = "running", time + (tonumber(settings.durationMinutes) or 20) * 60, {}
        announce(string.format("KILL RACE! Most player kills in the next %d minutes wins %d.", tonumber(settings.durationMinutes) or 20, tonumber(settings.prize) or 0))
    elseif race.state == "running" and time >= race.endsAt then
        race.state = "idle"
        local best, bestCount = nil, 0
        for steamId, entry in pairs(race.kills) do
            if entry.count > bestCount then best, bestCount = { steamId = steamId, name = entry.name }, entry.count end
        end
        if best == nil then return announce("Kill race over: nobody scored.") end
        credit(best.steamId, best.name, tonumber(settings.prize) or 0, "kill race win")
        announce(string.format("Kill race over: %s wins %d with %d kill(s)!", best.name, tonumber(settings.prize) or 0, bestCount))
    end
end

-- Player kills that count for tasks and the race: not suicides or squadmates.
local function economyKill(kill, time)
    if kill.killerId == nil or kill.victimId == nil or kill.killerId == kill.victimId then return end
    if sameSquad(kill.killerId, kill.victimId) then return end
    taskProgress(kill.killerId, kill.killerName, "kills", 1, time)
    if kill.distance then taskProgress(kill.killerId, kill.killerName, "longshot", kill.distance, time) end
    if race.state == "running" then
        local entry = race.kills[kill.killerId] or { name = kill.killerName or "?", count = 0 }
        entry.count = entry.count + 1
        race.kills[kill.killerId] = entry
    end
end

-- Squad bonus: every so often, each player gets a little for every squadmate online with them.
local function squadBonusCheck(session, time)
    local settings = config.squadBonus
    if not settings.enabled or session.steamId == nil then return end
    local every = (tonumber(settings.everyMinutes) or 60) * 60
    session.squadBonusAt = session.squadBonusAt or time + every
    if time < session.squadBonusAt then return end
    session.squadBonusAt = time + every
    local mine = squadOf[session.steamId]
    if mine == nil or mine == "" then return end
    local mates = 0
    for _, other in pairs(sessions) do
        if other ~= session and other.steamId and squadOf[other.steamId] == mine then mates = mates + 1 end
    end
    mates = math.min(mates, tonumber(settings.maxMates) or 4)
    if mates > 0 then
        credit(session.steamId, session.name, mates * (tonumber(settings.amountPerMate) or 0), "squad bonus")
    end
end

local playtimeCarry = {}   -- steamId -> seconds not yet counted towards the playtime task

local function economyTick(time, elapsed, online)
    lotteryTick(time)
    raceTick(time, online)
    for _, session in pairs(sessions) do
        if session.steamId then
            local carry = (playtimeCarry[session.steamId] or 0) + elapsed
            if carry >= 60 then
                taskProgress(session.steamId, session.name, "playtime", math.floor(carry / 60), time)
                carry = carry % 60
            end
            playtimeCarry[session.steamId] = carry
            squadBonusCheck(session, time)
            payCredit(session)
        end
    end
end

-- !sell: sells the item in the player's hands. SCUM's own DropItemFromHands puts it down (so
-- the game handles the inventory side), the dropped item is removed like any item left on the
-- ground, and only then is the player paid. Anything unexpected stops it before money moves.
local function plainItemName(name)
    name = string.lower(tostring(name or ""))
    name = string.gsub(name, "^bp_", "")
    name = string.gsub(name, "_c$", "")
    return name
end

local function sellEntry(item)
    local class = safe(function() return item:GetClass():GetFName():ToString() end)
    if class == nil then return nil end
    local wanted = plainItemName(class)
    for _, entry in ipairs(config.sell.items or {}) do
        if plainItemName(entry.item) == wanted then return entry end
    end
    return nil
end

local function sellCommand(session, rest)
    local prefix = config.chatCommands.prefix
    if rest == "prices" or rest == "list" then
        local lines = { "The server buys (hold it and type " .. prefix .. "sell):" }
        for _, entry in ipairs(config.sell.items or {}) do
            lines[#lines + 1] = string.format("%s: %d", tostring(entry.name or entry.item), tonumber(entry.price) or 0)
        end
        if #lines == 1 then lines[2] = "Nothing yet." end
        return tell(session, lines)
    end
    if session.steamId == nil then return tell(session, "Your SteamID is not known yet; type any ! command and try again.") end
    local pawn = characterOf(session.controller)
    if pawn == nil then return tell(session, "You need to be alive to sell.") end
    local item = safe(function() return pawn:GetItemInHands() end)
    if not isValid(item) then return tell(session, "Hold the item you want to sell in your hands, then type " .. prefix .. "sell.") end
    local entry = sellEntry(item)
    if entry == nil then return tell(session, "The server does not buy that. " .. prefix .. "sell prices shows what it buys.") end
    local price = tonumber(entry.price) or 0

    local dropped = pcall(function() pawn:DropItemFromHands() end)
    local stillHeld = safe(function() return pawn:GetItemInHands() end)
    if not dropped or (isValid(stillHeld) and address(stillHeld) == address(item)) then
        return tell(session, "Could not take the item from your hands; nothing was sold.")
    end
    -- Only the exact item that was in their hands is removed: nothing nearby is looked at. If
    -- the game has replaced it since the drop, nothing is removed and nothing is paid.
    if not isValid(item) then
        output("Selling: " .. session.name .. "'s " .. tostring(entry.item) .. " changed when it was dropped; not removed, not paid.")
        return tell(session, "The sale failed; the item is on the ground at your feet.")
    end
    local removed = pcall(function() item:K2_DestroyActor() end)
    if not removed then
        output("Selling: " .. session.name .. "'s " .. tostring(entry.item) .. " was dropped but could not be removed; not paid.")
        return tell(session, "The sale failed; the item is on the ground at your feet.")
    end
    output(string.format("%s sold %s for %d.", session.name, tostring(entry.name or entry.item), price))
    credit(session.steamId, session.name, price, "sold " .. tostring(entry.name or entry.item))
    payCredit(session)
    tell(session, string.format("Sold %s for %d.", tostring(entry.name or entry.item), price))
end

    return {
        shopCommand = shopCommand, payCommand = payCommand, lotteryCommand = lotteryCommand, sellCommand = sellCommand,
        tasksCommand = tasksCommand, economyTick = economyTick, economyKill = economyKill, race = race,
    }
end)()

events.onKill = function(kill, time)
    deathRecap(kill)
    hotspotCheck(kill, time)
    manhuntKill(kill)
    economy.economyKill(kill, time)
end

-- ------------------------------------------------------------------ chat commands

local function handleChat(chat, time)
    if not config.chatCommands.enabled then return end
    local session = sessionForChat(chat)
    if session == nil then
        local names = {}
        for _, candidate in pairs(sessions) do names[#names + 1] = tostring(candidate.name) end
        output("Ignored " .. (config.chatCommands.prefix or "!") .. chat.text .. " from " .. tostring(chat.name) .. " (" .. chat.steamId
            .. "): they do not match a player online (" .. (#names > 0 and table.concat(names, ", ") or "nobody found online") .. ").")
        return
    end
    if session.steamId == nil then session.steamId = chat.steamId end
    if chat.name and session.name ~= chat.name then steamIdByName[session.name] = chat.steamId end

    local prefix = config.chatCommands.prefix
    local word, rest = string.match(chat.text, "^(%S+)%s*(.-)%s*$")
    word = string.lower(word or "")

    if word == "help" then
        local lines = { "Commands:", prefix .. "rules, " .. prefix .. "online" }
        if config.chatCommands.discord ~= "" then lines[2] = lines[2] .. ", " .. prefix .. "discord" end
        if config.stats.enabled then lines[#lines + 1] = prefix .. "stats [name], " .. prefix .. "top" end
        if config.voting.enabled then lines[#lines + 1] = prefix .. "vote <option>, " .. prefix .. "yes, " .. prefix .. "no" end
        local more = {}
        if config.info.enabled then more[#more + 1] = prefix .. "info" end
        if config.bounties.enabled then more[#more + 1] = prefix .. "bounty" end
        if config.teleports.enabled then more[#more + 1] = prefix .. "tp" end
        if config.teleports.enabled and config.teleports.toPlayer then more[#more + 1] = prefix .. "tpto <name>" end
        more[#more + 1] = prefix .. "seen <name>"
        if config.manhunt.enabled then more[#more + 1] = prefix .. "manhunt" end
        if config.shop.enabled then more[#more + 1] = prefix .. "shop, " .. prefix .. "buy" end
        if config.sell.enabled then more[#more + 1] = prefix .. "sell" end
        if config.pay.enabled then more[#more + 1] = prefix .. "pay <name> <amount>" end
        if config.lottery.enabled then more[#more + 1] = prefix .. "lottery" end
        if config.dailyTasks.enabled then more[#more + 1] = prefix .. "tasks" end
        if config.killRace.enabled then more[#more + 1] = prefix .. "race" end
        if config.reports.enabled then more[#more + 1] = prefix .. "report <name> <what happened>" end
        if #more > 0 then lines[#lines + 1] = table.concat(more, ", ") end
        tell(session, lines)
    elseif word == "rules" then
        local lines = { "Server rules:" }
        for index, rule in ipairs(config.chatCommands.rules or {}) do lines[#lines + 1] = index .. ". " .. rule end
        if #lines == 1 then lines[2] = "No rules have been set." end
        tell(session, lines)
    elseif word == "discord" then
        tell(session, config.chatCommands.discord ~= "" and ("Discord: " .. config.chatCommands.discord) or "No Discord link has been set.")
    elseif word == "online" then
        local names = {}
        for _, other in pairs(sessions) do names[#names + 1] = other.name end
        table.sort(names)
        tell(session, #names .. " online: " .. table.concat(names, ", "))
    elseif word == "stats" and config.stats.enabled then
        local entry = session.steamId and records[session.steamId]
        if rest ~= "" then
            entry = nil
            for _, candidate in pairs(records) do
                if string.lower(candidate.name) == string.lower(rest) then entry = candidate break end
            end
            if entry == nil then return tell(session, "No stats for " .. rest .. ".") end
        end
        local lines = entry and statsLines(entry) or { "No stats yet." }
        if type(lines) == "string" then lines = { lines } end
        -- Your own stats also say when the next playtime reward is due.
        local rewards = config.playtimeRewards
        local every = (tonumber(rewards.everyMinutes) or 0) * 60
        if rest == "" and entry and rewards.enabled and every > 0 and #(rewards.commands or {}) > 0 then
            local left = every - (entry.playtime - (entry.rewarded or 0))
            lines[#lines + 1] = left > 0 and string.format("Next playtime reward in %d min.", math.ceil(left / 60))
                or "Playtime reward due now: it is paid as soon as it can be."
        end
        tell(session, lines)
    elseif word == "top" and config.stats.enabled then
        tell(session, topLines())
    elseif word == "vote" and config.voting.enabled then
        startVote(session, rest, time)
    elseif (word == "yes" or word == "no") and config.voting.enabled then
        castVote(session, word)
    elseif word == "info" and config.info.enabled then
        tell(session, infoLines(time))
    elseif word == "report" and config.reports.enabled then
        report(session, rest, time)
    elseif word == "bounty" and config.bounties.enabled then
        bountyCommand(session, rest)
    elseif word == "tp" and config.teleports.enabled then
        teleportCommand(session, rest, time)
    elseif (word == "tpto" or word == "tpaccept" or word == "tpdeny") and config.teleports.enabled then
        playerTeleportCommand(session, word, rest, time)
    elseif word == "seen" then
        local id, entry = findPlayerRecord(rest)
        if id == nil or entry == nil then return tell(session, rest == "" and ("Usage: " .. prefix .. "seen <name>") or ("No player called " .. rest .. ".")) end
        if sessionById(id) then return tell(session, entry.name .. " is online now.") end
        if (entry.lastSeen or 0) <= 0 then return tell(session, entry.name .. " has not been seen since this was turned on.") end
        tell(session, entry.name .. " was last online " .. duration(time - entry.lastSeen) .. " ago.")
    elseif word == "manhunt" and config.manhunt.enabled then
        manhuntCommand(session, rest)
    elseif (word == "shop" or word == "buy") and config.shop.enabled then
        economy.shopCommand(session, word, rest)
    elseif word == "sell" and config.sell.enabled then
        economy.sellCommand(session, string.lower(rest or ""))
    elseif word == "pay" and config.pay.enabled then
        economy.payCommand(session, rest)
    elseif word == "lottery" and config.lottery.enabled then
        economy.lotteryCommand(session, rest, time)
    elseif word == "tasks" and config.dailyTasks.enabled then
        economy.tasksCommand(session, time)
    elseif word == "race" and config.killRace.enabled then
        if economy.race.state == "running" then
            local mine = session.steamId and economy.race.kills[session.steamId]
            tell(session, string.format("Kill race: %d min left, you have %d kill(s).", math.max(0, math.ceil((economy.race.endsAt - time) / 60)), mine and mine.count or 0))
        else
            tell(session, string.format("Next kill race in about %d min.", math.max(0, math.ceil(((economy.race.nextAt or time) - time) / 60))))
        end
    elseif word == "where" and isAdmin(session.controller) then
        local pawn = characterOf(session.controller)
        local position = pawn and location(pawn)
        tell(session, position and string.format("You are at x=%.0f y=%.0f z=%.0f", position.x, position.y, position.z) or "Your position is not known.")
    end
end

-- ------------------------------------------------------------------ new players and AFK

-- A basic survival kit, used when no starter kit items are set. Item codes as in SpawnItem.
local BASIC_STARTER_KIT = {
    { item = "Water_05l", amount = 2 },
    { item = "Canned_Tuna", amount = 1 },
    { item = "BakedBeans", amount = 1 },
    { item = "Apple", amount = 2 },
    { item = "Emergency_bandage", amount = 3 },
    { item = "1H_Improvised_metal_knife", amount = 1 },
    { item = "Improvised_Bag_Small_01", amount = 1 },
}

local function starterKitItems()
    local kit = config.newPlayers
    if #(kit.starterKitItems or {}) > 0 then return kit.starterKitItems end
    if kit.starterKitPreset == "basic" then return BASIC_STARTER_KIT end
    return {}
end

local function newPlayerCheck(session, time)
    if session.newChecked or session.steamId == nil then return end
    local pawn = characterOf(session.controller)
    if pawn == nil then return end
    session.spawnedAt = session.spawnedAt or time
    if time - session.spawnedAt < SPAWN_DELAY then return end

    local entry = record(session.steamId, session.name, true)
    if entry.new then
        entry.new = nil
        session.welcomedBack = true
        local lines = {}
        for _, message in ipairs(config.newPlayers.messages or {}) do
            lines[#lines + 1] = fill(message, { name = session.name, steamId = session.steamId })
        end
        if #lines > 0 then tell(session, lines) end
        output("New player: " .. session.name .. " (" .. session.steamId .. ")")
    elseif not session.welcomedBack then
        session.welcomedBack = true
        if config.welcomeBack.enabled and (config.welcomeBack.message or "") ~= "" then
            tell(session, fill(config.welcomeBack.message, {
                name = session.name, hours = hours(entry.playtime), kills = entry.kills, deaths = entry.deaths,
                bestStreak = entry.bestStreak or 0,
            }))
        end
    end

    if not session.toldFeatures then
        session.toldFeatures = true
        local summary = featureTips()
        if config.featureTips.onJoin and summary then tell(session, summary) end
    end

    if config.newPlayers.starterKit and entry.kit == "pending" then
        local kit = config.newPlayers
        local position = location(pawn)
        local values = {
            name = session.name, steamId = session.steamId,
            location = position and string.format("X=%.0f Y=%.0f Z=%.0f", position.x, position.y, position.z + 50) or "",
        }
        local kitItems = config.itemRewards.enabled and starterKitItems() or {}
        if #(kit.starterKitCommands or {}) == 0 and #kitItems == 0 then
            session.newChecked = true
            return
        end
        local ok, detail = giveReward(session, kit.starterKitCommands, kitItems, values)
        if not ok then
            -- Try again later (for example when an admin comes online).
            if not session.kitWaitReported then
                session.kitWaitReported = true
                output("Starter kit for " .. session.name .. " is waiting: " .. detail .. ".")
            end
            return
        end
        entry.kit = "given"
        recordsDirty = true
        if (kit.starterKitMessage or "") ~= "" then
            tell(session, fill(kit.starterKitMessage, values))
        end
        output("Gave a starter kit to " .. session.name .. ".")
    end
    session.newChecked = true
end

local function today(time)
    return os.date("!%Y-%m-%d", time)
end

-- Playtime rewards, the daily bonus and bounty payouts. All need an admin online; until then
-- they stay owed and are retried every second.
local function rewardCheck(session, time)
    if session.steamId == nil or characterOf(session.controller) == nil then return end
    local entry = records[session.steamId]
    if entry == nil then return end
    local values = { name = session.name, steamId = session.steamId }

    local rewards = config.playtimeRewards
    if rewards.enabled then
        local itemsOn = config.itemRewards.enabled
        local hasDaily = rewards.dailyEnabled ~= false
            and (#(rewards.dailyCommands or {}) > 0 or (itemsOn and #(rewards.dailyItems or {}) > 0))
        -- Logged when paid, and once per reason while a reward waits, so it can be followed.
        local function waiting(kind, why)
            local key = kind .. ":" .. tostring(why)
            if session.rewardWait ~= key then
                session.rewardWait = key
                output(string.format("%s for %s is waiting: %s.", kind, session.name, tostring(why)))
            end
        end
        if hasDaily and entry.daily ~= today(time) then
            local paid, why = giveReward(session, rewards.dailyCommands, rewards.dailyItems, values)
            if paid then
                entry.daily = today(time)
                recordsDirty = true
                session.rewardWait = nil
                output("Paid the daily bonus to " .. session.name .. ".")
                if (rewards.dailyMessage or "") ~= "" then tell(session, fill(rewards.dailyMessage, values)) end
            else
                waiting("Daily bonus", why)
            end
        end
        local every = (tonumber(rewards.everyMinutes) or 0) * 60
        local hasReward = #(rewards.commands or {}) > 0 or (itemsOn and #(rewards.items or {}) > 0)
        if every > 0 and hasReward and entry.playtime - (entry.rewarded or 0) >= every then
            local paid, why = giveReward(session, rewards.commands, rewards.items, values)
            if paid then
                entry.rewarded = (entry.rewarded or 0) + every
                recordsDirty = true
                session.rewardWait = nil
                output(string.format("Paid the playtime reward to %s (%.0f min played in total).", session.name, entry.playtime / 60))
                if (rewards.message or "") ~= "" then tell(session, fill(rewards.message, values)) end
            else
                waiting("Playtime reward", why)
            end
        end
    end

    payQueuedRewards(session)

    if config.bounties.enabled and (entry.owed or 0) > 0 then
        local ok = runAdminCommand(fill(config.bounties.payCommand, { amount = entry.owed, steamId = session.steamId, name = session.name }))
        if ok then
            tell(session, "Bounty paid: " .. entry.owed .. " added to your account.")
            output(string.format("Paid %d bounty to %s.", entry.owed, session.name))
            entry.owed = 0
            recordsDirty = true
        end
    end
end

local function afkCheck(session, time, online)
    local afk = config.afk
    local pawn = characterOf(session.controller)
    local position = pawn and location(pawn)
    local yaw = yawOf(session.controller)

    local moved = position and session.position and
        math.sqrt((position.x - session.position.x) ^ 2 + (position.y - session.position.y) ^ 2) / CM_PER_M >= AFK_MOVE
    local turned = yaw and session.yaw and math.abs(((yaw - session.yaw + 180) % 360) - 180) >= AFK_TURN
    if session.activeAt == nil or moved or turned then
        session.activeAt, session.warned = time, false
    end
    session.position, session.yaw = position or session.position, yaw or session.yaw

    if not afk.enabled then return end
    if afk.ignoreAdmins and isAdmin(session.controller) then return end
    if online < (tonumber(afk.onlyWhenPlayersAtLeast) or 0) then return end

    local limit = (tonumber(afk.minutes) or 20) * 60
    local idle = time - session.activeAt
    local warnAt = limit - (tonumber(afk.warnMinutesBefore) or 0) * 60
    if not session.warned and warnAt < limit and idle >= warnAt then
        session.warned = true
        tell(session, string.format("You will be kicked for being AFK in %d min. Move to stay.", math.ceil((limit - idle) / 60)))
    end
    if idle >= limit then
        local gameMode = findFirst(GAME_MODE_CLASSES)
        if gameMode and pcall(function() gameMode:KickPlayer(session.controller, afk.kickReason) end) then
            output("Kicked " .. session.name .. " for being AFK.")
            session.activeAt = time   -- do not retry every second while they disconnect
        end
    end
end

-- ------------------------------------------------------------------ main loop

local lastTick = nil
local lastTopAnnouncement = nil

-- Who is online and where, for the panel's Overview page. Rewritten every 15 seconds:
--   # updated <unix time>
--   steamId <tab> name <tab> x <tab> y <tab> z <tab> place <tab> vehicle <tab> admin <tab> online seconds <tab> ping
-- x/y/z are centimetres (empty when unknown); vehicle and admin are 1 or 0; ping is in ms (empty
-- when the game does not say).
local ONLINE_FILE = DIR .. "/online.tsv"
local ONLINE_EVERY = 15
local lastOnlineWrite = 0

local function cell(value)
    return (string.gsub(tostring(value or ""), "[\t\r\n]", " "))
end

-- The player's ping in ms from their PlayerState: Unreal keeps it divided by 4 in "Ping".
local function pingOf(controller)
    local value = safe(function()
        local state = controller.PlayerState
        if not isValid(state) then return nil end
        return state.Ping
    end)
    value = tonumber(value)
    if value == nil or value <= 0 then return nil end
    return math.floor(value * 4 + 0.5)
end

local function writeOnline(time)
    if time - lastOnlineWrite < ONLINE_EVERY then return end
    lastOnlineWrite = time
    local lines = { "# updated " .. string.format("%d", time) }
    for _, session in pairs(sessions) do
        -- The pawn is the character, or the vehicle while driving; read now, not kept.
        local pawn = safe(function() return session.controller:K2_GetPawn() end)
        local position = isValid(pawn) and location(pawn) or nil
        local vehicle = position ~= nil and characterOf(session.controller) == nil
        local fields = {
            session.steamId or "", session.name or "?",
            position and string.format("%.0f", position.x) or "",
            position and string.format("%.0f", position.y) or "",
            position and string.format("%.0f", position.z) or "",
            position and (describePlace(position) or "") or "",
            vehicle and "1" or "0",
            isAdmin(session.controller) and "1" or "0",
            string.format("%d", math.max(0, time - (session.since or time))),
            pingOf(session.controller) or "",
        }
        for index, value in ipairs(fields) do fields[index] = cell(value) end
        lines[#lines + 1] = table.concat(fields, "\t")
    end
    local file = io.open(ONLINE_FILE, "w")
    if not file then return end
    file:write(table.concat(lines, "\n") .. "\n")
    file:close()
end

local function tick()
    local time = os.time()
    local elapsed = lastTick and math.max(0, math.min(time - lastTick, 10)) or 0
    lastTick = time

    local seen = {}
    local controllers = playerControllers(findAll, CONTROLLER_CLASSES)
    for _, controller in ipairs(controllers) do
        local key = address(controller)
        seen[key] = true
        local session = sessions[key]
        local name = playerName(controller)
        if session == nil and name ~= nil then
            session = { controller = controller, name = name, since = time }
            sessions[key] = session
        end
        if session ~= nil then
            session.controller = controller
            session.name = name or session.name
            session.steamId = session.steamId or steamIdByName[session.name]
            if session.steamId and (config.stats.enabled or config.playtimeRewards.enabled) then
                local entry = record(session.steamId, session.name, true)
                entry.playtime = entry.playtime + elapsed
                recordsDirty = true
            end
            if session.steamId and records[session.steamId] then records[session.steamId].lastSeen = time end
        end
    end
    for key in pairs(sessions) do
        if not seen[key] then sessions[key] = nil end
    end

    local squads, squadError = pcall(squadTick, time)
    if not squads then output("Checking squads failed: " .. tostring(squadError)) end

    local wrote, writeError = pcall(writeOnline, time)
    if not wrote then output("Writing online.tsv failed: " .. tostring(writeError)) end

    local online = onlineCount()
    for _, session in pairs(sessions) do
        local ok, err = pcall(newPlayerCheck, session, time)
        if not ok then output("New player check failed: " .. tostring(err)) end
        ok, err = pcall(afkCheck, session, time, online)
        if not ok then output("AFK check failed: " .. tostring(err)) end
        ok, err = pcall(rewardCheck, session, time)
        if not ok then output("Reward check failed: " .. tostring(err)) end
        ok, err = pcall(teleportCheck, session, time)
        if not ok then output("Teleport failed: " .. tostring(err)) end
    end

    local kills = pendingKills
    pendingKills = {}
    for _, kill in ipairs(kills) do
        local ok, err = pcall(handleKill, kill, time)
        if not ok then output("Kill handling failed: " .. tostring(err)) end
    end

    local chats = pendingChats
    pendingChats = {}
    for _, chat in ipairs(chats) do
        local ok, err = pcall(handleChat, chat, time)
        if not ok then output("Chat command failed: " .. tostring(err)) end
    end

    finishVote(time)
    announceTip(time, online)
    local ok, err = pcall(calibrateGrid, time)
    if not ok then output("Working out map sectors failed: " .. tostring(err)) end
    ok, err = pcall(manhuntTick, time, online)
    if not ok then output("Manhunt failed: " .. tostring(err)) end
    ok, err = pcall(kothTick, time, elapsed, online)
    if not ok then output("King of the Hill failed: " .. tostring(err)) end
    ok, err = pcall(economy.economyTick, time, elapsed, online)
    if not ok then output("Economy update failed: " .. tostring(err)) end

    local every = (tonumber(config.stats.announceTopEveryMinutes) or 0) * 60
    if config.stats.enabled and every > 0 and online > 0 then
        lastTopAnnouncement = lastTopAnnouncement or time
        if time - lastTopAnnouncement >= every then
            lastTopAnnouncement = time
            announce(table.concat(topLines(), "  "))
        end
    end
end

local busy = false
local lastSave, lastConfigCheck = os.time(), os.time()

every(1000, function()
    local time = os.time()
    local ok, err = pcall(refreshLogs, time)
    if not ok then output("Reading SCUM's logs failed: " .. tostring(err)) end

    if time - lastConfigCheck >= CONFIG_CHECK then
        lastConfigCheck = time
        if readText(DIR .. "/config.lua") ~= configText then
            config = loadConfig()
            output("Settings reloaded.")
        end
    end

    if time - lastSave >= SAVE_EVERY then
        lastSave = time
        ok, err = pcall(saveRecords)
        if not ok then output("Saving players.tsv failed: " .. tostring(err)) end
    end

    if not busy then
        busy = true
        ExecuteInGameThread(function()
            local ticked, failure = pcall(tick)
            busy = false
            if not ticked then output("Update failed: " .. tostring(failure)) end
        end)
    end
    return false
end)

local features = {}
if config.chatCommands.enabled then features[#features + 1] = "chat commands" end
if config.killFeed.enabled then features[#features + 1] = "kill feed" end
if config.stats.enabled then features[#features + 1] = "stats" end
if config.afk.enabled then features[#features + 1] = "AFK kick after " .. config.afk.minutes .. " min" end
if config.voting.enabled then features[#features + 1] = "voting" end
if config.newPlayers.starterKit then features[#features + 1] = "starter kit" end
if config.playtimeRewards.enabled then features[#features + 1] = "playtime rewards" end
if config.killStreaks.enabled then features[#features + 1] = "kill streaks" end
if config.bounties.enabled then features[#features + 1] = "bounties" end
if config.teleports.enabled then features[#features + 1] = "teleports" end
if config.manhunt.enabled then features[#features + 1] = "manhunt" end
if config.koth.enabled then features[#features + 1] = "King of the Hill" end
for _, name in ipairs({ "shop", "sell", "pay", "lottery", "dailyTasks", "killRace", "squadBonus" }) do
    if config[name].enabled then features[#features + 1] = name end
end
output("Active: " .. (#features > 0 and table.concat(features, ", ") or "nothing enabled") .. ".")
