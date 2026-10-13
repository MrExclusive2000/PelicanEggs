--[[
    ExclsvConsole - runs SCUM admin commands typed into the Pelican console.

    The SCUM egg's start command appends each line typed in the Pelican console to
    ue4ss/Mods/ExclsvConsole/commands.txt. This mod picks those lines up once a second
    and runs them through an online admin's chat command channel, exactly as if they typed it in chat.
    Announce, ListPlayers, Kick <name>, WhereIs, Balance, FindOutposts, FindItem and ListItems
    are handled directly and work with no admin online, as do TeleportPlayer and GiveItem (not
    yet confirmed on a live server). With no-admin-commands.txt in this folder, money, fame,
    SpawnItem and Teleport commands also run without an admin (see the README). A minute after the world loads, the mod writes the item names to items.txt
    for SCUM Manager's item dropdowns.

    Results and errors are written to ue4ss/Mods/ExclsvConsole/console.log, which the
    egg and the SCUM Manager Admin Console page show.
]]

-- Commands are sent the way they are typed in SCUM's chat: with a leading "#".
-- Typing "ListPlayers" or "#ListPlayers" in the console both become "#ListPlayers".
local COMMAND_PREFIX = "#"

local TAG = "[ExclsvConsole] "

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

local CONTROLLER_CLASSES = { "BP_ConZPlayerController_C", "ConZPlayerController" }
local GAME_MODE_CLASSES = { "BP_ConZGameMode_C", "ConZGameMode" }

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
    if name == nil or name == "" then return "?" end
    return name
end

local function isAdmin(controller)
    return safe(function() return controller:IsUserAdmin() end) == true
end

local function players()
    local list = {}
    for _, controller in ipairs(playerControllers(findAll, CONTROLLER_CLASSES)) do
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

-- ------------------------------------------------------------------ handled by the mod, no admin needed
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
    -- Plain values the controller keeps for the player's screen. Calling SCUM's
    -- GetCurrencyBalanceText (it builds a formatted text) crashed a live server, so it is not used.
    local function value(field)
        local number = safe(function() return player.controller[field] end)
        return type(number) == "number" and string.format("%d", number) or "?"
    end
    output(string.format("%s: money %s, gold %s, fame %s", player.name,
        value("_moneyBalanceRep"), value("_goldBalanceRep"), value("_repFamePoints")))
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
        output(string.format("Teleported %s to %s %s %s.", player.name, x, y, z))
    else
        output("Teleport failed for " .. player.name .. ": " .. tostring(ok and "the game refused" or result))
    end
end

-- Never keep game objects between calls: SCUM unloads item classes it is not using, and touching
-- an unloaded class crashes the server. Item types are remembered by path and looked up again.
local knownItems = {}    -- class name -> object path, every item seen (kept in items.txt)
local scanItems          -- defined with the item list below

-- Item classes are Blueprints such as BP_Weapon_AK47_C. Look among the classes the game has loaded.
local function findItemClass(name)
    local candidates = { name, name .. "_C", "BP_" .. name .. "_C", "BP_" .. name }
    for _, candidate in ipairs(candidates) do
        local found = safe(function() return FindObject("BlueprintGeneratedClass", candidate) end)
        if isValid(found) then return found, candidate end
    end
    -- FindObject by short name does not work on every UE4SS build: use the item scan's paths.
    if next(knownItems) == nil then scanItems() end
    for _, candidate in ipairs(candidates) do
        local path = knownItems[candidate]
        if path and path ~= "" then
            -- Already loaded, or SCUM loads item types on demand: load it from its path.
            local found = safe(function() return StaticFindObject(path) end)
            if not isValid(found) then found = safe(function() return LoadAsset(path) end) end
            if isValid(found) then return found, candidate end
        end
    end
    return nil
end

-- items.txt lists every item type seen so far ("ClassName<TAB>/Game/...path"). SCUM loads item
-- types on demand, so one scan only sees what is in memory at that moment; the list grows with
-- each scan. SCUM Manager reads it to offer item dropdowns.
local ITEMS_FILE = DIR and (DIR .. "/items.txt") or nil

local function loadKnownItems()
    local file = ITEMS_FILE and io.open(ITEMS_FILE, "r")
    if not file then return end
    for line in file:lines() do
        local name, path = string.match(line, "^([%w_]+)\t?(%S*)")
        if name then knownItems[name] = path ~= "" and path or knownItems[name] or "" end
    end
    file:close()
