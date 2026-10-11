--[[
    ScumAntiCheat - server-side movement checks for SCUM.

    Once a second it reads every player's position on the server and flags:
      - speed:    moving faster than anyone can on foot or in a vehicle
      - teleport: jumping hundreds of metres between two checks without an admin teleport

    BattlEye covers the client (aimbots, ESP, injected code). This catches what still shows up
    on the server. Admins, players being teleported by the game, falling or parachuting
    players and freshly (re)spawned characters are not checked.

    Settings: config.lua in this mod's folder.
    Reports:  anticheat.log in this mod's folder, UE4SS.log, and the Pelican console when the
              PelicanConsole mod is installed.
]]

local TAG = "[ScumAntiCheat] "
local CONTROLLER_CLASSES = { "ConZPlayerController", "BP_ConZPlayerController_C", "PlayerController" }
local GAME_MODE_CLASSES = { "BP_ConZGameMode_C", "ConZGameMode" }
local CM_PER_M = 100
local FALLING_SPEED = 5      -- m/s downwards; above this the horizontal check is skipped
local MAX_SAMPLE_GAP = 5     -- seconds; older samples are discarded instead of compared

local DEFAULTS = {
    action = "log",
    strikesToAct = 3,
    strikeWindowSeconds = 60,
    maxFootSpeed = 15,
    maxVehicleSpeed = 120,
    teleportDistance = 300,
    ignoreAdmins = true,
    ignoreNames = {},
    kickReason = "Kicked by anti-cheat (movement).",
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

local LOG_FILES = { DIR .. "/anticheat.log", DIR .. "/../PelicanConsole/console.log" }

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

local function loadConfig()
    local config = {}
    for key, value in pairs(DEFAULTS) do config[key] = value end

    local ok, loaded = pcall(dofile, DIR .. "/config.lua")
    if ok and type(loaded) == "table" then
        for key, value in pairs(loaded) do config[key] = value end
    elseif not ok then
        output("config.lua could not be read, using defaults: " .. tostring(loaded))
    end

    if config.action ~= "log" and config.action ~= "kick" then
        output("Unknown action '" .. tostring(config.action) .. "', using \"log\".")
        config.action = "log"
    end

    config.ignored = {}
    for _, name in ipairs(config.ignoreNames or {}) do
        config.ignored[string.lower(name)] = true
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
    if name == nil or name == "" then return "unknown player" end
    return name
end

local function isTrue(object, method)
    return safe(function() return object[method](object) end) == true
end

local function className(object)
    return safe(function() return object:GetClass():GetFName():ToString() end) or ""
end

local function inVehicle(pawn)
    -- Driving possesses the vehicle; passengers are attached to it.
    if not string.find(className(pawn), "Prisoner", 1, true) then return true end
    return isValid(safe(function() return pawn:GetAttachParentActor() end))
end

local function location(pawn)
    local vector = safe(function() return pawn:K2_GetActorLocation() end)
    if vector == nil then return nil end
    local x, y, z = safe(function() return vector.X end), safe(function() return vector.Y end), safe(function() return vector.Z end)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    return { x = x / CM_PER_M, y = y / CM_PER_M, z = z / CM_PER_M }
end

local gameplayStatics = nil
local function now(world)
    if gameplayStatics == nil then
        gameplayStatics = safe(function() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end) or false
    end
    if gameplayStatics and world then
        local seconds = safe(function() return gameplayStatics:GetRealTimeSeconds(world) end)
        if type(seconds) == "number" then return seconds end
    end
    return os.time()
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

-- ------------------------------------------------------------------ checks

local tracked = {}   -- by controller address: { pawn, position, time, strikes = { times } }

local function strike(entry, controller, name, reason, time)
    local recent = {}
    for _, at in ipairs(entry.strikes) do
        if time - at <= config.strikeWindowSeconds then recent[#recent + 1] = at end
    end
    recent[#recent + 1] = time
    entry.strikes = recent

    output(string.format("%s: %s [strike %d/%d]", name, reason, #recent, config.strikesToAct))

    if #recent >= config.strikesToAct then
        entry.strikes = {}
        if config.action == "kick" then
            if kick(controller, name) then
                output("Kicked " .. name .. ".")
            else
                output("Could not kick " .. name .. "; kick them manually.")
            end
        else
            output(name .. " reached " .. config.strikesToAct .. " strikes. action = \"log\", so nothing was done.")
        end
    end
end

local function check(controller, world, time, seen)
    local key = address(controller)
    seen[key] = true

    local pawn = safe(function() return controller:K2_GetPawn() end)
    if not isValid(pawn) then
        tracked[key] = nil
        return
    end

    local entry = tracked[key]
    if entry == nil then
        entry = { strikes = {} }
        tracked[key] = entry
    end

    local position = location(pawn)
    local pawnKey = address(pawn)
    local previous, previousTime = entry.position, entry.time
    local samePawn = entry.pawn == pawnKey
    entry.pawn, entry.position, entry.time = pawnKey, position, time

    -- New character, vehicle entered or left, or no usable previous sample: start over.
    if not samePawn or position == nil or previous == nil then return end
    local elapsed = time - previousTime
    if elapsed <= 0 or elapsed > MAX_SAMPLE_GAP then return end

    local name = playerName(controller)
    if config.ignored[string.lower(name)] then return end
    if config.ignoreAdmins and isTrue(controller, "IsUserAdmin") then return end
    if isTrue(controller, "IsTeleportInProgress") or isTrue(pawn, "IsTeleportInProgress") then return end

    local dx, dy, dz = position.x - previous.x, position.y - previous.y, position.z - previous.z
    local distance = math.sqrt(dx * dx + dy * dy)
    local where = string.format("at %.0f, %.0f, %.0f", position.x, position.y, position.z)

    if distance >= config.teleportDistance then
        strike(entry, controller, name, string.format("teleported %.0f m in %.1f s %s", distance, elapsed, where), time)
        return
    end

    if -dz / elapsed > FALLING_SPEED then return end

    local vehicle = inVehicle(pawn)
    local limit = vehicle and config.maxVehicleSpeed or config.maxFootSpeed
    local speed = distance / elapsed
    if speed > limit then
        strike(entry, controller, name, string.format("moving %.1f m/s %s (limit %d) %s",
            speed, vehicle and "in a vehicle" or "on foot", limit, where), time)
    end
end

local playerCount = -1

local function checkAll()
    local world = findFirst({ "World" })
    local time = now(world)
    local seen = {}
    local controllers = findAll(CONTROLLER_CLASSES)

    for _, controller in ipairs(controllers) do
        local ok, err = pcall(check, controller, world, time, seen)
        if not ok then
            output("Check failed for one player: " .. tostring(err))
        end
    end

    -- Forget players who left.
    for key in pairs(tracked) do
        if not seen[key] then tracked[key] = nil end
    end

    if #controllers ~= playerCount then
        playerCount = #controllers
        print(TAG .. "Watching " .. playerCount .. " player(s).\n")
    end
end

local busy = false
LoopAsync(1000, function()
    if not busy then
        busy = true
        ExecuteInGameThread(function()
            local ok, err = pcall(checkAll)
            busy = false
            if not ok then output("Check failed: " .. tostring(err)) end
        end)
    end
    return false
end)

output(string.format("Active. action=%s, foot limit %d m/s, vehicle limit %d m/s, teleport %d m, %d strikes in %d s.",
    config.action, config.maxFootSpeed, config.maxVehicleSpeed, config.teleportDistance,
    config.strikesToAct, config.strikeWindowSeconds))
