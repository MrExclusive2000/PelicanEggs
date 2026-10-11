-- ScumAntiCheat settings. Edit, then restart the server.
-- Speeds are in metres per second (1 m/s = 3.6 km/h).
return {
    -- "log": only report suspects. "kick": kick them once they reach strikesToAct.
    -- Run on "log" for a few days first and check nothing legitimate gets flagged.
    action = "log",

    -- How many violations within strikeWindowSeconds trigger the action.
    strikesToAct = 3,
    strikeWindowSeconds = 60,

    -- Horizontal speed limits. Sprinting is about 7 m/s; the fastest vehicles stay well under 100.
    maxFootSpeed = 15,
    maxVehicleSpeed = 120,

    -- A jump of at least this many metres between two checks counts as a teleport.
    teleportDistance = 300,

    -- Admins (AdminUsers.ini) are never checked. Players listed here aren't either.
    ignoreAdmins = true,
    ignoreNames = {
        -- "SomePlayerName",
    },

    kickReason = "Kicked by anti-cheat (movement). Contact an admin if this is a mistake.",
}
