--[[
    ScumAntiCheat - server-side checks for SCUM.

    Once a second it reads every player's position and movement on the server and flags:
      - speed:      faster than anyone can move on foot or in a vehicle
      - teleport:   jumping hundreds of metres between two checks
      - flying:     staying in flying movement mode (fly hack)
      - hovering:   staying in the air without falling (hover / airwalk)
      - map bounds: outside the island or deep below it (noclip, under-map)
    and, using SCUM's own files:
      - unauthorized admin: admin rights without being in AdminUsers.ini
      - names:      names that impersonate staff
      - watchlist:  announces watched SteamIDs when they join
      - game logs:  shows SCUM's own violation and admin-command logs in the console
    and, for aimbots, from SCUM's kill log and the players' aim:
      - long-range kills beyond what the weapon can do (and melee kills from afar)
      - kills with god mode, or from a position the server disagrees with
      - too many kills in a short time
      - aim snaps: the view jumping onto a target right before a kill, kill after kill
    Aimbot checks only report suspects; nobody is punished for them unless
    strikeOnKillFlags is turned on.

    BattlEye covers the client (aimbots, ESP, injected code). This catches what still shows up
    on the server. Admins in AdminUsers.ini, players the game itself is teleporting, falling or
    parachuting players and freshly (re)spawned characters are not checked.

    Settings: config.lua in this mod's folder (re-read every 30 seconds; the aim-snap check
              is only switched on or off by a restart).
    Reports:  anticheat.log in this mod's folder, UE4SS.log, and the Pelican console when the
              PelicanConsole mod is installed.
]]

local TAG = "[ScumAntiCheat] "
local CONTROLLER_CLASSES = { "ConZPlayerController", "BP_ConZPlayerController_C", "PlayerController" }
local GAME_MODE_CLASSES = { "BP_ConZGameMode_C", "ConZGameMode" }
local CM_PER_M = 100
local FALLING_SPEED = 5       -- m/s downwards; above this the horizontal speed check is skipped
local HOVER_SPEED = 1         -- m/s; slower vertical movement than this while falling is hovering
local SETTLE_SECONDS = 5      -- seconds after getting into or out of a vehicle before movement counts
local MAX_SAMPLE_GAP = 5      -- seconds; older samples are discarded instead of compared
local REPEAT_COOLDOWN = 5     -- seconds between strikes for the same continuous violation
local FILE_REFRESH = 60       -- seconds between re-reading AdminUsers.ini and looking for new game logs
local MAX_READ = 1024 * 1024  -- bytes read from a log per second

local MOVE_FALLING = 3
local MOVE_FLYING = 5

