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
        -- Starter kit: SCUM admin commands (without "#") run once per new player, after their
        -- character spawns. {steamId} and {name} are the player. Needs an admin online; the kit
        -- waits until one is. Use commands that name the player: SpawnItem has no target, so it
        -- would drop items in front of the admin instead.
        starterKit = true,
        -- EXPERIMENTAL: items given straight into the new player's inventory, no admin needed.
        -- Item names as in SpawnItem (find them with "Find an item name" on the Admin Console),
        -- e.g. { item = "Water_05l", amount = 1 }.
        starterKitItems = {},
        starterKitCommands = {
            "ChangeCurrencyBalance Normal 500 {steamId}",
        },
        starterKitMessage = "Welcome gift: 500 cash has been added to your account. Spend it at a trader.",
    },

    -- Returning players get their stats when they join. {name} {hours} {kills} {deaths} {bestStreak}
    welcomeBack = {
        enabled = true,
        message = "Welcome back {name}! {hours} played, {kills} kills, {deaths} deaths.",
    },

    -- Rewards for playing, run as SCUM admin commands (needs an admin online; owed rewards wait).
    playtimeRewards = {
        enabled = true,
        everyMinutes = 60,
        commands = { "ChangeCurrencyBalance Normal 100 {steamId}" },
        message = "+100 cash for an hour on the server. Thanks for playing!",
        -- Once per day (UTC), the first time the player is online.
        dailyCommands = { "ChangeCurrencyBalance Normal 200 {steamId}" },
        dailyMessage = "Daily login bonus: +200 cash.",
        -- EXPERIMENTAL: items given with each reward, e.g. { item = "Water_05l", amount = 1 }.
        items = {},
        dailyItems = {},
    },

    -- {name} {count} / {killer} {victim} {count}
    killStreaks = {
        enabled = true,
        announceAt = { 3, 5, 10, 15, 20 },
        message = "{name} is on a {count} kill streak!",
        endedMessage = "{killer} ended {victim}'s {count} kill streak!",
        endedMinimum = 3,
        -- Killing the same player again within this many minutes does not count (stops farming).
        ignoreSameVictimMinutes = 30,
    },

    -- The server puts a bounty on players with a kill streak; whoever kills them collects it.
    bounties = {
        enabled = true,
        streakBountyAt = 5,          -- kill streak that starts a bounty (0 = never)
        streakBountyAmount = 500,
        streakBountyIncrease = 100,  -- added for each further kill
        -- Let players place bounties with !bounty <name> <amount>. Off: the mod cannot check a
        -- player's balance yet, so a broke player could place a bounty for a friend to collect.
        playerBounties = false,
        minAmount = 100,
        maxAmount = 5000,
        payCommand = "ChangeCurrencyBalance Normal {amount} {steamId}",
        chargeCommand = "ChangeCurrencyBalance Normal -{amount} {steamId}",
        -- EXPERIMENTAL: read the player's balance first and refuse bounties they cannot pay.
        -- Turn this on before playerBounties.
        checkBalance = false,
    },

    -- !tp <name>: the player stands still for standStillSeconds, pays the price and is teleported.
    -- Coordinates are SCUM world units (centimetres); admins can type !where to get theirs.
    teleports = {
        enabled = true,
        cooldownMinutes = 30,
        standStillSeconds = 10,
        -- "admin": SCUM's Teleport command (needs an admin online).
        -- "direct": EXPERIMENTAL, moves the player directly, no admin needed.
        method = "admin",
        -- EXPERIMENTAL: read the player's balance first and refuse teleports they cannot pay.
        checkBalance = false,
        command = "Teleport {steamId} {x} {y} {z}",
        chargeCommand = "ChangeCurrencyBalance Normal -{price} {steamId}",
        locations = {
            -- { name = "trader", x = 0, y = 0, z = 0, price = 500 },
        },
    },

    -- !info: server time, uptime, players online, next restart (from ServerMessages), plus these lines.
    info = {
        enabled = true,
        lines = {},
    },

    -- !report <name> <what happened>: written to reports.log, the Admin Console and online admins.
    reports = {
        enabled = true,
        cooldownSeconds = 60,
    },

    -- Tell players what the server offers. The tips are built from the settings above, so they
    -- only mention what is switched on.
    featureTips = {
        onJoin = true,                 -- "This server has: ..." to each player when they spawn
        announceEveryMinutes = 20,     -- a rotating tip to everyone (0 = never)
        extraTips = {},                -- your own tips, added to the rotation
    },

    -- A private message to the player who died. {killer} {weapon} {distance}
    deathRecap = {
        enabled = true,
        message = "You were killed by {killer} with {weapon} from {distance} m.",
    },

    -- Several kills close together are announced, by map sector (worked out from the outposts)
    -- or the nearest teleport destination. {place} {kills}
    hotspots = {
        enabled = true,
        kills = 3,
        withinMinutes = 5,
        radius = 500,               -- metres
        cooldownMinutes = 10,       -- the same place at most this often
        message = "Heavy fighting reported {place}!",
    },

    -- Players volunteer with !manhunt join. Every so often one becomes the target; their sector
    -- is announced every few minutes. The killer, or the target if they survive, is rewarded.
    -- Commands need an admin online (rewards wait); items are experimental.
    manhunt = {
        enabled = true,
        everyMinutes = 60,
        durationMinutes = 15,
        revealEveryMinutes = 3,
        minPlayers = 3,
        hunterCommands = { "ChangeCurrencyBalance Normal 1000 {steamId}" },
        hunterItems = {},
        survivorCommands = { "ChangeCurrencyBalance Normal 1000 {steamId}" },
        survivorItems = {},
    },

    -- King of the Hill: one zone is announced; whoever stays inside it longest wins.
    -- Zones: { name = "airfield", x = 0, y = 0, z = 0, radius = 100 } (world units; radius in m).
    -- Do not use outposts: they are safe zones.
    koth = {
        enabled = true,
        everyMinutes = 90,
        durationMinutes = 15,
        updateEveryMinutes = 5,
        minPlayers = 3,
        minSeconds = 60,
        zones = {},
        rewardCommands = { "ChangeCurrencyBalance Normal 1000 {steamId}" },
        rewardItems = {},
    },
}
