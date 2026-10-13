--[[
    Runs main.lua against a fake UE4SS runtime. Run from the repo root:
        lua5.4 mods/PelicanConsole/tests/run.lua
]]

local failures, count = 0, 0
local function check(name, condition)
    count = count + 1
    if not condition then
        failures = failures + 1
        io.stdout:write("FAIL: " .. name .. "\n")
    end
end

-- ------------------------------------------------------------------ fake UE4SS runtime
local calls = {}
local processorValid, worldAvailable, processorFails = true, true, false

local processor = {
    IsValid = function() return processorValid end,
    Test_ProcessAdminCommand = function(_, context, command)
        if processorFails then error("access violation") end
        calls[#calls + 1] = { context = context, command = command }
    end,
}
local world = { IsValid = function() return true end, name = "World" }

local log = {}
function print(text) log[#log + 1] = text end
function StaticFindObject(path)
    if path == "/Script/SCUM.Default__MiscStatics" then return processor end
    return { IsValid = function() return false end }
end
local function object(fields)
    local o = fields or {}
    o.valid = true
    function o:IsValid() return self.valid end
    function o:GetAddress() return self end
    return o
end

local hud, kicks, rpc = {}, {}, {}
local gameMode = object({ name = "GameMode" })
function gameMode:SendHUDMessageToAll(message, beep) hud[#hud + 1] = { message = message, beep = beep } end
function gameMode:KickPlayer(controller, reason) kicks[#kicks + 1] = { controller = controller, reason = reason } return true end

local function Player(name, admin)
    local controller = object({ name = name, admin = admin })
    controller.PlayerState = { GetPlayerName = function() return { ToString = function() return controller.name end } end }
    function controller:IsUserAdmin() return self.admin end
    local channel = object({ owner = controller })
    function channel:GetOwner() return self.owner end
    function channel:Chat_Server_ProcessAdminCommand(command) rpc[#rpc + 1] = { by = controller.name, command = command } end
    controller.channel = channel
    return controller
end

local online = {}
function FindAllOf(className)
    if className == "ConZPlayerController" then return online end
    if className == "PlayerRpcChannel" then
        local channels = {}
        for _, controller in ipairs(online) do channels[#channels + 1] = controller.channel end
        return channels
    end
    return nil
end
-- UE4SS FindObjects: object searches must leave out objects still loading or being destroyed.
function FindObjects(count, className, name, required, banned, exact)
    if className == "Class" then return {} end
    local unsafe = 0x400 | 0x1000 | 0x8000 | 0x10000
    assert(banned & unsafe == unsafe, "object searches must leave out objects being destroyed")
    if banned & (0x10 | 0x20) == 0 then templateSearches = (templateSearches or 0) + 1 end
    liveSearches = (liveSearches or 0) + 1
    return FindAllOf(className) or {}
end
function FindFirstOf(className)
    if worldAvailable and className == "World" then return world end
    if worldAvailable and className == "ConZGameMode" then return gameMode end
    return nil
end
local gameThreadRuns = 0
function ExecuteInGameThread(callback) gameThreadRuns = gameThreadRuns + 1; callback() end
local loopCallback, loopDelay
-- UE4SS game-thread timer; LoopAsync would run Lua on a background thread.
function LoopAsync() error("timers must run on the game thread (LoopInGameThreadWithDelay)") end
function LoopInGameThreadWithDelay(delay, callback) loopDelay, loopCallback = delay, callback end

-- Run a temp copy of the mod so the real folder is untouched.
local tmp = os.tmpname()
os.remove(tmp)
local dir = tmp .. "/PelicanConsole"
os.execute("mkdir -p '" .. dir .. "/Scripts'")
local source = assert(io.open("mods/PelicanConsole/Scripts/main.lua")):read("a")
local copy = dir .. "/Scripts/main.lua"
assert(io.open(copy, "w")):write(source):close()

local function writeCommands(text, file)
    assert(io.open(dir .. "/" .. (file or "commands.txt"), "a")):write(text):close()
end
local function exists(file)
    local handle = io.open(dir .. "/" .. file)
    if handle then handle:close() return true end
    return false
end
local function consoleLog()
    local handle = io.open(dir .. "/console.log")
    if not handle then return "" end
    local text = handle:read("a")
    handle:close()
    return text
end

-- Commands left over from before the start must be dropped, not run.
writeCommands("ShutdownServer\n")
writeCommands("Stale\n", "commands.processing")

dofile(copy)

check("loop registered every second", loopDelay == 1000 and loopCallback ~= nil)
check("stale commands.txt removed at startup", not exists("commands.txt"))
check("stale commands.processing removed at startup", not exists("commands.processing"))
check("ready message in console.log", string.find(consoleLog(), "[ExclsvConsole] Ready.", 1, true) ~= nil)
check("ready message printed to UE4SS log", string.find(table.concat(log), "Ready.", 1, true) ~= nil)

-- Nothing queued: nothing runs and the loop keeps going.
check("loop keeps running", loopCallback() == false)
check("no commands, nothing run", gameThreadRuns == 1)   -- the item list check only

-- No admin online: SCUM only runs admin commands for an admin in game, so the console says so.
-- SCUM's own test helper (which it ignores) is never used.
writeCommands("SetTime 12\n\n   \n##SetWeather 0\r\n")
loopCallback()
check("needs an admin, said once per command", string.find(consoleLog(), "No admin is online, so SCUM cannot run SetTime 12.", 1, true) ~= nil
    and string.find(consoleLog(), "No admin is online, so SCUM cannot run SetWeather 0.", 1, true) ~= nil)
check("repeated # dropped, CR trimmed, run on the game thread", gameThreadRuns == 3)   -- two commands plus the item list check
check("queue file consumed", not exists("commands.txt") and not exists("commands.processing"))
check("log lines timestamped", string.find(consoleLog(), "%d%d:%d%d:%d%d %[ExclsvConsole%] No admin is online") ~= nil)
check("SCUM's ignored test helper is never used", #calls == 0)
writeCommands("ChangeCurrencyBalance Normal 1 76561198000000001\n")
loopCallback()
check("money commands point to the no-admin switch", string.find(consoleLog(), "This one can also run without an admin: create no-admin-commands.txt", 1, true) ~= nil)

-- Announce goes straight to every player's screen, admin or not.
writeCommands("Announce Hello world\n")
loopCallback()
check("announce uses the HUD message", hud[1] and hud[1].message == "Hello world" and hud[1].beep == false)
check("announce logged", string.find(consoleLog(), "Announced: Hello world", 1, true) ~= nil)
writeCommands("#announce\n")
loopCallback()
check("empty announce explained", string.find(consoleLog(), "Usage: Announce <message>", 1, true) ~= nil and #hud == 1)

-- ListPlayers is answered in the console.
writeCommands("ListPlayers\n")
loopCallback()
check("empty server listed", string.find(consoleLog(), "No players online.", 1, true) ~= nil)
local alice, bob = Player("Alice", false), Player("Bob", true)
online = { alice, bob }
writeCommands("ListPlayers\n")
loopCallback()
local text = consoleLog()
check("player count", string.find(text, "2 player(s) online:", 1, true) ~= nil)
check("players and admin flag", string.find(text, "  Alice\n", 1, true) ~= nil and string.find(text, "  Bob (admin)", 1, true) ~= nil)

-- Kick by name uses the game mode; ambiguous or unknown names do not.
writeCommands("Kick alice\n")
loopCallback()
check("kick by name", kicks[1] and kicks[1].controller == alice)
check("kick logged", string.find(consoleLog(), "Kicked Alice.", 1, true) ~= nil)

-- With an admin online, other commands run through that admin's chat command channel.
writeCommands("SetTime 6\nKick 76561198000000001\n")
loopCallback()
check("command runs as the admin", rpc[1] and rpc[1].by == "Bob" and rpc[1].command == "SetTime 6")
check("unknown kick target goes to SCUM", rpc[2] and rpc[2].command == "Kick 76561198000000001")
check("admin route logged", string.find(consoleLog(), "Ran as Bob: SetTime 6", 1, true) ~= nil)
check("non-admin channel never used", rpc[3] == nil)

-- Admin online but their channel cannot be matched: says so, and the command is not run.
bob.channel.owner = object()
writeCommands("SetTime 7\n")
loopCallback()
check("unmatched channel reported", string.find(consoleLog(), "Found admin Bob online but not their command channel", 1, true) ~= nil
    and string.find(consoleLog(), "SCUM cannot run SetTime 7.", 1, true) ~= nil)
bob.channel.owner = bob

-- The admin's channel throws: reported, not fatal.
local workingChannel = bob.channel.Chat_Server_ProcessAdminCommand
function bob.channel:Chat_Server_ProcessAdminCommand() error("access violation") end
writeCommands("SetTime 2\n")
loopCallback()
check("failure reported", string.find(consoleLog(), "Failed: SetTime 2 (", 1, true) ~= nil)
bob.channel.Chat_Server_ProcessAdminCommand = workingChannel
online = {}

-- A leftover processing file (e.g. from a crash mid-read) must not block new commands.
writeCommands("Leftover\n", "commands.processing")
writeCommands("SetTime 1\n")
loopCallback()
check("new commands still run after leftover processing file", string.find(consoleLog(), "SCUM cannot run SetTime 1.", 1, true) ~= nil)

-- World not loaded yet: announce says so.
worldAvailable = false
writeCommands("Announce Hi\n")
loopCallback()
check("announce without world reported", string.find(consoleLog(), "game world is not loaded yet", 1, true) ~= nil)
worldAvailable = true

-- ------------------------------------------------------------------ experimental commands
local spawned, teleports = {}, {}
local function ExpPlayer(name)
    local controller = Player(name, false)
    local pawn = object({ x = 100, y = 200, z = 300, items = {} })
    function pawn:K2_GetActorLocation() return { X = self.x, Y = self.y, Z = self.z } end
    function pawn:K2_TeleportTo(location, rotation) teleports[#teleports + 1] = { who = name, at = location } return true end
    function pawn:PlaceItemInInventoryOrHolster(item) if item.fits then self.items[item] = true end end
    function pawn:HasItem(item) return self.items[item] == true end
    controller.pawn = pawn
    function controller:K2_GetPawn() return self.pawn end
    function controller:GetCurrencyBalanceText() error("GetCurrencyBalanceText crashed a live server and must not be called") end
    controller._moneyBalanceRep, controller._goldBalanceRep, controller._repFamePoints = 1250, 3, 42
    return controller
end
local waterClass = object({ name = "BP_Water_05l_C" })
function waterClass:GetFName() return { ToString = function() return "BP_Water_05l_C" end } end
function waterClass:GetFullName() return "BlueprintGeneratedClass /Game/ConZ_Files/Items/Water/BP_Water_05l.BP_Water_05l_C" end
local otherClass = object()
function otherClass:GetFName() return { ToString = function() return "BP_Weapon_AK47_C" end } end
function otherClass:GetFullName() return "BlueprintGeneratedClass /Game/ConZ_Files/Weapons/BP_Weapon_AK47.BP_Weapon_AK47_C" end
function FindObject(className, name)
    assert(className == "BlueprintGeneratedClass")
    if name == "BP_Water_05l_C" then return waterClass end
    return nil
end
local liveFindObjects = FindObjects
function FindObjects(count, className, ...) if className ~= "Class" then return liveFindObjects(count, className, ...) end return { waterClass, otherClass } end
local statics = object()
local fits = true
function statics:BeginDeferredActorSpawnFromClass(w, class, transform, collision)
    assert(collision == 1)
    local actor = object({ fits = fits })
    spawned[#spawned + 1] = { actor = actor, at = transform.Translation }
    return actor
end
function statics:FinishSpawningActor(actor) actor.finished = true end
local oldStatic = StaticFindObject
function StaticFindObject(path)
    if path == "/Script/Engine.Default__GameplayStatics" then return statics end
    return oldStatic(path)
end
local function lastLine() local lines = {} for line in consoleLog():gmatch("[^\n]+") do lines[#lines + 1] = line end return lines[#lines] or "" end

local mr = ExpPlayer("Mr Exclusive")
online = { mr, ExpPlayer("Bob") }
writeCommands("WhereIs mr exclusive\n")
loopCallback()
check("whereis", string.find(consoleLog(), "Mr Exclusive is at 100 200 300", 1, true) ~= nil)
writeCommands("Balance Bob\n")
loopCallback()
check("balance", string.find(consoleLog(), "Bob: money 1250, gold 3, fame 42", 1, true) ~= nil)
writeCommands("TeleportPlayer Mr Exclusive 1 -2 3.5\n")
loopCallback()
check("teleport", teleports[1] and teleports[1].who == "Mr Exclusive" and teleports[1].at.Y == -2 and teleports[1].at.Z == 3.5)
writeCommands("TeleportPlayer Bob\n")
loopCallback()
check("teleport usage", string.find(lastLine(), "Usage: TeleportPlayer", 1, true) ~= nil and #teleports == 1)
writeCommands("FindItem water\n")
loopCallback()
check("find item", string.find(consoleLog(), "1 item(s) match \"water\":", 1, true) ~= nil and string.find(consoleLog(), "  BP_Water_05l_C", 1, true) ~= nil)
writeCommands("GiveItem Mr Exclusive Water_05l 2\n")
loopCallback()
check("give item spawned at the player", #spawned == 2 and spawned[1].at.Z == 350 and spawned[1].actor.finished)
check("give item into the inventory", string.find(consoleLog(), "Gave Mr Exclusive 2 x BP_Water_05l_C: 2 in their inventory, 0 at their feet.", 1, true) ~= nil)
fits = false
writeCommands("GiveItem Bob Water_05l\n")
loopCallback()
check("give item falls back to the ground", string.find(consoleLog(), "Gave Bob 1 x BP_Water_05l_C: 0 in their inventory, 1 at their feet.", 1, true) ~= nil)
writeCommands("GiveItem Bob Nothing\n")
loopCallback()
check("unknown item", string.find(lastLine(), "Item Nothing has not been loaded on this server yet. Spawn one once with SpawnItem Nothing", 1, true) ~= nil)
writeCommands("Balance Nobody\n")
loopCallback()
check("unknown player", string.find(lastLine(), "No online player matches \"Nobody\"", 1, true) ~= nil)
online = {}


-- Outposts: found by searching loaded classes for traders, bankers and safe zones.
local function Banker(x, y)
    local banker = object({ x = x, y = y })
    function banker:K2_GetActorLocation() return { X = self.x, Y = self.y, Z = 1000 } end
    function banker:GetActorForwardVector() return { X = 1, Y = 0, Z = 0 } end
    return banker
end
local function NamedClass(name) local c = object() function c:GetFName() return { ToString = function() return name end } end return c end
local classList = { NamedClass("BP_Banker_Outpost_C"), NamedClass("BankATMWidget"), NamedClass("TraderFilterFamePointsButton"),
    NamedClass("BP_SafeZone_C"), NamedClass("Default__BP_Banker_Outpost_C") }
local savedFindObjects = FindObjects
function FindObjects(count, className, ...) if className ~= "Class" then return liveFindObjects(count, className, ...) end return classList end
-- Rows along -Y (A at the top), columns along +X: A0 (0, 900), B4 (4, 600), C2 (2, 300), Z3 (3, -300), in km-ish units.
local bankers = { Banker(0, 900000), Banker(400000, 600000), Banker(200000, 300000), Banker(300000, -300000), Banker(300100, -300100) }
local zones = {}
local oldFindAll = FindAllOf
local asked = {}
function FindAllOf(className)
    asked[className] = true
    if className == "BP_Banker_Outpost_C" then return bankers end
    if className == "BP_SafeZone_C" then return zones end
    return oldFindAll(className)
end
writeCommands("FindOutposts\n")
loopCallback()
check("UI classes are not searched", not asked.BankATMWidget and not asked.TraderFilterFamePointsButton)
check("outposts found from bankers and de-duplicated", string.find(consoleLog(), "4 outpost(s) found from banker positions, named by sector:", 1, true) ~= nil)
check("outposts named by sector, in front of the banker", string.find(consoleLog(), "Outpost a0 at 250 900000 1020", 1, true) ~= nil
    and string.find(consoleLog(), "Outpost b4 at 400250 600000 1020", 1, true) ~= nil
    and string.find(consoleLog(), "Outpost c2 at 200250 300000 1020", 1, true) ~= nil
    and string.find(consoleLog(), "Outpost z3 at 300250 -300000 1020", 1, true) ~= nil)
-- Traders found on a live server: rows Z, A, B, C along +Y, columns along +X.
bankers = { Banker(-628501, -564653), Banker(-157342, 289458), Banker(17828, -675066), Banker(571094, -229415) }
writeCommands("FindOutposts\n")
loopCallback()
check("live outposts named with the Z row before A", string.find(consoleLog(), "Outpost a0 at -628251 -564653 1020", 1, true) ~= nil
    and string.find(consoleLog(), "Outpost c2 at -157092 289458 1020", 1, true) ~= nil
    and string.find(consoleLog(), "Outpost z3 at 18078 -675066 1020", 1, true) ~= nil
    and string.find(consoleLog(), "Outpost b4 at 571344 -229415 1020", 1, true) ~= nil)
-- No bankers loaded: safe zones are used instead, with a warning about the height.
bankers = {}
zones = { Banker(0, 0), Banker(500000, 0) }
writeCommands("FindOutposts\n")
loopCallback()
check("safe zones as a fallback", string.find(consoleLog(), "2 outpost(s) found from safezone positions", 1, true) ~= nil
    and string.find(consoleLog(), "centres of the safe zones", 1, true) ~= nil
    and string.find(consoleLog(), "Outpost outpost2 at 500000 0 1000", 1, true) ~= nil)
zones = {}
writeCommands("FindOutposts\n")
loopCallback()
check("nothing found explains what exists", string.find(consoleLog(), "No outposts found. Outpost-like objects in the world: none.", 1, true) ~= nil)
FindAllOf = oldFindAll
FindObjects = savedFindObjects


-- Item list for SCUM Manager's dropdowns: classes deriving from SCUM's Item, or (when UE4SS
-- cannot read parents) classes in /Game/ConZ_Files/Items/.
local itemBase = object()
function itemBase:GetFName() return { ToString = function() return "Item" end } end
local function Class(name, super, path)
    local class = object()
    function class:GetFName() return { ToString = function() return name end } end
    function class:GetFullName() return "BlueprintGeneratedClass " .. (path or "/Game/Other/") .. name end
    if super ~= false then function class:GetSuperStruct() return super end end
    return class
end
local foodBase = Class("FoodItem", itemBase)
local loadedClasses = { Class("BP_Water_05l_C", foodBase), Class("BP_Weapon_AK47_C", Class("WeaponItem", itemBase)),
    Class("BP_Door_C", Class("Actor", nil)), Class("SKEL_BP_Apple_C", foodBase) }
function FindObjects(count, className, ...) if className ~= "Class" then return liveFindObjects(count, className, ...) end return loadedClasses end
writeCommands("ListItems\n")
loopCallback()
local function itemsFile() local f = io.open(dir .. "/items.txt") local t = f and f:read("a") or "" if f then f:close() end return t end
-- Water was already seen by the FindItem test above; the AK47 is new.
check("item list written", string.find(consoleLog(), "Item list: 2 items known, 2 loaded right now (1 new). 4 classes checked (2 by parent class, 0 by folder).", 1, true) ~= nil)
check("item list contents with paths", itemsFile() == "BP_Water_05l_C\t/Game/Other/BP_Water_05l_C\nBP_Weapon_AK47_C\t/Game/Other/BP_Weapon_AK47_C\n")
-- Without GetSuperStruct: items are recognised by their folder.
loadedClasses = { Class("Christmas_Headband_01_ES_C", false, "/Game/ConZ_Files/Items/Clothes/"),
    Class("BP_SphereMotionTriggerComponent_C", false, "/Game/ConZ_Files/Items/Traps/"), Class("BP_Door_C", false) }
writeCommands("ListItems\n")
loopCallback()
check("items found by folder, list keeps earlier items", string.find(consoleLog(), "Item list: 3 items known, 1 loaded right now (1 new). 3 classes checked (0 by parent class, 1 by folder).", 1, true) ~= nil
    and string.find(itemsFile(), "Christmas_Headband_01_ES_C\t/Game/ConZ_Files/Items/Clothes/Christmas_Headband_01_ES_C\n", 1, true) ~= nil
    and string.find(itemsFile(), "BP_Weapon_AK47_C\t", 1, true) ~= nil)
writeCommands("FindItem headband\n")
loopCallback()
check("find item uses the scan", string.find(consoleLog(), "1 item(s) match \"headband\":", 1, true) ~= nil)
-- Nothing loaded right now: the known list stays, and an item not in memory is loaded from its path.
loadedClasses = {}
writeCommands("ListItems\n")
loopCallback()
check("known items survive a scan that sees none", string.find(consoleLog(), "Item list: 3 items known, 0 loaded right now (0 new).", 1, true) ~= nil)
local loadedPaths = {}
function LoadAsset(path)
    loadedPaths[#loadedPaths + 1] = path
    if path == "/Game/ConZ_Files/Items/Clothes/Christmas_Headband_01_ES_C" then return Class("Christmas_Headband_01_ES_C", false) end
end
online = { ExpPlayer("Bob") }
writeCommands("GiveItem Bob Christmas_Headband_01_ES\n")
loopCallback()
check("item not in memory is loaded from its path", loadedPaths[1] == "/Game/ConZ_Files/Items/Clothes/Christmas_Headband_01_ES_C"
    and string.find(consoleLog(), "Gave Bob 1 x Christmas_Headband_01_ES_C", 1, true) ~= nil)
-- A class seen by an earlier scan may have been unloaded since: it is looked up again by path,
-- never touched through the old object.
local unloaded = Class("BP_Unloaded_C", itemBase, "/Game/ConZ_Files/Items/")
loadedClasses = { unloaded }
writeCommands("ListItems\n")
loopCallback()
local touchedUnloaded = false
function unloaded:IsValid() touchedUnloaded = true error("freed memory") end
function unloaded:GetFName() touchedUnloaded = true error("freed memory") end
loadedClasses = {}
writeCommands("GiveItem Bob BP_Unloaded_C\n")
loopCallback()
check("unloaded item class not touched", not touchedUnloaded)
online = {}

-- ------------------------------------------------------------------ commands without an admin
-- SCUM's command registry: each command object keeps the lowest level allowed to run it.
local function RegistryCommand(className, level)
    local command = object({ _requiredExecutorLevel = level })
    function command:GetClass() return { GetFName = function() return { ToString = function() return className end } end } end
    return command
end
local currency = RegistryCommand("AdminCommand_ChangeCurrencyBalance", 1)
local godMode = RegistryCommand("AdminCommand_SetGodMode", 1)
local registryList = { godMode, currency }
local gameInstance = object({ _adminCommandRegistry = { _commands = {
    ForEach = function(_, callback)
        for index, command in ipairs(registryList) do callback(index, { get = function() return command end }) end
    end,
} } })
local findFirstBefore = FindFirstOf
function FindFirstOf(className)
    if className == "ConZGameInstance" then return gameInstance end
    return findFirstBefore(className)
end
local levelsSeen = {}
local regular = Player("Bob", false)
function regular.channel:Chat_Server_ProcessAdminCommand(command)
    rpc[#rpc + 1] = { by = "Bob", command = command }
    levelsSeen[#levelsSeen + 1] = currency._requiredExecutorLevel
end
online = { regular }
for key in pairs(rpc) do rpc[key] = nil end
calls = {}

writeCommands("AsPlayer Bob ChangeCurrencyBalance Normal 1 76561198000000001\n")
loopCallback()
check("off without the switch file", #rpc == 0 and currency._requiredExecutorLevel == 1
    and string.find(consoleLog(), "Commands without an admin are off. Create no-admin-commands.txt", 1, true) ~= nil)

assert(io.open(dir .. "/no-admin-commands.txt", "w")):close()
writeCommands("AsPlayer Bob ChangeCurrencyBalance Normal 1 76561198000000001\n")
loopCallback()
check("run through the player's own channel, without the #", rpc[1] and rpc[1].by == "Bob" and rpc[1].command == "ChangeCurrencyBalance Normal 1 76561198000000001")
check("level lowered only while the command runs", levelsSeen[1] == 0 and currency._requiredExecutorLevel == 1)
check("other commands untouched", godMode._requiredExecutorLevel == 1)
check("reported as experimental", string.find(consoleLog(), "Ran without an admin, as Bob: ChangeCurrencyBalance Normal 1", 1, true) ~= nil)

writeCommands("ChangeCurrencyBalance Normal 5 76561198000000001\n")
loopCallback()
check("used automatically when no admin is online", rpc[2] and rpc[2].command == "ChangeCurrencyBalance Normal 5 76561198000000001"
    and #calls == 0 and currency._requiredExecutorLevel == 1)

writeCommands("AsPlayer Bob SetGodMode 1\nSetGodMode 1\n")
loopCallback()
check("only whitelisted commands", #rpc == 2 and godMode._requiredExecutorLevel == 1
    and string.find(consoleLog(), "AsPlayer only runs ChangeCurrencyBalance", 1, true) ~= nil)
check("other commands need an admin", string.find(consoleLog(), "SCUM cannot run SetGodMode 1.", 1, true) ~= nil and #calls == 0)

-- SCUM's registry holds command classes: the class's default object (found by the safe search
-- and through the class) is what gets lowered, once, and put back.
local cdo = RegistryCommand("Default__ChangeCurrencyBalance_C", 1)
local cdoLevels = {}
function regular.channel:Chat_Server_ProcessAdminCommand(command)
    rpc[#rpc + 1] = { by = "Bob", command = command }
    cdoLevels[#cdoLevels + 1] = cdo._requiredExecutorLevel
end
local blueprintClass = object()
function blueprintClass:GetFName() return { ToString = function() return "ChangeCurrencyBalance_C" end } end
function blueprintClass:GetCDO() return cdo end
registryList = { blueprintClass }
local findAllBefore = FindAllOf
function FindAllOf(className)
    if className == "ChangeCurrencyBalance_C" then return { cdo } end
    return findAllBefore(className)
end
writeCommands("ChangeCurrencyBalance Normal 2 76561198000000001\n")
loopCallback()
check("default object of a registry class lowered while it runs", cdoLevels[1] == 0 and cdo._requiredExecutorLevel == 1 and #rpc == 3
    and string.find(consoleLog(), "command level ?=1", 1, true) ~= nil)
FindAllOf = findAllBefore
function regular.channel:Chat_Server_ProcessAdminCommand(command) rpc[#rpc + 1] = { by = "Bob", command = command } end

-- The level cannot be put back: warn, and never use the route again.
local stuckLevel = 1
local stuck = setmetatable({}, {
    __index = function(_, k) if k == "_requiredExecutorLevel" then return stuckLevel end return currency[k] end,
    __newindex = function(t, k, v)
        if k ~= "_requiredExecutorLevel" then return rawset(t, k, v) end
        if v ~= 0 then error("write failed") end
        stuckLevel = v
    end,
})
function stuck:GetClass() return currency:GetClass() end
registryList = { stuck }
writeCommands("ChangeCurrencyBalance Normal 1 76561198000000001\n")
loopCallback()
check("failed restore is reported", string.find(consoleLog(), "WARNING: could not restore the admin level of ChangeCurrencyBalance", 1, true) ~= nil)
writeCommands("ChangeCurrencyBalance Normal 1 76561198000000001\n")
loopCallback()
check("route switched off after a failed restore", #rpc == 4
    and string.find(consoleLog(), "switched off after a problem", 1, true) ~= nil)

os.remove(dir .. "/no-admin-commands.txt")
FindFirstOf = findFirstBefore
online = {}

-- Started from an unexpected path: disabled with a message instead of erroring.
log, loopCallback = {}, nil
local strayPath = tmp .. "/stray.lua"
assert(io.open(strayPath, "w")):write(source):close()
dofile(strayPath)
check("unknown folder disables the mod", loopCallback == nil)
check("unknown folder reported", string.find(table.concat(log), "Could not work out the mod folder", 1, true) ~= nil)

os.execute("rm -rf '" .. tmp .. "'")
check("player searches leave out objects being destroyed (FindObjects, not FindAllOf)", (liveSearches or 0) > 0)
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
