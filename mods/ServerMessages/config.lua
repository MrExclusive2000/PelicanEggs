-- ServerMessages settings. Edit here or on the SCUM Manager "SCUM Mod Settings" page.
-- Changes are picked up within 30 seconds; no restart needed.
-- {name} is replaced with the player's name, {players} with the number of players online.
return {
    -- Shown only to the player, a few seconds after their character spawns. "" turns it off.
    welcome = "Welcome to the server, {name}! Be fair, have fun.",

    -- Announce joins to everyone. "" turns it off.
    joinAnnouncement = "",

    -- Rotating announcements to everyone, one every intervalMinutes. Empty list turns them off.
    intervalMinutes = 30,
    announcements = {
        "Server rules: no cheating, no exploiting, respect other players.",
        -- "Join our Discord: discord.gg/yourinvite",
    },

    -- Skip announcements while the server is empty.
    onlyWhenPlayersOnline = true,

    -- Write joins and leaves to the Pelican console and players.log.
    logJoinsAndLeaves = true,

    -- Daily restart times, "HH:MM" in UTC. Countdown announcements go out the given number of
    -- minutes before each. The restart itself is a Pelican schedule (Schedules > New).
    restartTimes = {
        -- "06:00", "18:00",
    },
    restartWarnings = { 30, 15, 5, 1 },
    restartMessage = "Server restart in {minutes} minute(s).",
}