local DEFAULTS = {
    action = "log",
    banAfterKicks = 3,
    strikesToAct = 3,
    strikeWindowSeconds = 60,
    checks = {
        speed = true, teleport = true, flying = true, hovering = true, mapBounds = true,
        unauthorizedAdmin = true, names = true, watchlist = true, gameLogs = true,
        killLog = true, aimSnap = true,
    },
    maxFootSpeed = 21,
    maxVehicleSpeed = 120,
    teleportDistance = 300,
    flyingSeconds = 10,
    hoverSeconds = 8,
    mapBounds = { minX = -9548, maxX = 6692, minY = -9548, maxY = 6692, minZ = -300 },
    ignoreAdmins = true,
    ignoreNames = {},
    ignoreSteamIds = {},
    blockedNames = { "admin", "moderator", "owner", "[staff]" },
    watchlist = {},
    strikeOnGameViolations = false,
    maxKillDistance = 800,
    maxMeleeDistance = 8,
    weaponMaxDistance = {
        { "bow", 150 }, { "1911", 150 }, { "deagle", 150 }, { "m9", 150 }, { "revolver", 150 },
        { "pistol", 150 }, { "tec01", 150 }, { "glock", 150 },
    },
    killRateKills = 8,
    killRateMinutes = 5,
    maxLocationMismatch = 50,
    aimSnapDegrees = 150,
    aimSnapPattern = 3,
    strikeOnKillFlags = false,
    kickReason = "Kicked by anti-cheat.",
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
    print(TAG .. "Could not work out the mod folder; anti-cheat is disabled.\n")
    return
end

-- <SCUM>/Binaries/Win64/ue4ss/Mods/ScumAntiCheat -> <SCUM>
local SCUM_DIR = DIR .. "/../../../../.."
local CONFIG_DIR = SCUM_DIR .. "/Saved/Config/WindowsServer"
local SERVER_LOG = SCUM_DIR .. "/Saved/Logs/SCUM.log"
local GAME_LOG_DIR = SCUM_DIR .. "/Saved/SaveFiles/Logs"
local OFFENSES_FILE = DIR .. "/offenses.txt"
-- Our other mods (PlayerTools !tp, PelicanConsole TeleportPlayer) write "<os.time> <name>" here
-- when they teleport a player, so the teleport check does not flag it.
local ALLOWED_TELEPORTS_FILE = DIR .. "/allowed_teleports.txt"
local ALLOWED_TELEPORT_SECONDS = 15
local LOG_FILES = { DIR .. "/anticheat.log", DIR .. "/../PelicanConsole/console.log" }

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

local function set(list, lower)
    local result = {}
    for _, value in ipairs(list or {}) do
        value = tostring(value)
        result[lower and string.lower(value) or value] = true
    end
    return result
end

local configText = nil
local function readConfigText()
    local file = io.open(DIR .. "/config.lua", "rb")
    if not file then return nil end
    local text = file:read("a")
    file:close()
    return text
end

local function loadConfig()
    configText = readConfigText()
    local config = {}
    for key, value in pairs(DEFAULTS) do config[key] = value end

    local ok, loaded = pcall(dofile, DIR .. "/config.lua")
    if ok and type(loaded) == "table" then
        for key, value in pairs(loaded) do config[key] = value end
    elseif not ok then
        output("config.lua could not be read, using defaults: " .. tostring(loaded))
    end

    -- Nested tables: fill in whatever the file leaves out.
    for _, key in ipairs({ "checks", "mapBounds" }) do
        local merged = {}
        for name, value in pairs(DEFAULTS[key]) do merged[name] = value end
        if type(config[key]) == "table" then
            for name, value in pairs(config[key]) do merged[name] = value end
        end
        config[key] = merged
    end

    if config.action ~= "log" and config.action ~= "kick" and config.action ~= "ban" then
        output("Unknown action '" .. tostring(config.action) .. "', using \"log\".")
        config.action = "log"
    end

    config.ignored = set(config.ignoreNames, true)
    config.ignoredIds = set(config.ignoreSteamIds)
    config.watched = set(config.watchlist)
    config.blocked = {}
    for _, pattern in ipairs(config.blockedNames or {}) do
        config.blocked[#config.blocked + 1] = string.lower(tostring(pattern))
    end
    return config
end

local config = loadConfig()

-- ------------------------------------------------------------------ files

-- SCUM writes some files as UTF-16. Everything this mod looks for is ASCII, so drop the zero bytes.
local function ascii(data)
    data = string.gsub(data, "^\255\254", "")
    return (string.gsub(data, "%z", ""))
end

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local data = file:read("a")
    file:close()
    return ascii(data or "")
end

local function steamIdsIn(path)
    local text = readFile(path)
    if text == nil then return nil end
    local ids = {}
    for line in string.gmatch(text, "[^\r\n]+") do
        local id = string.match(line, "^%s*(%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d)")
        if id then ids[id] = true end
    end
    return ids
end

-- Follows a growing log file, returning complete new lines.
local function newTail(path, fromEnd)
    return { path = path, offset = nil, fromEnd = fromEnd, partial = "" }
end

local function readTail(tail)
    local file = io.open(tail.path, "rb")
    if not file then return {} end
    local size = file:seek("end") or 0
    if tail.offset == nil or size < tail.offset then
        -- First read, or the file was recreated.
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

-- Newest SCUM game log with this prefix, e.g. violations_20261011122958.log.
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

-- ------------------------------------------------------------------ server state from files

local steamIdByName = {}      -- from SCUM.log login lines
local adminIds = nil          -- AdminUsers.ini; nil when it can't be read
local offenses = {}           -- SteamID -> times kicked by this mod
local pendingViolations = {}  -- SteamID -> reason, from SCUM's violation log
local serverLog = newTail(SERVER_LOG, false)
local gameLogs = {}           -- prefix -> tail
local lastFileRefresh = nil

local function loadOffenses()
    local text = readFile(OFFENSES_FILE) or ""
    for id, count in string.gmatch(text, "(%d+)%s+(%d+)") do
        offenses[id] = tonumber(count)
    end
end

local function saveOffenses()
    local file = io.open(OFFENSES_FILE, "w")
    if not file then return end
    for id, count in pairs(offenses) do
        file:write(id .. " " .. count .. "\n")
    end
    file:close()
end

loadOffenses()

local function handleServerLogLine(line)
    -- LogSCUM: '1.2.3.4 76561198000000000:Name(2)' logged in at: X=...
    local id, name = string.match(line, "'%S+ (%d+):(.*)%(%d+%)' logged in at:")
    if id then
        steamIdByName[name] = id
    end
end

-- ------------------------------------------------------------------ kill log

local pendingKills = {}   -- parsed on the file thread, analysed on the game thread
local recentKillKeys = {}

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
        local killerServer = vectorIn(killer, "ServerLocation")
        return {
            killerId = string.match(killer, '"UserId":"(%d+)"'),
            killerName = string.match(killer, '"ProfileName":"(.-)"'),
            victimId = string.match(victim, '"UserId":"(%d+)"'),
            victimName = string.match(victim, '"ProfileName":"(.-)"'),
            weapon = string.match(line, '"Weapon":"(.-)"') or "?",
            distance = distanceBetween(killerServer, vectorIn(victim, "ServerLocation")),
            mismatch = distanceBetween(killerServer, vectorIn(killer, "ClientLocation")),
            immortal = string.find(killer, '"HasImmortality":true', 1, true) ~= nil,
        }
    end

    local victimName, victimId, killerName, killerId = string.match(line, "Died: (.-) %((%d+)%), Killer: (.-) %((%d+)%)")
    if killerId then
        return {
            killerId = killerId, killerName = killerName, victimId = victimId, victimName = victimName,
            weapon = string.match(line, "Weapon: (.-)%s+[SC]%[") or string.match(line, "Weapon: (%S+)") or "?",
            distance = number(string.match(line, "Distance: ([%d%.]+) m")),
        }
    end
    return nil
end

local function handleKillLine(line)
    local kill = parseKill(line)
    if kill == nil or kill.killerId == nil or kill.killerId == kill.victimId then return end
    -- The same kill appears in both formats; count it once.
    local key = kill.killerId .. ">" .. tostring(kill.victimId) .. "@" .. (string.match(line, "^([%d%.%-]+)") or line)
    if recentKillKeys[key] then return end
    recentKillKeys[key] = true
    pendingKills[#pendingKills + 1] = kill
end

local function handleGameLogLine(kind, line)
    if string.match(line, "^%s*$") then return end
    if kind == "kill" then
        handleKillLine(line)
        return
    end
    -- Only lines about a player; skip file headers such as "Game version: ...".
    local id = string.match(line, "(%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d)")
    if id == nil then return end
    output("SCUM " .. kind .. ": " .. line)
    if kind == "violation" and config.strikeOnGameViolations then
        pendingViolations[id] = line
    end
end

local GAME_LOG_KINDS = { violations_ = "violation", admin_ = "admin command", kill_ = "kill" }

local function gameLogEnabled(prefix)
    if prefix == "kill_" then return config.checks.killLog end
    return config.checks.gameLogs
end

local allowedTeleports = {}   -- name -> os.time of a teleport made by our own mods

local function readAllowedTeleports()
    local text = readFile(ALLOWED_TELEPORTS_FILE)
    if text == nil or text == "" then return end
    for time, name in string.gmatch(text, "(%d+) ([^\r\n]+)") do
        allowedTeleports[name] = tonumber(time)
    end
    local file = io.open(ALLOWED_TELEPORTS_FILE, "w")
    if file then file:close() end
end

local function refreshFiles(now)
    readAllowedTeleports()
    for _, line in ipairs(readTail(serverLog)) do
        handleServerLogLine(line)
    end

    local refresh = lastFileRefresh == nil or now - lastFileRefresh >= FILE_REFRESH
    if refresh then
        local firstRefresh = lastFileRefresh == nil
        lastFileRefresh = now
        adminIds = steamIdsIn(CONFIG_DIR .. "/AdminUsers.ini")

        for prefix in pairs(GAME_LOG_KINDS) do
            if gameLogEnabled(prefix) then
                local path = newestGameLog(prefix)
                if path and (gameLogs[prefix] == nil or gameLogs[prefix].path ~= path) then
                    -- Skip what was already in the file when the mod started; read new files in full.
                    gameLogs[prefix] = newTail(path, firstRefresh)
                    recentKillKeys = {}
                end
            end
        end
    end

    for prefix, tail in pairs(gameLogs) do
        for _, line in ipairs(readTail(tail)) do
            handleGameLogLine(GAME_LOG_KINDS[prefix], line)
        end
    end
end

local function ban(steamId)
    local path = CONFIG_DIR .. "/BannedUsers.ini"
    local existing = steamIdsIn(path) or {}
    if existing[steamId] then return true end
    local text = readFile(path) or ""
    local file = io.open(path, "a")
    if not file then return false end
    if text ~= "" and not string.match(text, "\n$") then file:write("\n") end
    file:write(steamId .. "\n")
    file:close()
    return true
end

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

local function findAll(classNames)
    local found, seen = {}, {}
    for _, className in ipairs(classNames) do
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

local function findFirst(classNames)
    for _, className in ipairs(classNames) do
        local object = safe(function() return FindFirstOf(className) end)
        if isValid(object) then return object end
    end
    return nil
end

local function playerName(controller)
    local name = safe(function() return text(controller.PlayerState:GetPlayerName()) end)
    if name == nil or name == "" then return nil end
    return name
end

local function isTrue(object, method)
    return safe(function() return object[method](object) end) == true
end

local function className(object)
    return safe(function() return object:GetClass():GetFName():ToString() end) or ""
end

local function isCharacter(pawn)
    return string.find(className(pawn), "Prisoner", 1, true) ~= nil
end

local function inVehicle(pawn)
    -- Driving possesses the vehicle; passengers are attached to it.
    if not isCharacter(pawn) then return true end
    return isValid(safe(function() return pawn:GetAttachParentActor() end))
end

local function movementMode(pawn)
    local movement = safe(function() return pawn.CharacterMovement end)
    if not isValid(movement) then return nil end
    local mode = safe(function() return movement.MovementMode end)
    return type(mode) == "number" and mode or nil
end

local function location(pawn)
    local vector = safe(function() return pawn:K2_GetActorLocation() end)
    if vector == nil then return nil end
    local x, y, z = safe(function() return vector.X end), safe(function() return vector.Y end), safe(function() return vector.Z end)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    return { x = x / CM_PER_M, y = y / CM_PER_M, z = z / CM_PER_M }
end

-- Seconds since the server started. On Windows (and Wine) os.clock() is wall-clock time.
-- Never pass game objects in here: a UWorld can be destroyed between two calls (map change),
-- and calling into a destroyed object crashes the server.
local function now()
    return os.clock()
end

local function kick(controller, name)
    local gameMode = findFirst(GAME_MODE_CLASSES)
    if gameMode and safe(function() return gameMode:KickPlayer(controller, config.kickReason) end) ~= nil then
        return true
    end

    -- Fall back to SCUM's own admin command.
    local processor = safe(function() return StaticFindObject("/Script/SCUM.Default__MiscStatics") end)
    local world = findFirst({ "World" })
    if isValid(processor) and world then
        return pcall(function() processor:Test_ProcessAdminCommand(world, "#Kick " .. name) end)
    end
    return false
end

-- ------------------------------------------------------------------ actions

local function describe(player)
    if player.steamId then return player.name .. " (" .. player.steamId .. ")" end
    return player.name
end

local function act(player, controller, why)
    local who = describe(player)
    if config.action == "log" then
        output(who .. ": " .. why .. ". action = \"log\", so nothing was done.")
        return
    end

    local banNow = config.action == "ban"
    if config.action == "kick" and player.steamId and config.banAfterKicks > 0 then
        local kicks = (offenses[player.steamId] or 0) + 1
        offenses[player.steamId] = kicks
        saveOffenses()
        if kicks >= config.banAfterKicks then
            output(who .. " has now been kicked " .. kicks .. " times.")
            banNow = true
        end
    end

    if banNow then
        if player.steamId and ban(player.steamId) then
            output("Banned " .. who .. " (added to BannedUsers.ini): " .. why .. ".")
        elseif player.steamId then
            output("Could not write BannedUsers.ini; ban " .. who .. " manually.")
        else
            output("SteamID of " .. who .. " unknown, so they can only be kicked.")
        end
    end

    if kick(controller, player.name) then
        output("Kicked " .. who .. ": " .. why .. ".")
    else
        output("Could not kick " .. who .. "; kick them manually.")
    end
end

local function strike(player, controller, reason, time)
    local recent = {}
    for _, at in ipairs(player.strikes) do
        if time - at <= config.strikeWindowSeconds then recent[#recent + 1] = at end
    end
    recent[#recent + 1] = time
    player.strikes = recent

    output(string.format("%s: %s [strike %d/%d]", describe(player), reason, #recent, config.strikesToAct))

    if #recent >= config.strikesToAct then
        player.strikes = {}
        act(player, controller, "reached " .. config.strikesToAct .. " strikes")
    end
end

-- A violation that persists every second only counts once per REPEAT_COOLDOWN.
local function strikeOnce(player, controller, kind, reason, time)
    local last = player.lastStrike[kind]
    if last and time - last < REPEAT_COOLDOWN then return end
    player.lastStrike[kind] = time
    strike(player, controller, reason, time)
end

-- ------------------------------------------------------------------ checks

local tracked = {}   -- by controller address

-- ------------------------------------------------------------------ aim snaps

local SNAP_HISTORY = 10   -- seconds of snaps kept per player
local SNAP_WINDOW = 3     -- seconds before a kill (plus log delay) that count

local function angleDifference(a, b)
    local d = (a - b + 180) % 360 - 180
    return math.abs(d)
end

local function rotation(controller)
    local rotator = safe(function() return controller:GetControlRotation() end)
        or safe(function() return controller.ControlRotation end)
    if rotator == nil then return nil end
    local yaw, pitch = safe(function() return rotator.Yaw end), safe(function() return rotator.Pitch end)
    if type(yaw) ~= "number" or type(pitch) ~= "number" then return nil end
    return yaw, pitch
end

local function sampleAim()
    local time = now()
    -- Find the controllers again every time: one kept from an earlier tick may have been
    -- destroyed since, and touching a destroyed object crashes the server.
    for _, controller in ipairs(findAll(CONTROLLER_CLASSES)) do
        local player = tracked[address(controller)]
        local yaw, pitch = nil, nil
        if player then yaw, pitch = rotation(controller) end
        if yaw then
            local last = player.lastAim
            if last and time > last.time and time - last.time <= 0.3 then
                local turned = math.sqrt(angleDifference(yaw, last.yaw) ^ 2 + angleDifference(pitch, last.pitch) ^ 2)
                if turned >= config.aimSnapDegrees then
                    player.snaps[#player.snaps + 1] = { time = time, degrees = turned, seconds = time - last.time }
                end
            end
            player.lastAim = { yaw = yaw, pitch = pitch, time = time }
            while player.snaps[1] and time - player.snaps[1].time > SNAP_HISTORY do
                table.remove(player.snaps, 1)
            end
        end
    end
end

-- ------------------------------------------------------------------ kill analysis

local killTimes = {}   -- killer SteamID -> times of recent kills
local killStats = {}   -- killer SteamID -> { kills, snapKills }

local function weaponLimit(weapon)
    if string.find(weapon, "[Melee]", 1, true) then return config.maxMeleeDistance, "melee" end
    -- Traps, explosives and vehicles can kill far from their owner.
    if string.find(weapon, "%[") and not string.find(weapon, "[Projectile]", 1, true) then return nil end
    local lower = string.lower(weapon)
    for _, rule in ipairs(config.weaponMaxDistance or {}) do
        if type(rule) == "table" and rule[1] and string.find(lower, string.lower(rule[1]), 1, true) then
            return rule[2], rule[1]
        end
    end
    return config.maxKillDistance, "any weapon"
end

local function analyseKill(kill, byId, time)
    local player = byId[kill.killerId]
    local who = player and describe(player) or ((kill.killerName or "?") .. " (" .. kill.killerId .. ")")
    local victim = kill.victimName or kill.victimId or "?"
    if config.ignoredIds[kill.killerId] or (player and (player.verifiedAdmin and config.ignoreAdmins)) then return end

    local function suspect(reason)
        output("SUSPECT " .. who .. ": " .. reason)
        if config.strikeOnKillFlags and player and player.controller then
            strike(player, player.controller, reason, time)
        end
    end

    local limit, label = weaponLimit(kill.weapon)
    if limit and kill.distance and kill.distance > limit then
        suspect(string.format("killed %s at %.0f m with %s (limit for %s: %d m)", victim, kill.distance, kill.weapon, label, limit))
    end

    if kill.immortal then
        suspect("had god mode (immortality) while killing " .. victim)
    end

    if kill.mismatch and kill.mismatch > config.maxLocationMismatch then
        suspect(string.format("killed %s while the client was %.0f m from where the server had them", victim, kill.mismatch))
    end

    local recent = {}
    for _, at in ipairs(killTimes[kill.killerId] or {}) do
        if time - at <= config.killRateMinutes * 60 then recent[#recent + 1] = at end
    end
    recent[#recent + 1] = time
    killTimes[kill.killerId] = recent
    if #recent == config.killRateKills then
        suspect(string.format("%d kills within %d minutes", #recent, config.killRateMinutes))
    end

    if config.checks.aimSnap and player then
        local stats = killStats[kill.killerId] or { kills = 0, snapKills = 0 }
        killStats[kill.killerId] = stats
        stats.kills = stats.kills + 1

        local biggest = nil
        for _, snap in ipairs(player.snaps) do
            if time - snap.time <= SNAP_WINDOW and (biggest == nil or snap.degrees > biggest.degrees) then
                biggest = snap
            end
        end
        if biggest then
            stats.snapKills = stats.snapKills + 1
            output(string.format("%s snapped %.0f degrees in %.2f s right before killing %s.", who, biggest.degrees, biggest.seconds, victim))
            if stats.snapKills % config.aimSnapPattern == 0 and stats.snapKills * 2 >= stats.kills then
                suspect(string.format("aim snapped onto the target before %d of %d kills", stats.snapKills, stats.kills))
            end
        end
    end
end

local function processKills(time)
    if #pendingKills == 0 then return end
    local kills = pendingKills
    pendingKills = {}
    local byId = {}
    for _, player in pairs(tracked) do
        if player.steamId then byId[player.steamId] = player end
    end
    for _, kill in ipairs(kills) do
        local ok, err = pcall(analyseKill, kill, byId, time)
        if not ok then output("Kill check failed: " .. tostring(err)) end
    end
end

local function checkIdentity(player, controller, isAdmin)
    if player.steamId == nil then
        player.steamId = steamIdByName[player.name]
    end

    -- Admin rights must match AdminUsers.ini.
    player.verifiedAdmin = isAdmin and (adminIds == nil or player.steamId == nil or adminIds[player.steamId] == true)
    if config.checks.unauthorizedAdmin and isAdmin and not player.verifiedAdmin and not player.flaggedAdmin then
        player.flaggedAdmin = true
        output(describe(player) .. " has admin rights but is not in AdminUsers.ini.")
        act(player, controller, "unauthorized admin rights")
    end

    if config.checks.watchlist and player.steamId and config.watched[player.steamId] and not player.announced then
        player.announced = true
        output("Watchlisted player online: " .. describe(player) .. ".")
    end

    if config.checks.names and not player.verifiedAdmin and not player.flaggedName then
        local lower = string.lower(player.name)
        for _, pattern in ipairs(config.blocked) do
            if string.find(lower, pattern, 1, true) then
                player.flaggedName = true
                act(player, controller, "name contains '" .. pattern .. "'")
                break
            end
        end
    end
end

local function exempt(player, controller, pawn)
    if config.ignored[string.lower(player.name)] then return true end
    if player.steamId and config.ignoredIds[player.steamId] then return true end
    if config.ignoreAdmins and player.verifiedAdmin then return true end
    local allowed = allowedTeleports[player.name]
    if allowed and os.time() - allowed <= ALLOWED_TELEPORT_SECONDS then return true end
    return isTrue(controller, "IsTeleportInProgress") or isTrue(pawn, "IsTeleportInProgress")
end

local function checkMovement(player, controller, pawn, position, previous, elapsed, time, vehicle)
    local where = string.format("at %.0f, %.0f, %.0f", position.x, position.y, position.z)
    local bounds = config.mapBounds

    if config.checks.mapBounds then
        if position.x < bounds.minX or position.x > bounds.maxX or position.y < bounds.minY or position.y > bounds.maxY then
            strikeOnce(player, controller, "bounds", "outside the map " .. where, time)
        elseif position.z < bounds.minZ then
            strikeOnce(player, controller, "bounds", "below the map " .. where, time)
        end
    end

    local mode = not vehicle and movementMode(pawn) or nil

    if config.checks.flying then
        if mode == MOVE_FLYING then
            player.flyingSince = player.flyingSince or time
            if time - player.flyingSince >= config.flyingSeconds then
                player.flyingSince = time
                strike(player, controller, string.format("flying for %d s %s", config.flyingSeconds, where), time)
            end
        else
            player.flyingSince = nil
        end
    end

    if previous == nil then return end
    local dx, dy, dz = position.x - previous.x, position.y - previous.y, position.z - previous.z
    local distance = math.sqrt(dx * dx + dy * dy)
    local verticalSpeed = dz / elapsed

    if config.checks.hovering then
        if mode == MOVE_FALLING and math.abs(verticalSpeed) < HOVER_SPEED then
            player.hoverSince = player.hoverSince or (time - elapsed)
            if time - player.hoverSince >= config.hoverSeconds then
                player.hoverSince = time
                strike(player, controller, string.format("hovering in the air for %d s %s", config.hoverSeconds, where), time)
            end
        else
            player.hoverSince = nil
        end
    end

    -- A teleport is a jump further than the fastest legal movement could cover since the last
    -- check (a plane covers a lot of ground when the server stalls for a few seconds).
    local fastest = vehicle and config.maxVehicleSpeed or config.maxFootSpeed
    if config.checks.teleport and distance >= config.teleportDistance + fastest * elapsed then
        strike(player, controller, string.format("teleported %.0f m in %.1f s %s", distance, elapsed, where), time)
        return
    end

    if config.checks.speed and -verticalSpeed <= FALLING_SPEED then
        local limit = vehicle and config.maxVehicleSpeed or config.maxFootSpeed
        local speed = distance / elapsed
        if speed > limit then
            strike(player, controller, string.format("moving %.1f m/s %s (limit %d) %s",
                speed, vehicle and "in a vehicle" or "on foot", limit, where), time)
        end
    end
end

local function check(controller, time, seen)
    local key = address(controller)
    local name = playerName(controller)
    if name == nil then return end   -- still connecting
    seen[key] = true

    local player = tracked[key]
    if player == nil or player.name ~= name then
        player = { name = name, strikes = {}, lastStrike = {}, snaps = {} }
        tracked[key] = player
    end
    player.controller = controller

    checkIdentity(player, controller, isTrue(controller, "IsUserAdmin"))

    if player.steamId and pendingViolations[player.steamId] then
        local line = pendingViolations[player.steamId]
        pendingViolations[player.steamId] = nil
        strike(player, controller, "SCUM reported: " .. line, time)
    end

    local pawn = safe(function() return controller:K2_GetPawn() end)
    if not isValid(pawn) then
        player.pawn, player.position = nil, nil
        return
    end

    local position = location(pawn)
    local pawnKey = address(pawn)
    local vehicle = inVehicle(pawn)
    local previous, previousTime = player.position, player.time
    if player.pawn ~= pawnKey or player.vehicle ~= vehicle then
        -- New character, or got into / out of a vehicle (as driver or passenger): start over,
        -- and give the game a few seconds to settle where the character really is.
        previous = nil
        player.flyingSince, player.hoverSince = nil, nil
        if player.pawn ~= nil then player.settleUntil = time + SETTLE_SECONDS end
    end
    player.pawn, player.position, player.time, player.vehicle = pawnKey, position, time, vehicle

    if position == nil or exempt(player, controller, pawn) then return end

    local elapsed = previousTime and (time - previousTime) or 0
    if previous ~= nil and (elapsed <= 0 or elapsed > MAX_SAMPLE_GAP) then
        previous = nil
        player.flyingSince, player.hoverSince = nil, nil
    end

    -- A passenger's character rides along attached to the vehicle and its position jumps
    -- about; the driver is checked instead. Map bounds still apply.
    if (vehicle and isCharacter(pawn)) or (player.settleUntil and time < player.settleUntil) then
        previous = nil
    end

    checkMovement(player, controller, pawn, position, previous, elapsed, time, vehicle)
end

local playerCount = -1

local function checkAll()
    local time = now()
    local seen = {}
    local controllers = findAll(CONTROLLER_CLASSES)

    for _, controller in ipairs(controllers) do
        local ok, err = pcall(check, controller, time, seen)
        if not ok then
            output("Check failed for one player: " .. tostring(err))
        end
    end

    -- Forget players who left.
    for key in pairs(tracked) do
        if not seen[key] then tracked[key] = nil end
    end

    processKills(time)

    -- Controllers are only good for this tick.
    for _, player in pairs(tracked) do player.controller = nil end

    if #controllers ~= playerCount then
        playerCount = #controllers
        print(TAG .. "Watching " .. playerCount .. " player(s).\n")
    end
end

local busy = false
local lastConfigCheck = os.time()
LoopAsync(1000, function()
    if os.time() - lastConfigCheck >= 30 then
        lastConfigCheck = os.time()
        if readConfigText() ~= configText then
            config = loadConfig()
            output("Settings reloaded (action=" .. config.action .. ").")
        end
    end
    if not busy then
        local ok, err = pcall(refreshFiles, os.time())
        if not ok then output("Reading SCUM's files failed: " .. tostring(err)) end

        busy = true
        ExecuteInGameThread(function()
            local checked, failure = pcall(checkAll)
            busy = false
            if not checked then output("Check failed: " .. tostring(failure)) end
        end)
    end
    return false
end)

if config.checks.aimSnap then
    local sampling = false
    LoopAsync(100, function()
        if not sampling then
            sampling = true
            ExecuteInGameThread(function()
                local ok, err = pcall(sampleAim)
                sampling = false
                if not ok then output("Aim sampling failed: " .. tostring(err)) end
            end)
        end
        return false
    end)
end

local enabled = {}
for _, name in ipairs({ "speed", "teleport", "flying", "hovering", "mapBounds", "unauthorizedAdmin", "names", "watchlist", "gameLogs", "killLog", "aimSnap" }) do
    if config.checks[name] then enabled[#enabled + 1] = name end
end
output(string.format("Active. action=%s, %d strikes in %d s. Checks: %s.",
    config.action, config.strikesToAct, config.strikeWindowSeconds, table.concat(enabled, ", ")))
