--[[
    PelicanConsole - runs SCUM admin commands typed into the Pelican console.

    The SCUM egg's start command appends each line typed in the Pelican console to
    ue4ss/Mods/PelicanConsole/commands.txt. This mod picks those lines up once a second
    and runs them through SCUM's own admin command processor
    (/Script/SCUM.MiscStatics:Test_ProcessAdminCommand), so no admin has to be online.

    Results and errors are written to ue4ss/Mods/PelicanConsole/console.log, which the
    egg shows in the Pelican console.
]]

-- Commands are sent the way they are typed in SCUM's chat: with a leading "#".
-- Typing "ListPlayers" or "#ListPlayers" in the console both become "#ListPlayers".
-- If SCUM ignores them, try setting this to "" (no prefix) and restart.
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

local function run(command)
    local processor = safe(function() return StaticFindObject(PROCESSOR_PATH) end)
    if not isValid(processor) then
        output("SCUM's admin command processor was not found. This SCUM version may have changed it.")
        return
    end

    local context = worldContext()
    if context == nil then
        output("The game world is not loaded yet. Try again once the server is online.")
        return
    end

    local ok, err = pcall(function()
        processor:Test_ProcessAdminCommand(context, command)
    end)

    if ok then
        output("Ran: " .. command)
    else
        output("Failed: " .. command .. " (" .. tostring(err) .. ")")
    end
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
