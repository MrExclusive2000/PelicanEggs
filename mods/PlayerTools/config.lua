-- PlayerTools settings. Edit here or on the SCUM Manager "SCUM Mod Settings" page.
-- Changes are picked up within 30 seconds; no restart needed.
return {
    -- Chat commands players type in game chat, e.g. !help. Replies go only to that player.
    chatCommands = {
        enabled = true,
        prefix = "!",
        rules = {
            "No cheating or exploiting.",
            "Respect other players.",
        },
        discord = "",   -- shown by !discord, e.g. "discord.gg/yourinvite"
    },

    -- Announces kills to everyone. {killer} {victim} {weapon} {distance}
    killFeed = {
        enabled = true,
        message = "{killer} killed {victim} with {weapon} ({distance} m)",
        minDistance = 0,   -- metres; only announce kills at least this far
    },

    -- Kills, deaths, longest kill and playtime per player. !stats and !top in chat.
    stats = {
        enabled = true,
        topCount = 3,
        announceTopEveryMinutes = 0,   -- 0 = never announce the leaderboard
    },

    -- Kicks players who have not moved or looked around for a while.
    afk = {
        enabled = false,
        minutes = 20,
        warnMinutesBefore = 2,
        onlyWhenPlayersAtLeast = 0,    -- only kick when this many players are online (0 = always)
        ignoreAdmins = true,
        kickReason = "Kicked for being AFK.",
    },

    -- Players vote with !vote <option>, then !yes / !no.
    -- Options run SCUM admin commands, so an admin (AdminUsers.ini) must be online for a
    -- passed vote to take effect.
    voting = {
        enabled = true,
        durationSeconds = 60,
        cooldownMinutes = 15,
        percentNeeded = 50,            -- of players online
        minVotes = 2,
        options = {
            { name = "day", label = "make it daytime", command = "SetTime 10" },
            { name = "night", label = "make it night", command = "SetTime 22" },
            { name = "sun", label = "clear the weather", command = "SetWeather 0" },
        },
    },

    -- First time a player joins the server.
    newPlayers = {
        messages = {
            "Welcome {name}! Type !help in chat for server commands.",
        },
        -- Starter kit: SCUM admin commands run once per new player, after their character spawns.
        -- {location} is where the player stands, {steamId} and {name} the player.
        -- Needs an admin online; the kit waits until one is.
        starterKit = false,
        starterKitCommands = {
            -- 'SpawnItem Water_05l 1 Location "{location}"',
            -- 'ChangeCurrencyBalance Normal 500 {steamId}',
        },
        starterKitMessage = "Your starter kit has arrived. Good luck out there!",
    },
}