end
loadKnownItems()

local NOT_AN_ITEM = { "^ABP_", "^WBP_", "^UI_", "^SKEL_", "^REINST_", "^Default__", "Component", "AnimBP", "Widget" }

-- True / false from the class's parents (needs UE4SS's GetSuperStruct), or nil when unknown.
local function derivesFromItem(class)
    local current = class
    for depth = 1, 15 do
        local ok, parent = pcall(function() return current:GetSuperStruct() end)
        if not ok then
            if depth == 1 then return nil end   -- this UE4SS cannot read parents
            return false
        end
        if not isValid(parent) then return false end
        local name = safe(function() return parent:GetFName():ToString() end)
        if name == "Item" then return true end
        current = parent
    end
    return false
end

-- Every loaded item class. Items live under /Game/ConZ_Files/Items/; where UE4SS can read a
-- class's parents, only classes deriving from SCUM's Item count.
scanItems = function()
    local classes = safe(function() return FindObjects(0, "Class", nil, 0, 0, false) end) or {}
    local names, byParent, byFolder = {}, 0, 0
    local itemClasses = {}
    for _, class in pairs(classes) do
        local name = safe(function() return class:GetFName():ToString() end)
        local path = safe(function() return class:GetFullName() end) or ""
        local skip = name == nil
        for _, pattern in ipairs(NOT_AN_ITEM) do
            if name and string.find(name, pattern) then skip = true end
        end
        if not skip then
            local isItem = derivesFromItem(class)
            if isItem == true then
                byParent = byParent + 1
            elseif isItem == nil and string.find(path, "/ConZ_Files/Items/", 1, true) and string.find(name, "_C$") then
                isItem = true
                byFolder = byFolder + 1
            end
            if isItem then
                names[#names + 1] = name
                itemClasses[name] = class
            end
        end
    end
    local new = 0
    for _, name in ipairs(names) do
        local path = string.match(safe(function() return itemClasses[name]:GetFullName() end) or "", "^%S+%s+(.+)$") or ""
        if knownItems[name] == nil then new = new + 1 end
        if path ~= "" or knownItems[name] == nil then knownItems[name] = path end
    end
    local all = {}
    for name in pairs(knownItems) do all[#all + 1] = name end
    table.sort(all)
    return all, #classes, byParent, byFolder, #names, new
end

local function writeItemList(quiet)
    local names, scanned, byParent, byFolder, loaded, new = scanItems()
    if #names == 0 then
        if not quiet then output("No item classes found (" .. scanned .. " classes checked). Try ListItems again once the server is fully online.") end
        return false
    end
    local file = io.open(ITEMS_FILE, "w")
    if file == nil then
        output("Could not write " .. tostring(ITEMS_FILE) .. ".")
        return false
    end
    local lines = {}
    for _, name in ipairs(names) do lines[#lines + 1] = name .. "\t" .. (knownItems[name] or "") end
    file:write(table.concat(lines, "\n") .. "\n")
    file:close()
    if not quiet or new > 0 then
        output(string.format("Item list: %d items known, %d loaded right now (%d new). %d classes checked (%d by parent class, %d by folder). Refresh ExclsvSCUM Manager to see them.",
            #names, loaded, new, scanned, byParent, byFolder))
    end
    return true
end

local function findItems(text)
    local lowered = string.lower(trim(text))
    if lowered == "" then return output("Usage: FindItem <part of an item name>") end
    local names = scanItems()
    local matches = {}
    for _, name in ipairs(names) do
        if string.find(string.lower(name), lowered, 1, true) then matches[#matches + 1] = name end
    end
    if #matches == 0 then return output("No item matches \"" .. text .. "\" (" .. #names .. " items loaded).") end
    output(#matches .. " item(s) match \"" .. text .. "\"" .. (#matches > 40 and ", first 40:" or ":"))
    for index = 1, math.min(40, #matches) do output("  " .. matches[index]) end
end

local function giveItem(text)
    local player, rest = playerAndRest(text, "Usage: GiveItem <player> <item> [amount]")
    if player == nil then return end
    local item, amount = string.match(rest or "", "^(%S+)%s*(%d*)$")
    if item == nil then return output("Usage: GiveItem <player> <item> [amount]") end
    amount = math.max(1, math.min(tonumber(amount) or 1, 10))

    local class, className = findItemClass(item)
    if class == nil then
        return output("Item " .. item .. " has not been loaded on this server yet. Spawn one once with SpawnItem " .. item
            .. " (as an admin in game), then try again.")
    end
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
    output(string.format("Gave %s %d x %s: %d in their inventory, %d at their feet.", player.name, amount, className, placed, dropped))
end

-- Outposts are found from the traders, bankers or safe zones the map has loaded.
local OUTPOST_SECTORS = { "a0", "b4", "c2", "z3" }   -- SCUM's four outposts
local SAME_OUTPOST = 30000                            -- 300 m

-- SCUM's grid: five 3048 m sectors each way from -904800 cm.
local GRID_MIN, CELL = -904800, 304800
local ROW_INDEX = { { a = 0, b = 1, c = 2, z = 4 }, { z = 0, a = 1, b = 2, c = 3 } }   -- Z after D, or before A

local function cellOf(value, direction)
    local index = math.floor((value - GRID_MIN) / CELL)
    return direction > 0 and index or 4 - index
end

-- Names the four outposts by sector from the way of laying SCUM's grid (rows A, B, C with Z
-- before A or after C; columns 0 to 4) that fits their positions. Several layouts can fit the
-- order of the positions; the one that also puts each in its sector on SCUM's grid wins.
-- Otherwise nil.
local function sectorNames(points)
    if #points ~= #OUTPOST_SECTORS then return nil end
    local columns = { a0 = 0, b4 = 4, c2 = 2, z3 = 3 }
    local fits, exact = {}, {}
    for orderIndex, sectors in ipairs({ OUTPOST_SECTORS, { "z3", "a0", "b4", "c2" } }) do
        for _, axis in ipairs({ "X", "Y" }) do
            local other = axis == "X" and "Y" or "X"
            for _, rowDirection in ipairs({ 1, -1 }) do
                for _, columnDirection in ipairs({ 1, -1 }) do
                    local order = {}
                    for index in ipairs(points) do order[index] = index end
                    table.sort(order, function(a, b) return points[a][axis] * rowDirection < points[b][axis] * rowDirection end)
                    local names, consistent = {}, true
                    for rank, index in ipairs(order) do names[index] = sectors[rank] end
                    for a in ipairs(points) do
                        for b in ipairs(points) do
                            if columns[names[a]] < columns[names[b]] and points[a][other] * columnDirection >= points[b][other] * columnDirection then
                                consistent = false
                            end
                        end
                    end
                    if consistent then
                        fits[#fits + 1] = names
                        local onGrid = true
                        for index, point in ipairs(points) do
                            local sector = names[index]
                            if cellOf(point[axis], rowDirection) ~= ROW_INDEX[orderIndex][string.sub(sector, 1, 1)]
                                or cellOf(point[other], columnDirection) ~= columns[sector] then
                                onGrid = false
                            end
                        end
                        if onGrid then exact[#exact + 1] = names end
                    end
                end
            end
        end
    end
    if #exact == 1 then return exact[1] end
    return #fits == 1 and fits[1] or nil
end

-- Classes whose names suggest an outpost, best first. NPCs stand on the ground, so their
-- positions are good teleport spots; safe zone volumes only mark the area.
local OUTPOST_KEYWORDS = { "banker", "trader", "outpost", "safezone" }
local NOT_IN_WORLD = { "widget", "button", "panel", "request", "response", "filter", "menu", "statics",
    "setup", "settings", "data", "registry", "tag", "atm", "ui", "category", "depot", "interface" }

local function outpostCandidates()
    local candidates = {}
    local classes = safe(function() return FindObjects(0, "Class", nil, 0, 0, false) end) or {}
    for _, class in pairs(classes) do
        local name = safe(function() return class:GetFName():ToString() end)
        local lowered = name and string.lower(name) or ""
        local keyword = nil
        for _, word in ipairs(OUTPOST_KEYWORDS) do
            if keyword == nil and string.find(lowered, word, 1, true) then keyword = word end
        end
        local excluded = string.find(lowered, "^default__") or string.find(lowered, "^skel_") or string.find(lowered, "^reinst_")
        for _, word in ipairs(NOT_IN_WORLD) do
            if string.find(lowered, word, 1, true) then excluded = true end
        end
        if keyword and not excluded then candidates[#candidates + 1] = { name = name, keyword = keyword } end
    end
    table.sort(candidates, function(a, b) return a.name < b.name end)
    return candidates
end

local function findOutposts()
    local found = {}   -- keyword -> list of { at, onGround }
    local report = {}
    for _, candidate in ipairs(outpostCandidates()) do
        local count = 0
        for _, actor in ipairs(findAll({ candidate.name })) do
            local at = locationOf(actor)
            if at then
                count = count + 1
                local onGround = candidate.keyword == "banker" or candidate.keyword == "trader"
                if onGround then
                    -- Stand a few metres in front of the NPC, not inside them.
                    local forward = safe(function() return actor:GetActorForwardVector() end)
                    local fx, fy = safe(function() return forward.X end), safe(function() return forward.Y end)
                    if type(fx) == "number" and type(fy) == "number" then
                        at.X, at.Y = at.X + fx * 250, at.Y + fy * 250
                    end
                    at.Z = at.Z + 20
                end
                found[candidate.keyword] = found[candidate.keyword] or {}
                table.insert(found[candidate.keyword], at)
            end
        end
        if count > 0 then report[#report + 1] = candidate.name .. ": " .. count end
    end

    local points, used = {}, nil
    for _, keyword in ipairs(OUTPOST_KEYWORDS) do
        local clusters = {}
        for _, at in ipairs(found[keyword] or {}) do
            local duplicate = false
            for _, point in ipairs(clusters) do
                if math.abs(point.X - at.X) < SAME_OUTPOST and math.abs(point.Y - at.Y) < SAME_OUTPOST then duplicate = true end
            end
            if not duplicate then clusters[#clusters + 1] = at end
        end
        if #clusters >= 2 and #clusters <= 8 then
            points, used = clusters, keyword
            break
        end
    end

    if #points == 0 then
        output("No outposts found. Outpost-like objects in the world: " .. (#report > 0 and table.concat(report, ", ") or "none")
            .. ". Traders may only exist while a player is near; try again with someone at an outpost, or use \"Add a place where a player stands\".")
        return
    end

    table.sort(points, function(a, b) return a.X < b.X end)
    local names = sectorNames(points)
    output(#points .. " outpost(s) found from " .. used .. " positions" .. (names and ", named by sector:" or " (names could not be matched to sectors):"))
    if used == "outpost" or used == "safezone" then
        output("These are the centres of the safe zones: teleport there once to check the height is right.")
    end
    for index, point in ipairs(points) do
        output(string.format("Outpost %s at %.0f %.0f %.0f", names and names[index] or ("outpost" .. index), point.X, point.Y, point.Z))
    end
end

-- ------------------------------------------------------------------ commands without an admin (opt-in; confirmed on a live server)
-- Every SCUM admin command is an object in the game instance's command registry and keeps
-- the lowest executor level allowed to run it (_requiredExecutorLevel, EExecutorStatus:
-- 0 Regular, 1 Admin, ...). For one command, on the game thread, the level is set to Regular,
-- the command is sent through an online player's own chat command channel, and the level is
-- put back at once. Chat from players is handled on this same thread, so nobody can slip a
-- command in while it is lowered. Only the commands below, which our mods use, are allowed.
-- Off unless no-admin-commands.txt exists in this mod's folder: delete it to turn this off.
-- The levels live only in memory, so a server restart always puts SCUM's own values back.
-- Lower-case verb -> SCUM's command class (the native AdminCommand_X and its Blueprint X_C).
local ELEVATED_COMMANDS = {
    changecurrencybalance = "ChangeCurrencyBalance", changefamepoints = "ChangeFamePoints",
    spawnitem = "SpawnItem", teleport = "Teleport",
}
local ELEVATED_SWITCH = "no-admin-commands.txt"
local REGULAR = 0
local GAME_INSTANCE_CLASSES = { "BP_ConZGameInstance_C", "ConZGameInstance", "GameInstance" }
local elevatedBroken = false

local function elevatedEnabled()
    if DIR == nil then return false end
    local file = io.open(DIR .. "/" .. ELEVATED_SWITCH, "r")
    if file == nil then return false end
    file:close()
    return true
end

-- Every object that can hold the command's level: the command's default object (new command
-- objects copy their values from it), any instances, and what the registry holds (objects, or
-- classes whose default object is used). Only objects whose level can be read are kept.
local function commandObjects(name)
    local className = ELEVATED_COMMANDS[name]
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
    local instance = findFirst(GAME_INSTANCE_CLASSES)
    local commands = instance and safe(function() return instance._adminCommandRegistry._commands end)
    if commands ~= nil then
        safe(function()
            commands:ForEach(function(_, element)
                local entry = element:get()
                local own = safe(function() return string.lower(entry:GetFName():ToString()) end)
                local classOf = safe(function() return string.lower(entry:GetClass():GetFName():ToString()) end)
                if own and wanted[own] then
                    add(safe(function() return entry:GetCDO() end)) -- the registry holds the class
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

-- Runs one whitelisted command as a regular player. Returns true when SCUM was asked.
local function runElevated(command, executor, quiet)
    local name = verb(command)
    if not ELEVATED_COMMANDS[name] then return false end
    if not elevatedEnabled() then
        if not quiet then
            output("Commands without an admin are off. Create " .. ELEVATED_SWITCH .. " in the ExclsvConsole mod folder to try them.")
        end
        return false
    end
    if elevatedBroken then
        output("Commands without an admin were switched off after a problem; restart the server to try again.")
        return false
    end
    if executor == nil then
        -- Any online player whose name can be read; AsPlayer picks one on purpose.
        for _, player in ipairs(players()) do
            if player.name ~= "?" then executor = player break end
        end
    end
    if executor == nil then
        output("Could not run " .. command .. " without an admin: no player is online to run it.")
        return false
    end
    local channel = channelOf(executor.controller)
    local targets = commandObjects(name)
    if channel == nil or #targets == 0 then
        output("Could not run " .. command .. " without an admin: "
            .. (channel == nil and ("no command channel for " .. executor.name) or ("SCUM's " .. ELEVATED_COMMANDS[name] .. " command was not found")) .. ".")
        return false
    end
    local levels, found = {}, {}
    for index, target in ipairs(targets) do
        levels[index] = safe(function() return target._requiredExecutorLevel end)
        found[index] = (safe(function() return target:GetFName():ToString() end) or "?") .. "=" .. tostring(levels[index])
    end

    local text = (string.gsub(command, "^#+", ""))
    -- SCUM writes the command to its admin log under the player's name; tell ExclsvAntiCheat (if
    -- installed) it was ours, so it does not kick them for running an admin command.
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
    local lowered = true
    for _, target in ipairs(targets) do
        if safe(function() target._requiredExecutorLevel = REGULAR return true end) ~= true then lowered = false end
    end
    local ok, err = false, "the admin level could not be changed"
    if lowered then
        ok, err = pcall(function() channel:Chat_Server_ProcessAdminCommand(text) end)
    end
    -- Put every level back, check them, and never use this route again if that fails.
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
        output("WARNING: could not restore the admin level of " .. ELEVATED_COMMANDS[name] .. ". Restart the server now so players cannot use it.")
    end

    if ok then
        output("Ran without an admin, as " .. executor.name .. ": " .. text .. " (command level "
            .. table.concat(found, ", ") .. ")")
    else
        output("Failed without an admin: " .. text .. " (" .. tostring(err) .. ")")
    end
    return ok
end

-- AsPlayer <name> <command>: runs a whitelisted command as that player without an admin.
-- SpawnItem and Teleport act on whoever runs them, so this is how to aim them at a player.
local function asPlayer(rest)
    local player, command = playerAndRest(rest, "Usage: AsPlayer <player> <command>")
    if player == nil then return end
    if not ELEVATED_COMMANDS[verb(command or "")] then
        output("AsPlayer only runs ChangeCurrencyBalance, ChangeFamePoints, SpawnItem and Teleport.")
        return
    end
    runElevated(command, player)
end

local function run(command)
    local name, rest = verb(command)

    if name == "findoutposts" then return findOutposts() end
    if name == "listitems" then return writeItemList(false) end

    if name == "whereis" then return whereIs(rest) end
    if name == "balance" then return balance(rest) end
    if name == "teleportplayer" then return teleportPlayer(rest) end
    if name == "finditem" then return findItems(rest) end
    if name == "giveitem" then return giveItem(rest) end
    if name == "asplayer" then return asPlayer(rest) end
    if name == "listplayers" then return listPlayers() end
    if name == "announce" then return announce(rest) end
    if name == "kick" and kick(rest) then return end

    local channel, admin = adminChannel()
    if channel ~= nil then
        -- The game client strips the "#" before sending a chat command to the server, so
        -- SCUM would read "#SetTime" as an unknown command.
        command = (string.gsub(command, "^#+", ""))
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
    if runElevated(command, nil, true) then return end
    -- SCUM only runs admin commands for an admin in game (its own test helper ignores them).
    local text = (string.gsub(command, "^#+", ""))
    local hint = ""
    if ELEVATED_COMMANDS[verb(text)] and not elevatedEnabled() then
        hint = " This one can also run without an admin: create " .. ELEVATED_SWITCH .. " in the ExclsvConsole mod folder."
    end
    output("No admin is online, so SCUM cannot run " .. text .. ". Join as an admin (AdminUsers.ini) and try again." .. hint)
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

-- The item list is written a minute after the world has loaded, then refreshed every 30 minutes
-- (new item types load as players meet them). Game objects are only touched on the game thread.
local ITEM_RESCAN = 30 * 60
local itemsWritten, itemTries, worldSeenAt, lastItemCheck, lastItemScan = false, 0, nil, nil, nil

-- For the panel's Console page, which can only read whole files: every 5 seconds the end of
-- SCUM.log goes into server.log (without SCUM's "Global Stats" lines), and status.txt gets
--   # updated <unix time>
--   <the newest Global Stats line: server frame times, FPS and counts>
-- Only files are touched here, never game objects.
local SERVER_LOG = DIR and (DIR .. "/../../../../../Saved/Logs/SCUM.log") or nil
local STATUS_FILE = DIR and (DIR .. "/status.txt") or nil
local SERVER_TAIL_FILE = DIR and (DIR .. "/server.log") or nil
local STATUS_EVERY, STATUS_READ_BYTES, STATUS_TAIL_LINES = 5, 64 * 1024, 120
local lastStatus, lastStatsLine, statusFailed = 0, nil, false

local function writeStatus(now)
    if SERVER_LOG == nil or now - lastStatus < STATUS_EVERY then return end
    lastStatus = now
    local log = io.open(SERVER_LOG, "rb")
    if log == nil then return end
    local size = log:seek("end") or 0
    local start = math.max(0, size - STATUS_READ_BYTES)
    log:seek("set", start)
    local data = log:read("a") or ""
    log:close()

    local lines = {}
    for line in string.gmatch(data, "([^\n]*)\n") do
        line = string.gsub(line, "\r$", "")
        if string.find(line, "Global Stats:", 1, true) then
            lastStatsLine = line
        elseif string.find(line, "%S") then
            lines[#lines + 1] = line
        end
    end
    if start > 0 and #lines > 0 then table.remove(lines, 1) end   -- the first line is cut off
    local first = math.max(1, #lines - STATUS_TAIL_LINES + 1)

    local tail = io.open(SERVER_TAIL_FILE, "w")
    if tail then
        tail:write(table.concat(lines, "\n", first, #lines) .. "\n")
        tail:close()
    end
    local status = io.open(STATUS_FILE, "w")
    if status then
        status:write(string.format("# updated %d\n%s\n", now, lastStatsLine or ""))
        status:close()
    end
end

every(1000, function()
    local now = os.time()
    local wrote, statusError = pcall(writeStatus, now)
    if not wrote and not statusFailed then
        statusFailed = true
        output("Writing status.txt failed: " .. tostring(statusError))
    end
    if itemsWritten and lastItemScan and now - lastItemScan >= ITEM_RESCAN then
        lastItemScan = now
        ExecuteInGameThread(function()
            local ok, err = pcall(writeItemList, true)
            if not ok then output("Refreshing the item list failed: " .. tostring(err)) end
        end)
    end
    if not itemsWritten and itemTries < 10 and (lastItemCheck == nil or now - lastItemCheck >= 10) then
        lastItemCheck = now
        ExecuteInGameThread(function()
            if worldSeenAt == nil and findFirst(GAME_MODE_CLASSES) then worldSeenAt = now end
            if worldSeenAt and now - worldSeenAt >= 60 + itemTries * 60 then
                itemTries = itemTries + 1
                -- Only report a failure on the last try; a list is reported whenever it is written.
                local ok, written = pcall(writeItemList, itemTries < 10)
                if not ok then output("Writing the item list failed: " .. tostring(written)) end
                itemsWritten = ok and written
                if itemsWritten then lastItemScan = now end
            end
        end)
    end

    local commands = takeCommands()
    for _, command in ipairs(commands) do
        ExecuteInGameThread(function()
            run(command)
        end)
    end
    return false
end)

output("Ready. Type SCUM admin commands in the Pelican console, e.g. ListPlayers or Announce Hello.")
