--[[
    PelicanConsole - runs SCUM admin commands typed into the Pelican console.

    The SCUM egg's start command appends each line typed in the Pelican console to
    ue4ss/Mods/PelicanConsole/commands.txt. This mod picks those lines up once a second
    and runs them through an online admin's chat command channel, exactly as if they typed it in chat.
    Announce, ListPlayers and Kick <name> are handled directly and work with no admin online,
    as do the experimental WhereIs, Balance, TeleportPlayer, FindItem and GiveItem.

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

-- ------------------------------------------------------------------ experimental, no admin needed
-- These call SCUM and Unreal functions found by the probe directly. They are new and not yet
-- confirmed on a live server, so try them on yourself first.

local function findPlayer(target)
    local lowered = string.lower(target or "")
    if lowered == "" then return nil end
    local partial = nil
    for _, player in ipairs(players()) do
        local name = string.lower(player.name)
        if name == lowered then return player end
        if partial == nil and string.find(name, lowered, 1, true) then partial = player end
    end
    return partial
end

local function pawnOf(controller)
    local pawn = safe(function() return controller:K2_GetPawn() end)
    return isValid(pawn) and pawn or nil
end

local function locationOf(pawn)
    local vector = safe(function() return pawn:K2_GetActorLocation() end)
    local x, y, z = safe(function() return vector.X end), safe(function() return vector.Y end), safe(function() return vector.Z end)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    return { X = x, Y = y, Z = z }
end

-- "Name x y z" or "Name" -> player, rest
local function playerAndRest(text, usage)
    -- Names can contain spaces: try the longest prefix that matches an online player.
    local words = {}
    for word in string.gmatch(text or "", "%S+") do words[#words + 1] = word end
    for count = #words, 1, -1 do
        local player = findPlayer(table.concat(words, " ", 1, count))
        if player then return player, table.concat(words, " ", count + 1) end
    end
    output("No online player matches \"" .. tostring(text) .. "\". " .. usage)
    return nil
end

local function whereIs(text)
    local player = playerAndRest(text, "Usage: WhereIs <player>")
    if player == nil then return end
    local pawn = pawnOf(player.controller)
    local at = pawn and locationOf(pawn)
    output(at and string.format("%s is at %.0f %.0f %.0f", player.name, at.X, at.Y, at.Z) or (player.name .. " has no character right now."))
end

local function balance(text)
    local player = playerAndRest(text, "Usage: Balance <player>")
    if player == nil then return end
    local function currency(kind)
        return safe(function() return player.controller:GetCurrencyBalanceText(kind):ToString() end) or "?"
    end
    local fame = safe(function() return player.controller:GetFamePointsRounded() end)
    output(string.format("%s: money %s, gold %s, fame %s", player.name, currency(0), currency(1), tostring(fame or "?")))
end

-- Tell ScumAntiCheat (if installed) that this teleport is ours, so it is not flagged.
local function allowTeleport(name)
    local folder = DIR .. "/../ScumAntiCheat"
    local probe = io.open(folder .. "/config.lua", "r")
    if probe == nil then return end
    probe:close()
    local file = io.open(folder .. "/allowed_teleports.txt", "a")
    if file then
        file:write(os.time() .. " " .. name .. "\n")
        file:close()
    end
end

local function teleportPlayer(text)
    local player, rest = playerAndRest(text, "Usage: TeleportPlayer <player> <x> <y> <z>")
    if player == nil then return end
    local x, y, z = string.match(rest or "", "^(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)$")
    if x == nil then return output("Usage: TeleportPlayer <player> <x> <y> <z> (get coordinates with WhereIs)") end
    local pawn = pawnOf(player.controller)
    if pawn == nil then return output(player.name .. " has no character right now.") end
    allowTeleport(player.name)
    local ok, result = pcall(function()
        return pawn:K2_TeleportTo({ X = tonumber(x), Y = tonumber(y), Z = tonumber(z) }, { Pitch = 0, Yaw = 0, Roll = 0 })
    end)
    if ok and result ~= false then
        output(string.format("Teleported %s to %s %s %s (experimental).", player.name, x, y, z))
    else
        output("Teleport failed for " .. player.name .. ": " .. tostring(ok and "the game refused" or result))
    end
end

-- Item classes are Blueprints such as BP_Weapon_AK47_C. Look among the classes the game has loaded.
local function findItemClass(name)
    local candidates = { name, name .. "_C", "BP_" .. name .. "_C", "BP_" .. name }
    for _, candidate in ipairs(candidates) do
        local found = safe(function() return FindObject("BlueprintGeneratedClass", candidate) end)
        if isValid(found) then return found, candidate end
    end
    return nil
end

local function findItems(text)
    local lowered = string.lower(trim(text))
    if lowered == "" then return output("Usage: FindItem <part of an item name>") end
    local matches = {}
    local classes = safe(function() return FindObjects(0, "BlueprintGeneratedClass", nil, 0, 0, false) end) or {}
    for _, class in pairs(classes) do
        local name = safe(function() return class:GetFName():ToString() end)
        if name and string.find(string.lower(name), lowered, 1, true) then matches[#matches + 1] = name end
    end
    table.sort(matches)
    if #matches == 0 then return output("No loaded class matches \"" .. text .. "\".") end
    output(#matches .. " loaded class(es) match \"" .. text .. "\"" .. (#matches > 40 and ", first 40:" or ":"))
    for index = 1, math.min(40, #matches) do output("  " .. matches[index]) end
end

local function giveItem(text)
    local player, rest = playerAndRest(text, "Usage: GiveItem <player> <item> [amount]")
    if player == nil then return end
    local item, amount = string.match(rest or "", "^(%S+)%s*(%d*)$")
    if item == nil then return output("Usage: GiveItem <player> <item> [amount]") end
    amount = math.max(1, math.min(tonumber(amount) or 1, 10))

    local class, className = findItemClass(item)
    if class == nil then return output("Item " .. item .. " is not loaded. Try FindItem " .. item .. " for the exact class name.") end
    local pawn = pawnOf(player.controller)
    local at = pawn and locationOf(pawn)
    if at == nil then return output(player.name .. " has no character right now.") end
    local statics = safe(function() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end)
    local world = findFirst({ "World" })
    if not isValid(statics) or world == nil then return output("The game world is not ready.") end

    local placed, dropped = 0, 0
    for _ = 1, amount do
        local transform = {
            Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
            Translation = { X = at.X, Y = at.Y, Z = at.Z + 50 },
            Scale3D = { X = 1, Y = 1, Z = 1 },
        }
        local ok, err = pcall(function()
            local actor = statics:BeginDeferredActorSpawnFromClass(world, class, transform, 1, nil)
            if not isValid(actor) then error("the game did not create the item") end
            statics:FinishSpawningActor(actor, transform)
            pcall(function() pawn:PlaceItemInInventoryOrHolster(actor, true) end)
            if safe(function() return pawn:HasItem(actor) end) == true then placed = placed + 1 else dropped = dropped + 1 end
        end)
        if not ok then return output("GiveItem failed for " .. className .. ": " .. tostring(err)) end
    end
    output(string.format("Gave %s %d x %s (experimental): %d in their inventory, %d at their feet.", player.name, amount, className, placed, dropped))
end

-- Every trader outpost has a banker. Their positions give the outposts on this server's map.
local OUTPOST_MARKERS = { "BP_Banker_C", "Banker" }
local OUTPOST_SECTORS = { "a0", "b4", "c2", "z3" }   -- SCUM's four outposts
local SAME_OUTPOST = 30000                            -- 300 m

-- Names the four outposts by sector when exactly one way of laying SCUM's grid (rows A, B, C
-- then Z; columns 0 to 4) over the map fits their positions. Otherwise nil.
local function sectorNames(points)
    if #points ~= #OUTPOST_SECTORS then return nil end
    local columns = { a0 = 0, b4 = 4, c2 = 2, z3 = 3 }
    local fits = {}
    for _, axis in ipairs({ "X", "Y" }) do
        local other = axis == "X" and "Y" or "X"
        for _, rowDirection in ipairs({ 1, -1 }) do
            for _, columnDirection in ipairs({ 1, -1 }) do
                local order = {}
                for index in ipairs(points) do order[index] = index end
                table.sort(order, function(a, b) return points[a][axis] * rowDirection < points[b][axis] * rowDirection end)
                local names, consistent = {}, true
                for rank, index in ipairs(order) do names[index] = OUTPOST_SECTORS[rank] end
                for a in ipairs(points) do
                    for b in ipairs(points) do
                        if columns[names[a]] < columns[names[b]] and points[a][other] * columnDirection >= points[b][other] * columnDirection then
                            consistent = false
                        end
                    end
                end
                if consistent then fits[#fits + 1] = names end
            end
        end
    end
    return #fits == 1 and fits[1] or nil
end

local function findOutposts()
    local points = {}
    for _, actor in ipairs(findAll(OUTPOST_MARKERS)) do
        local at = locationOf(actor)
        if at then
            -- Stand a few metres in front of the banker, not inside them.
            local forward = safe(function() return actor:GetActorForwardVector() end)
            local fx, fy = safe(function() return forward.X end), safe(function() return forward.Y end)
            if type(fx) == "number" and type(fy) == "number" then
                at.X, at.Y = at.X + fx * 250, at.Y + fy * 250
            end
            at.Z = at.Z + 20
            local duplicate = false
            for _, point in ipairs(points) do
                if math.abs(point.X - at.X) < SAME_OUTPOST and math.abs(point.Y - at.Y) < SAME_OUTPOST then duplicate = true end
            end
            if not duplicate then points[#points + 1] = at end
        end
    end
    if #points == 0 then return output("No outposts found: no bankers are loaded on this map.") end

    table.sort(points, function(a, b) return a.X < b.X end)
    local names = sectorNames(points)
    output(#points .. " outpost(s) found" .. (names and ", named by sector:" or " (names could not be matched to sectors):"))
    for index, point in ipairs(points) do
        output(string.format("Outpost %s at %.0f %.0f %.0f", names and names[index] or ("outpost" .. index), point.X, point.Y, point.Z))
    end
end

local function run(command)
    local name, rest = verb(command)

    if name == "findoutposts" then return findOutposts() end

    if name == "whereis" then return whereIs(rest) end
    if name == "balance" then return balance(rest) end
    if name == "teleportplayer" then return teleportPlayer(rest) end
    if name == "finditem" then return findItems(rest) end
    if name == "giveitem" then return giveItem(rest) end
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
