--[[
    PlayerTools - quality-of-life features for SCUM players.

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
      - Teleports:     !tp <place> for a price, after standing still for a few seconds
      - Info:          !info with uptime, players online and the next restart
      - Reports:       !report <name> <reason>, logged to reports.log and sent to online admins

    Chat and kills come from SCUM's own logs (SCUM/Saved/SaveFiles/Logs/chat_*.log and
    kill_*.log). Messages to one player use Prisoner.SendMessageToClient, announcements use
    ConZGameMode.SendHUDMessageToAll. Votes, starter kits, rewards, bounty payouts and
    teleports run SCUM admin commands through an online admin's chat command channel, so they
    need an admin (AdminUsers.ini) online; until then they wait (votes and teleports say so).

    Settings: config.lua in this mod's folder (re-read every 30 seconds).
    Data:     players.tsv in this mod's folder (stats, rewards, bounties, starter kits),
              reports.log (player reports).
]]

local TAG = "[PlayerTools] "
local CONTROLLER_CLASSES = { "BP_ConZPlayerController_C", "ConZPlayerController" }
local GAME_MODE_CLASSES = { "BP_ConZGameMode_C", "ConZGameMode" }
local CM_PER_M = 100
local MAX_READ = 1024 * 1024       -- bytes read from a log per second
local CONFIG_CHECK = 30            -- seconds between looks at config.lua
local SAVE_EVERY = 60              -- seconds between writes of players.tsv
local LOG_REFRESH = 60             -- seconds between looks for a newer chat or kill log
local SPAWN_DELAY = 10             -- seconds after spawning before new-player messages and kits
local AFK_MOVE = 1                 -- metres
local AFK_TURN = 2                 -- degrees

local DEFAULTS = {
    chatCommands = { enabled = true, prefix = "!", rules = {}, discord = "" },
    killFeed = { enabled = true, message = "{killer} killed {victim} with {weapon} ({distance} m)", minDistance = 0 },
    stats = { enabled = true, topCount = 3, announceTopEveryMinutes = 0 },
    afk = { enabled = false, minutes = 20, warnMinutesBefore = 2, onlyWhenPlayersAtLeast = 0, ignoreAdmins = true, kickReason = "Kicked for being AFK." },
    voting = { enabled = true, durationSeconds = 60, cooldownMinutes = 15, percentNeeded = 50, minVotes = 2, options = {} },
    newPlayers = { messages = {}, starterKit = false, starterKitCommands = {}, starterKitMessage = "" },
    welcomeBack = { enabled = true, message = "Welcome back {name}! {hours} played, {kills} kills, {deaths} deaths." },
    playtimeRewards = {
        enabled = true, everyMinutes = 60,
        commands = { "ChangeCurrencyBalance Normal 100 {steamId}" },
        message = "+100 cash for an hour on the server. Thanks for playing!",
        dailyCommands = { "ChangeCurrencyBalance Normal 200 {steamId}" },
        dailyMessage = "Daily login bonus: +200 cash.",
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
    },
    teleports = {
        enabled = true, cooldownMinutes = 30, standStillSeconds = 10,
        command = "Teleport {x} {y} {z} {steamId}",
        chargeCommand = "ChangeCurrencyBalance Normal -{price} {steamId}",
        locations = {},
    },
    info = { enabled = true, lines = {} },
    reports = { enabled = true, cooldownSeconds = 60 },
}

local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function modDir()
    local source = string.gsub(debug.getinfo(1, "S").source or "", "^@", "")
    return string.match(source, "^(.*)[/\\]Scripts[/\\]main%.lua$")
end

local DIR = modDir()
if DIR == nil then
    print(TAG .. "Could not work out the mod folder; PlayerTools is disabled.\n")
    return
end

