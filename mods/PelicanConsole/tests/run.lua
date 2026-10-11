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
function FindFirstOf(className)
    if worldAvailable and className == "World" then return world end
    if worldAvailable and className == "ConZGameMode" then return gameMode end
    return nil
end
local gameThreadRuns = 0
function ExecuteInGameThread(callback) gameThreadRuns = gameThreadRuns + 1; callback() end
local loopCallback, loopDelay
function LoopAsync(delay, callback) loopDelay, loopCallback = delay, callback end

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
check("ready message in console.log", string.find(consoleLog(), "[PelicanConsole] Ready.", 1, true) ~= nil)
check("ready message printed to UE4SS log", string.find(table.concat(log), "Ready.", 1, true) ~= nil)

-- Nothing queued: nothing runs and the loop keeps going.
check("loop keeps running", loopCallback() == false)
check("no commands, no calls", #calls == 0 and gameThreadRuns == 0)

-- No admin online: SCUM's test helper is the only route, and the console says so.
writeCommands("SetTime 12\n\n   \n##SetWeather 0\r\n")
loopCallback()
check("two commands run", #calls == 2)
check("prefix added", calls[1] and calls[1].command == "#SetTime 12")
check("repeated prefix collapsed, CR trimmed", calls[2] and calls[2].command == "#SetWeather 0")
check("world passed as context", calls[1] and calls[1].context == world)
check("run on the game thread", gameThreadRuns == 2)
check("queue file consumed", not exists("commands.txt") and not exists("commands.processing"))
check("no-admin warning", string.find(consoleLog(), "Sent #SetTime 12, but no admin is online", 1, true) ~= nil)
check("log lines timestamped", string.find(consoleLog(), "%d%d:%d%d:%d%d %[PelicanConsole%] Sent #SetTime 12") ~= nil)

loopCallback()
check("commands run once", #calls == 2)

-- Announce goes straight to every player's screen, admin or not.
writeCommands("Announce Hello world\n")
loopCallback()
check("announce uses the HUD message", hud[1] and hud[1].message == "Hello world" and hud[1].beep == false)
check("announce not sent through the test helper", #calls == 2)
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
check("command runs as the admin", rpc[1] and rpc[1].by == "Bob" and rpc[1].command == "#SetTime 6")
check("unknown kick target goes to SCUM", rpc[2] and rpc[2].command == "#Kick 76561198000000001")
check("not sent through the test helper", #calls == 2)
check("admin route logged", string.find(consoleLog(), "Ran as Bob: #SetTime 6", 1, true) ~= nil)
check("non-admin channel never used", rpc[3] == nil)

-- Admin online but their channel cannot be matched: falls back and says so.
bob.channel.owner = object()
writeCommands("SetTime 7\n")
loopCallback()
check("unmatched channel reported", string.find(consoleLog(), "Found admin Bob online but not their command channel", 1, true) ~= nil)
check("unmatched channel falls back", calls[3] and calls[3].command == "#SetTime 7")
bob.channel.owner = bob
online = {}

-- A leftover processing file (e.g. from a crash mid-read) must not block new commands.
writeCommands("Leftover\n", "commands.processing")
writeCommands("SetTime 1\n")
loopCallback()
check("new commands still run after leftover processing file", #calls == 4)

-- Game call throws: reported, not fatal.
processorFails = true
writeCommands("SetTime 2\n")
loopCallback()
check("failure reported", string.find(consoleLog(), "Failed: #SetTime 2 (", 1, true) ~= nil)
processorFails = false

-- World not loaded yet.
worldAvailable = false
writeCommands("SetTime 3\nAnnounce Hi\n")
loopCallback()
check("world missing reported", string.find(consoleLog(), "No admin is online, so SCUM cannot run #SetTime 3", 1, true) ~= nil)
check("announce without world reported", string.find(consoleLog(), "game world is not loaded yet", 1, true) ~= nil)
check("no call without a world", #calls == 4)
worldAvailable = true

-- Processor missing (game update renamed it).
processorValid = false
writeCommands("SetTime 4\n")
loopCallback()
check("no call without a processor", #calls == 4)
processorValid = true

-- Started from an unexpected path: disabled with a message instead of erroring.
log, loopCallback = {}, nil
local strayPath = tmp .. "/stray.lua"
assert(io.open(strayPath, "w")):write(source):close()
dofile(strayPath)
check("unknown folder disables the mod", loopCallback == nil)
check("unknown folder reported", string.find(table.concat(log), "Could not work out the mod folder", 1, true) ~= nil)

os.execute("rm -rf '" .. tmp .. "'")
io.stdout:write(string.format("\n%d checks, %d failed\n", count, failures))
os.exit(failures == 0 and 0 or 1)
