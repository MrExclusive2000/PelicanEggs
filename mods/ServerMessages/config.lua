-- ServerMessages settings. Edit, then restart the server.
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

    -- Same as PelicanConsole: SCUM admin commands start with "#".
    commandPrefix = "#",
}