-- <SCUM>/Binaries/Win64/ue4ss/Mods/PlayerTools -> <SCUM>
local SCUM_DIR = DIR .. "/../../../../.."
local SERVER_LOG = SCUM_DIR .. "/Saved/Logs/SCUM.log"
local GAME_LOG_DIR = SCUM_DIR .. "/Saved/SaveFiles/Logs"
local PLAYERS_FILE = DIR .. "/players.tsv"
local REPORTS_FILE = DIR .. "/reports.log"
local RESTARTS_CONFIG = DIR .. "/../ServerMessages/config.lua"
local STARTED_AT = os.time()
local LOG_FILES = { DIR .. "/playertools.log", DIR .. "/../PelicanConsole/console.log" }

-- ------------------------------------------------------------------ output and config

local function output(message)
    local line = os.date("!%H:%M:%S") .. " " .. TAG .. message
    print(line .. "\n")
    for index, path in ipairs(LOG_FILES) do
        -- Only write to PelicanConsole's log when that mod is running (it creates the file).
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
    local file = io.open(tail.path, "rb")
    if not file then return {} end
    local size = file:seek("end") or 0
    if tail.offset == nil or size < tail.offset then
        tail.offset = (tail.offset == nil and tail.fromEnd) and size or 0
        tail.partial = ""
    end
    local lines = {}
    if size > tail.offset then
        file:seek("set", tail.offset)
        local data = file:read(math.min(size - tail.offset, MAX_READ)) or ""
        tail.offset = tail.offset + #data
        local text = tail.partial .. ascii(data)
        local last = 1
        for line, finish in string.gmatch(text, "([^\n]*)\n()") do
            lines[#lines + 1] = (string.gsub(line, "\r$", ""))
            last = finish
        end
        tail.partial = string.sub(text, last)
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
--   bestStreak, bounty (on this player), owed (bounty cash waiting to be paid to this player) }
-- Not saved: streak (current kill streak), new (first seen joining this session).
local records = {}
local recordsDirty = false
local FIELDS = { "name", "kills", "deaths", "playtime", "longest", "kit", "first", "rewarded", "daily", "bestStreak", "bounty", "owed" }

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
                owed = tonumber(parts[13]) or 0, streak = 0,
            }
        end
    end
end

