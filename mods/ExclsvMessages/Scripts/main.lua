--[[
    ExclsvMessages - welcome messages, rotating announcements and a join/leave log for SCUM.

    - Welcome: a private message to each player a few seconds after their character spawns.
    - Announcements: a list of messages broadcast in turn, one every few minutes.
    - Join/leave log: who came and went, in players.log and the Pelican console.
    - Restart warnings: countdown announcements before the daily restart times (UTC).

    Announcements are shown the way #Announce shows them (ConZGameMode.SendHUDMessageToAll).

    Settings: config.lua in this mod's folder (re-read every 30 seconds).
]]

local TAG = "[ExclsvMessages] "
local CONTROLLER_CLASSES = { "ConZPlayerController", "BP_ConZPlayerController_C", "PlayerController" }
local SCAN_SECONDS = 5
local WELCOME_DELAY = 10   -- seconds after the character spawns

local DEFAULTS = {
    welcome = "",
    joinAnnouncement = "",
    intervalMinutes = 30,
    announcements = {},
    onlyWhenPlayersOnline = true,
    logJoinsAndLeaves = true,
    restartTimes = {},
    restartWarnings = { 30, 15, 5, 1 },
    restartMessage = "Server restart in {minutes} minute(s).",
}
local CONFIG_CHECK = 30

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
    print(TAG .. "Could not work out the mod folder; ExclsvMessages is disabled.\n")
    return
end

local PLAYERS_LOG = DIR .. "/players.log"
local CONSOLE_LOG = DIR .. "/../ExclsvConsole/console.log"

local function append(path, line)
    local file = io.open(path, "a")
    if file then
        file:write(line .. "\n")
        file:close()
    end
end

local function output(message, toPlayersLog)
    local line = os.date("!%H:%M:%S") .. " " .. TAG .. message
    print(line .. "\n")
    if toPlayersLog then
        append(PLAYERS_LOG, os.date("!%Y-%m-%d ") .. line)
    end
    -- Only write to ExclsvConsole's log when that mod is running (it creates the file).
    local existing = io.open(CONSOLE_LOG, "r")
    if existing then
        existing:close()
        append(CONSOLE_LOG, line)
    end
end

local configText = nil
local function loadConfig()
    local raw = io.open(DIR .. "/config.lua", "rb")
    configText = raw and raw:read("a") or nil
    if raw then raw:close() end
    local config = {}
    for key, value in pairs(DEFAULTS) do config[key] = value end

    local ok, loaded = pcall(dofile, DIR .. "/config.lua")
    if ok and type(loaded) == "table" then
        for key, value in pairs(loaded) do config[key] = value end
    elseif not ok then
        output("config.lua could not be read, using defaults: " .. tostring(loaded))
    end

    if type(config.intervalMinutes) ~= "number" or config.intervalMinutes < 1 then
        config.intervalMinutes = DEFAULTS.intervalMinutes
    end
    return config
end

local config = loadConfig()

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

local function text(value)
    if type(value) == "string" then return value end
    return safe(function() return value:ToString() end)
end

local function address(object)
    return safe(function() return object:GetAddress() end) or object
end

local function findControllers()
    local found, seen = {}, {}
    for _, className in ipairs(CONTROLLER_CLASSES) do
        local objects = liveObjects(className)
        for _, object in ipairs(objects or {}) do
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

local function playerName(controller)
    local name = safe(function() return text(controller.PlayerState:GetPlayerName()) end)
    if name == nil or name == "" then return nil end
    return name
end

local function fill(template, name, players)
    template = string.gsub(template, "{name}", function() return name or "" end)
    return (string.gsub(template, "{players}", function() return tostring(players) end))
end

local GAME_MODE_CLASSES = { "BP_ConZGameMode_C", "ConZGameMode" }

-- The on-screen message #Announce shows, sent through the game mode directly (SCUM ignores
-- admin commands sent without an admin in game, so there is no command fallback).
local function announce(message)
    for _, className in ipairs(GAME_MODE_CLASSES) do
        local gameMode = safe(function() return FindFirstOf(className) end)
        if isValid(gameMode) then
            local ok = pcall(function() gameMode:SendHUDMessageToAll(message, false) end)
            if ok then return true end
        end
    end
    output("Could not show the announcement (the game world is not ready): " .. message)
    return false
end

local function sendPrivate(pawn, message)
    return pcall(function() pawn:SendMessageToClient(message, nil) end)
end

local function isCharacter(pawn)
    local class = safe(function() return pawn:GetClass():GetFName():ToString() end) or ""
    return string.find(class, "Prisoner", 1, true) ~= nil
end

-- ------------------------------------------------------------------ players

