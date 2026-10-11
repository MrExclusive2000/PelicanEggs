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

    kickReason = "Kicked by anti-cheat. Contact an admin if this is a mistake.",
}
