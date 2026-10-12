--[[
    ServerMessages - welcome messages, rotating announcements and a join/leave log for SCUM.

    - Welcome: a private message to each player a few seconds after their character spawns.
    - Announcements: a list of messages broadcast in turn, one every few minutes.
    - Join/leave log: who came and went, in players.log and the Pelican console.
    - Restart warnings: countdown announcements before the daily restart times (UTC).

    Announcements are shown the way #Announce shows them (ConZGameMode.SendHUDMessageToAll).

    Settings: config.lua in this mod's folder (re-read every 30 seconds).
]]

local TAG = "[ExclsvMessages] "
local CONTROLLER_CLASSES = { "ConZPlayerController", "BP_ConZPlayerController_C", "PlayerController" }
local PROCESSOR_PATH = "/Script/SCUM.Default__MiscStatics"
local SCAN_SECONDS = 5
local WELCOME_DELAY = 10   -- seconds after the character spawns

local DEFAULTS = {
    welcome = "",
    joinAnnouncement = "",
    intervalMinutes = 30,
    announcements = {},
    onlyWhenPlayersOnline = true,
    logJoinsAndLeaves = true,
    commandPrefix = "#",
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
local CONSOLE_LOG = DIR .. "/../PelicanConsole/console.log"

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
    -- Only write to PelicanConsole's log when that mod is running (it creates the file).
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
        local objects = safe(function() return FindAllOf(className) end)
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

local function playerName(controller)
    local name = safe(function() return text(controller.PlayerState:GetPlayerName()) end)
    if name == nil or name == "" then return nil end
    return name
end

local function fill(template, name, players)
    template = string.gsub(template, "{name}", function() return name or "" end)
    return (string.gsub(template, "{players}", function() return tostring(players) end))
end

local function adminCommand(command)
    local processor = safe(function() return StaticFindObject(PROCESSOR_PATH) end)
    local world = safe(function() return FindFirstOf("World") end)
    if not isValid(processor) or not isValid(world) then
        output("SCUM's admin command processor is not available; cannot send: " .. command)
        return false
    end
    local ok, err = pcall(function() processor:Test_ProcessAdminCommand(world, command) end)
    if not ok then output("Failed: " .. command .. " (" .. tostring(err) .. ")") end
    return ok
end

local GAME_MODE_CLASSES = { "BP_ConZGameMode_C", "ConZGameMode" }

-- The on-screen message #Announce shows. SCUM's command processor ignores commands sent
-- without an admin, so call the game mode directly and only fall back to the command.
local function announce(message)
    for _, className in ipairs(GAME_MODE_CLASSES) do
        local gameMode = safe(function() return FindFirstOf(className) end)
        if isValid(gameMode) then
            local ok = pcall(function() gameMode:SendHUDMessageToAll(message, false) end)
            if ok then return true end
        end
    end
    return adminCommand(config.commandPrefix .. "Announce " .. message)
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
    local controllers = findControllers()
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
LoopAsync(1000, function()
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
