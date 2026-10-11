--[[
    PelicanConsole - runs SCUM admin commands typed into the Pelican console.

    The SCUM egg's start command appends each line typed in the Pelican console to
    ue4ss/Mods/PelicanConsole/commands.txt. This mod picks those lines up once a second
    and runs them through an online admin's chat command channel, exactly as if they typed it in chat.
    Announce, ListPlayers and Kick <name> are handled directly and work with no admin online.

    Results and errors are written to ue4ss/Mods/PelicanConsole/console.log, which the
    egg and the SCUM Manager Admin Console page show.
]]

-- Commands are sent the way they are typed in SCUM's chat: with a leading "#".
-- Typing "ListPlayers" or "#ListPlayers" in the console both become "#ListPlayers".
local COMMAND_PREFIX = "#"

local TAG = "[PelicanConsole] "
local PROCESSOR_PATH = "/Script/SCUM.Default__MiscStatics"
local WORLD_CONTEXT_CLASSES = { "World", "BP_ConZGameMode_C", "ConZGameMode", "GameStateBase" }

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
local COMMANDS_FILE = DIR and (DIR .. "/commands.txt") or nil
local PROCESSING_FILE = DIR and (DIR .. "/commands.processing") or nil
local OUTPUT_FILE = DIR and (DIR .. "/console.log") or nil

local function output(message)
    local line = os.date("!%H:%M:%S") .. " " .. TAG .. message
    print(line .. "\n")

    if OUTPUT_FILE ~= nil then
        local file = io.open(OUTPUT_FILE, "a")
        if file ~= nil then
            file:write(line .. "\n")
            file:close()
        end
    end
end

local function trim(text)
    return (string.gsub(text or "", "^%s+", ""):gsub("%s+$", ""))
end

local function normalize(command)
    command = trim(command)
    if command == "" then
        return nil
    end

    command = string.gsub(command, "^#+", "")
    return COMMAND_PREFIX .. command
end

local function isValid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end

local function worldContext()
    for _, className in ipairs(WORLD_CONTEXT_CLASSES) do
        local object = safe(function() return FindFirstOf(className) end)
        if isValid(object) then
            return object
        end
    end
    return nil
end

local CONTROLLER_CLASSES = { "BP_ConZPlayerController_C", "ConZPlayerController" }
local GAME_MODE_CLASSES = { "BP_ConZGameMode_C", "ConZGameMode" }

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
    if name == nil or name == "" then return "?" end
    return name
end

local function isAdmin(controller)
    return safe(function() return controller:IsUserAdmin() end) == true
end

