-- ScumAntiCheat settings. Edit, then restart the server.
-- Distances are in metres, speeds in metres per second (1 m/s = 3.6 km/h).
return {
    -- What happens when a player reaches strikesToAct (or trips an instant check):
    --   "log"  - only report it (start here for a few days and read anticheat.log)
    --   "kick" - kick the player
    --   "ban"  - add the player's SteamID to BannedUsers.ini and kick them
    action = "log",

    -- With action = "kick": ban a player once they have been kicked this many times
    -- (counted across restarts in offenses.txt). 0 = never ban automatically.
    banAfterKicks = 3,

    -- How many violations within strikeWindowSeconds trigger the action.
    strikesToAct = 3,
    strikeWindowSeconds = 60,

    -- Turn individual checks on or off.
    checks = {
        speed = true,             -- faster than maxFootSpeed / maxVehicleSpeed
        teleport = true,          -- jumping teleportDistance or more between two checks
        flying = true,            -- in flying movement mode for flyingSeconds (fly hack)
        hovering = true,          -- in the air without falling for hoverSeconds (hover / airwalk)
        mapBounds = true,         -- outside the map or below mapBounds.minZ (noclip, under-map)
        unauthorizedAdmin = true, -- has admin rights but is not in AdminUsers.ini (instant)
        names = true,             -- name contains one of blockedNames (impersonation, instant)
        watchlist = true,         -- announce when a watchlisted SteamID joins
        gameLogs = true,          -- show SCUM's own violation and admin command logs in the console
        killLog = true,           -- aimbot signs in SCUM's kill log (range, god mode, desync, kill rate)
        aimSnap = true,           -- aim jumping onto targets right before kills
    },

    -- Speed limits. Sprinting is about 7 m/s; the fastest vehicles stay well under 100.
    maxFootSpeed = 15,
    maxVehicleSpeed = 120,

    -- A jump of at least this many metres between two checks counts as a teleport.
    teleportDistance = 300,

    -- Ladders can use flying mode briefly, so only longer stretches count.
    flyingSeconds = 10,
    -- Jumps and falls end within seconds; parachutes keep descending.
    hoverSeconds = 8,

    -- The playable island, from SCUM's own map bounds. minZ is how deep a player may be.
    mapBounds = { minX = -9548, maxX = 6692, minY = -9548, maxY = 6692, minZ = -300 },

    -- Real admins (listed in AdminUsers.ini) are never checked. Neither are these.
    ignoreAdmins = true,
    ignoreNames = {
        -- "SomePlayerName",
    },
    ignoreSteamIds = {
        -- "76561198000000000",
    },

    -- Player names containing any of these (any case) are flagged. Real admins are exempt.
    blockedNames = { "admin", "moderator", "owner", "[staff]" },

    -- SteamIDs to keep an eye on: the console says when they join.
    watchlist = {
        -- "76561198000000000",
    },

    -- With checks.gameLogs: also count each SCUM violation-log entry as a strike for that player.
    strikeOnGameViolations = false,

    -- ------------------------------------------------------------ aimbot detection
    -- These checks report "SUSPECT" lines for you to look into. Good players can trip them
    -- now and then; a cheater trips them again and again. Spectate before you ban.

    -- Longest believable kill with a firearm, and with melee (melee further away = kill aura).
    maxKillDistance = 800,
    maxMeleeDistance = 8,
    -- Shorter limits for weapons whose name contains the given text (any case).
    weaponMaxDistance = {
        { "bow", 150 },          -- bows and crossbows
        { "1911", 150 }, { "deagle", 150 }, { "m9", 150 }, { "revolver", 150 },
        { "pistol", 150 }, { "tec01", 150 }, { "glock", 150 },
    },

    -- This many kills within killRateMinutes is suspicious.
    killRateKills = 8,
    killRateMinutes = 5,

    -- The killer's position on their own PC vs on the server, in metres. A big gap means
    -- they killed from somewhere the server never saw them (teleport/desync kills).
    maxLocationMismatch = 50,

    -- Aim turning at least this many degrees within a tenth of a second counts as a snap.
    -- Report a player once this many of their kills (and at least half of them) had a snap
    -- just before.
    aimSnapDegrees = 150,
    aimSnapPattern = 3,

    -- Also count aimbot suspicions as strikes (so they can lead to a kick/ban). Off by default.
    strikeOnKillFlags = false,

    kickReason = "Kicked by anti-cheat. Contact an admin if this is a mistake.",
}