local online = {}            -- by controller address: { name, spawnedAt, welcomed }
local nextAnnouncement = nil
local announcementIndex = 0

local function scan()
    local now = os.time()
    local controllers = playerControllers(findControllers)
    local present = {}

    for _, controller in ipairs(controllers) do
        local key = address(controller)
        present[key] = true
        local player = online[key]

        if player == nil then
            -- The name arrives a moment after the connection; wait for it.
            local name = playerName(controller)
            if name ~= nil then
                player = { name = name, welcomed = false }
                online[key] = player
                if config.logJoinsAndLeaves then output(name .. " joined.", true) end
                if config.joinAnnouncement ~= "" then
                    announce(fill(config.joinAnnouncement, name, #controllers))
                end
            end
        end

        if player ~= nil and not player.welcomed and config.welcome ~= "" then
            local pawn = safe(function() return controller:K2_GetPawn() end)
            if isValid(pawn) and isCharacter(pawn) then
                player.spawnedAt = player.spawnedAt or now
                if now - player.spawnedAt >= WELCOME_DELAY then
                    player.welcomed = true
                    if not sendPrivate(pawn, fill(config.welcome, player.name, #controllers)) then
                        output("Could not send the welcome message to " .. player.name .. ".")
                    end
                end
            end
        end
    end

    for key, player in pairs(online) do
        if not present[key] then
            online[key] = nil
            if config.logJoinsAndLeaves then output(player.name .. " left.", true) end
        end
    end

    local messages = config.announcements or {}
    if #messages > 0 then
        nextAnnouncement = nextAnnouncement or (now + config.intervalMinutes * 60)
        if now >= nextAnnouncement then
            nextAnnouncement = now + config.intervalMinutes * 60
            if #controllers > 0 or not config.onlyWhenPlayersOnline then
                announcementIndex = announcementIndex % #messages + 1
                announce(fill(messages[announcementIndex], nil, #controllers))
            end
        end
    end
end

-- ------------------------------------------------------------------ restart warnings

local announcedWarnings = {}

-- Seconds from now until the next "HH:MM" (UTC), or nil when the time is not valid.
local function secondsUntil(clockTime, now)
    local hour, minute = string.match(tostring(clockTime), "^%s*(%d%d?):(%d%d)%s*$")
    hour, minute = tonumber(hour), tonumber(minute)
    if hour == nil or hour > 23 or minute > 59 then return nil end
    local t = os.date("!*t", now)
    local delta = hour * 3600 + minute * 60 - (t.hour * 3600 + t.min * 60 + t.sec)
    if delta <= 0 then delta = delta + 86400 end
    return delta
end

local function restartWarnings(now)
    for _, clockTime in ipairs(config.restartTimes or {}) do
        local delta = secondsUntil(clockTime, now)
        if delta then
            local restartAt = now + delta
            for _, minutes in ipairs(config.restartWarnings or {}) do
                minutes = tonumber(minutes)
                local key = restartAt .. ":" .. tostring(minutes)
                if minutes and delta <= minutes * 60 and delta > minutes * 60 - 60 and not announcedWarnings[key] then
                    announcedWarnings[key] = true
                    announce(fill(string.gsub(config.restartMessage, "{minutes}", tostring(minutes)), nil, 0))
                    output("Restart warning: " .. minutes .. " min before " .. clockTime .. " UTC.")
                end
            end
        end
    end
end

local busy = false
local lastScan = nil
local lastConfigCheck = os.time()
every(1000, function()
    local now = os.time()
    if now - lastConfigCheck >= CONFIG_CHECK then
        lastConfigCheck = now
        local raw = io.open(DIR .. "/config.lua", "rb")
        local text = raw and raw:read("a") or nil
        if raw then raw:close() end
        if text ~= configText then
            config = loadConfig()
            output("Settings reloaded.")
        end
    end
    if not busy then
        ExecuteInGameThread(function()
            local ok, err = pcall(restartWarnings, now)
            if not ok then output("Restart warning failed: " .. tostring(err)) end
        end)
    end
    if not busy and (lastScan == nil or now - lastScan >= SCAN_SECONDS) then
        busy, lastScan = true, now
        ExecuteInGameThread(function()
            local ok, err = pcall(scan)
            busy = false
            if not ok then output("Scan failed: " .. tostring(err)) end
        end)
    end
    return false
end)

output(string.format("Active. Welcome %s, %d announcement(s) every %d min, join/leave log %s, %d restart time(s).",
    config.welcome ~= "" and "on" or "off", #(config.announcements or {}), config.intervalMinutes,
    config.logJoinsAndLeaves and "on" or "off", #(config.restartTimes or {})))