local function players()
    local list = {}
    for _, controller in ipairs(findAll(CONTROLLER_CLASSES)) do
        list[#list + 1] = { controller = controller, name = playerName(controller), admin = isAdmin(controller) }
    end
    return list
end

-- The chat command channel of an online admin: running a command through it is the same
-- as that admin typing it in chat.
local function adminChannel()
    local admins = {}
    for _, player in ipairs(players()) do
        if player.admin then admins[address(player.controller)] = player end
    end
    if next(admins) == nil then return nil end

    for _, channel in ipairs(findAll({ "PlayerRpcChannel" })) do
        local owner = safe(function() return channel:GetOwner() end)
        local player = owner and admins[address(owner)]
        if player == nil and owner ~= nil then
            local ownerOwner = safe(function() return owner:GetOwner() end)
            player = ownerOwner and admins[address(ownerOwner)]
        end
        if player ~= nil then return channel, player end
    end
    return nil, select(2, next(admins))
end

local function verb(command)
    local name, rest = string.match(command, "^#*(%S+)%s*(.-)%s*$")
    return string.lower(name or ""), rest or ""
end

local function listPlayers()
    local list = players()
    if #list == 0 then
        output("No players online.")
        return
    end
    output(#list .. " player(s) online:")
    for _, player in ipairs(list) do
        output("  " .. player.name .. (player.admin and " (admin)" or ""))
    end
end

local function announce(message)
    if message == "" then
        output("Usage: Announce <message>")
        return
    end
    local gameMode = findFirst(GAME_MODE_CLASSES)
    if gameMode == nil then
        output("The game world is not loaded yet. Try again once the server is online.")
        return
    end
    local ok, err = pcall(function() gameMode:SendHUDMessageToAll(message, false) end)
    if ok then
        output("Announced: " .. message)
    else
        output("Failed to announce (" .. tostring(err) .. ")")
    end
end

local function kick(target)
    if target == "" then
        output("Usage: Kick <player name or SteamID>")
        return
    end
    local gameMode = findFirst(GAME_MODE_CLASSES)
    local lower = string.lower(target)
    local matches = {}
    for _, player in ipairs(players()) do
        if string.lower(player.name) == lower then matches = { player } break end
        if string.find(string.lower(player.name), lower, 1, true) then matches[#matches + 1] = player end
    end

    if gameMode == nil or #matches == 0 then
        return false   -- not an online name (maybe a SteamID): let SCUM handle it
    end
    if #matches > 1 then
        output("More than one player matches \"" .. target .. "\". Use the full name.")
        return true
    end
    local ok, err = pcall(function() gameMode:KickPlayer(matches[1].controller, "Kicked by an admin.") end)
    output(ok and ("Kicked " .. matches[1].name .. ".") or ("Failed to kick " .. matches[1].name .. " (" .. tostring(err) .. ")"))
    return true
end

-- SCUM's test helper: accepts commands but ignores most of them on a dedicated server.
local function runWithoutAdmin(command)
    local processor = safe(function() return StaticFindObject(PROCESSOR_PATH) end)
    local context = worldContext()
    if not isValid(processor) or context == nil then
        output("No admin is online, so SCUM cannot run " .. command .. ". Join as an admin (AdminUsers.ini) and try again.")
        return
    end
    local ok, err = pcall(function() processor:Test_ProcessAdminCommand(context, command) end)
    if ok then
        output("Sent " .. command .. ", but no admin is online, so SCUM may ignore it. Join as an admin (AdminUsers.ini) for full command support.")
    else
        output("Failed: " .. command .. " (" .. tostring(err) .. ")")
    end
end

local function run(command)
    local name, rest = verb(command)

    if name == "listplayers" then return listPlayers() end
    if name == "announce" then return announce(rest) end
    if name == "kick" and kick(rest) then return end

    local channel, admin = adminChannel()
    if channel ~= nil then
        local ok, err = pcall(function() channel:Chat_Server_ProcessAdminCommand(command) end)
        if ok then
            output("Ran as " .. admin.name .. ": " .. command .. " (replies appear in their chat)")
        else
            output("Failed: " .. command .. " (" .. tostring(err) .. ")")
        end
        return
    end
    if admin ~= nil then
        output("Found admin " .. admin.name .. " online but not their command channel; trying without.")
    end
    runWithoutAdmin(command)
end

-- Take the pending commands. Renaming first means a line appended while we read lands
-- in a fresh commands.txt instead of being lost.
local function takeCommands()
    if COMMANDS_FILE == nil then
        return {}
    end

    -- Windows' rename fails if the target exists, so clear any leftover first.
    os.remove(PROCESSING_FILE)
    if not os.rename(COMMANDS_FILE, PROCESSING_FILE) then
        return {}
    end

    local commands = {}
    local file = io.open(PROCESSING_FILE, "r")
    if file ~= nil then
        for line in file:lines() do
            local command = normalize(line)
            if command ~= nil then
                commands[#commands + 1] = command
            end
        end
        file:close()
    end
    os.remove(PROCESSING_FILE)

    return commands
end

if DIR == nil then
    print(TAG .. "Could not work out the mod folder; console commands are disabled.\n")
    return
end

-- Commands typed while the server was down would run at a random moment later; drop them.
os.remove(COMMANDS_FILE)
os.remove(PROCESSING_FILE)

LoopAsync(1000, function()
    local commands = takeCommands()
    for _, command in ipairs(commands) do
        ExecuteInGameThread(function()
            run(command)
        end)
    end
    return false
end)

output("Ready. Type SCUM admin commands in the Pelican console, e.g. ListPlayers or Announce Hello.")