local function saveRecords()
    if not recordsDirty then return end
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
            first = os.time(), rewarded = 0, daily = "", bestStreak = 0, bounty = 0, owed = 0, streak = 0,
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
        }
    end

    local victimName, victimId, killerName, killerId = string.match(line, "Died: (.-) %((%d+)%), Killer: (.-) %((%d+)%)")
    if killerId then
        return {
            killerId = killerId, killerName = killerName, victimId = victimId, victimName = victimName,
            weapon = string.match(line, "Weapon: (.-)%s+[SC]%[") or string.match(line, "Weapon: (%S+)"),
            distance = number(string.match(line, "Distance: ([%d%.]+) m")),
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

local function handleServerLogLine(line)
    -- LogSCUM: '1.2.3.4 76561198000000000:Name(2)' logged in at: X=...
    local id, name = string.match(line, "'%S+ (%d+):(.*)%(%d+%)' logged in at:")
    if id then steamIdByName[name] = id end
end

local function handleKillLine(line)
    local kill = parseKill(line)
    if kill == nil or kill.killerId == nil or kill.killerId == kill.victimId then return end
    local key = kill.killerId .. ">" .. tostring(kill.victimId) .. "@" .. (string.match(line, "^([%d%.%-]+)") or line)
    if recentKillKeys[key] then return end
    recentKillKeys[key] = true
    pendingKills[#pendingKills + 1] = kill
end

local function handleChatLine(line)
    local chat = parseChat(line)
    if chat == nil then return end
    if chat.name then steamIdByName[chat.name] = chat.steamId end
    local prefix = config.chatCommands.prefix or "!"
    if string.sub(chat.text, 1, #prefix) == prefix then
        chat.text = string.sub(chat.text, #prefix + 1)
        pendingChats[#pendingChats + 1] = chat
    end
end

local LOG_HANDLERS = { kill_ = handleKillLine, chat_ = handleChatLine }
local lastLogRefresh = nil

local function refreshLogs(time)
    for _, line in ipairs(readTail(serverLog)) do handleServerLogLine(line) end

    if lastLogRefresh == nil or time - lastLogRefresh >= LOG_REFRESH then
        local firstRefresh = lastLogRefresh == nil
        lastLogRefresh = time
        for prefix in pairs(LOG_HANDLERS) do
            local path = newestGameLog(prefix)
            if path and (gameLogs[prefix] == nil or gameLogs[prefix].path ~= path) then
                -- Skip what was already in the file when the mod started; read new files in full.
                gameLogs[prefix] = newTail(path, firstRefresh)
                if prefix == "kill_" then recentKillKeys = {} end
            end
        end
    end

    for prefix, tail in pairs(gameLogs) do
        for _, line in ipairs(readTail(tail)) do LOG_HANDLERS[prefix](line) end
    end
end

-- ------------------------------------------------------------------ game access

local function isValid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end

local function address(object)
    return safe(function() return object:GetAddress() end) or object
end

local function findAll(classNames)
    local found, seen = {}, {}
    for _, className in ipairs(classNames) do
        for _, object in ipairs(safe(function() return FindAllOf(className) end) or {}) do
            local key = address(object)
            if not seen[key] and isValid(object) then
                seen[key] = true
                found[#found + 1] = object
            end
        end
    end
    return found
end

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

local function sessionForChat(chat)
    local session = sessionById(chat.steamId)
    if session then return session end
    for _, candidate in pairs(sessions) do
        if chat.name and candidate.name == chat.name then return candidate end
    end
    return nil
end

local function tell(session, lines)
    if type(lines) == "string" then lines = { lines } end
    local pawn = characterOf(session.controller)
    if pawn == nil then return false end
    return pcall(function() pawn:SendMessageToClient(table.concat(lines, "\n"), nil) end)
end

local function onlineCount()
    local count = 0
    for _ in pairs(sessions) do count = count + 1 end
    return count
end

-- Runs an admin command through an online admin's chat command channel, as if they typed it.
local function runAdminCommand(command)
    local admins = {}
    for key, session in pairs(sessions) do
        if isAdmin(session.controller) then admins[key] = session end
    end
    if next(admins) == nil then return false, "no admin is online" end

    for _, channel in ipairs(findAll({ "PlayerRpcChannel" })) do
        local owner = safe(function() return channel:GetOwner() end)
        local admin = owner and admins[address(owner)]
        if admin == nil and owner ~= nil then
            local ownerOwner = safe(function() return owner:GetOwner() end)
            admin = ownerOwner and admins[address(ownerOwner)]
        end
        if admin ~= nil then
            local ok, err = pcall(function() channel:Chat_Server_ProcessAdminCommand("#" .. string.gsub(command, "^#+", "")) end)
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

local recentVictims = {}   -- "killer>victim" -> time, to stop streak and bounty farming

local function handleKill(kill, time)
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

    -- Killing the same player again soon after does not count towards streaks or bounties.
    local key = kill.killerId .. ">" .. tostring(kill.victimId)
    local window = (tonumber(streaks.ignoreSameVictimMinutes) or 0) * 60
    local farmed = recentVictims[key] ~= nil and time - recentVictims[key] < window
    recentVictims[key] = time

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

-- ------------------------------------------------------------------ info, reports, bounties, teleports

local lastReport = {}   -- SteamID -> time

local function duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h, m = seconds // 3600, (seconds % 3600) // 60
    if h > 0 then return string.format("%d h %d min", h, m) end
    return string.format("%d min", m)
end

-- Next restart from ServerMessages' restartTimes ("HH:MM" UTC), or nil.
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
    local price = tonumber(place.price) or 0
    values = { x = place.x, y = place.y, z = place.z, price = price, steamId = session.steamId, name = session.name }
    if price > 0 then
        local ok, detail = runAdminCommand(fill(config.teleports.chargeCommand, values))
        if not ok then return tell(session, "Teleports are not available right now (" .. detail .. ").") end
    end
    local ok, detail = runAdminCommand(fill(config.teleports.command, values))
    if not ok then return tell(session, "Teleports are not available right now (" .. detail .. ").") end
    local entry = record(session.steamId, session.name, true)
    entry.lastTeleport = time
    output(string.format("Teleported %s to %s%s.", session.name, place.name, price > 0 and (" for " .. price) or ""))
    tell(session, "Teleported to " .. place.name .. (price > 0 and (" (" .. price .. " paid)") or "") .. ".")
end

-- ------------------------------------------------------------------ chat commands

local function handleChat(chat, time)
    if not config.chatCommands.enabled then return end
    local session = sessionForChat(chat)
    if session == nil then return end
    if session.steamId == nil then session.steamId = chat.steamId end

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
        tell(session, entry and statsLines(entry) or "No stats yet.")
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
    elseif word == "where" and isAdmin(session.controller) then
        local pawn = characterOf(session.controller)
        local position = pawn and location(pawn)
        tell(session, position and string.format("You are at x=%.0f y=%.0f z=%.0f", position.x, position.y, position.z) or "Your position is not known.")
    end
end

-- ------------------------------------------------------------------ new players and AFK

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

    if config.newPlayers.starterKit and entry.kit == "pending" then
        local commands = config.newPlayers.starterKitCommands or {}
        if #commands == 0 then
            session.newChecked = true
            return
        end
        local position = location(pawn)
        local values = {
            name = session.name, steamId = session.steamId,
            location = position and string.format("X=%.0f Y=%.0f Z=%.0f", position.x, position.y, position.z + 50) or "",
        }
        local ok, detail = runAdminCommand(fill(commands[1], values))
        if not ok then
            -- Try again later (for example when an admin comes online).
            if not session.kitWaitReported then
                session.kitWaitReported = true
                output("Starter kit for " .. session.name .. " is waiting: " .. detail .. ".")
            end
            return
        end
        for index = 2, #commands do runAdminCommand(fill(commands[index], values)) end
        entry.kit = "given"
        recordsDirty = true
        if (config.newPlayers.starterKitMessage or "") ~= "" then
            tell(session, fill(config.newPlayers.starterKitMessage, values))
        end
        output("Gave a starter kit to " .. session.name .. " (run as " .. detail .. ").")
    end
    session.newChecked = true
end

local function today(time)
    return os.date("!%Y-%m-%d", time)
end

local function runAll(commands, values)
    for _, command in ipairs(commands or {}) do
        local ok, detail = runAdminCommand(fill(command, values))
        if not ok then return false, detail end
    end
    return true
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
        if #(rewards.dailyCommands or {}) > 0 and entry.daily ~= today(time) and runAll(rewards.dailyCommands, values) then
            entry.daily = today(time)
            recordsDirty = true
            if (rewards.dailyMessage or "") ~= "" then tell(session, fill(rewards.dailyMessage, values)) end
        end
        local every = (tonumber(rewards.everyMinutes) or 0) * 60
        if every > 0 and #(rewards.commands or {}) > 0 and entry.playtime - (entry.rewarded or 0) >= every
            and runAll(rewards.commands, values) then
            entry.rewarded = (entry.rewarded or 0) + every
            recordsDirty = true
            if (rewards.message or "") ~= "" then tell(session, fill(rewards.message, values)) end
        end
    end

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

local function tick()
    local time = os.time()
    local elapsed = lastTick and math.max(0, math.min(time - lastTick, 10)) or 0
    lastTick = time

    local seen = {}
    local controllers = findAll(CONTROLLER_CLASSES)
    for _, controller in ipairs(controllers) do
        local key = address(controller)
        seen[key] = true
        local session = sessions[key]
        local name = playerName(controller)
        if session == nil and name ~= nil then
            session = { controller = controller, name = name }
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
        end
    end
    for key in pairs(sessions) do
        if not seen[key] then sessions[key] = nil end
    end

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

LoopAsync(1000, function()
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
output("Active: " .. (#features > 0 and table.concat(features, ", ") or "nothing enabled") .. ".")
