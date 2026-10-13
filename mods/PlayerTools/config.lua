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
        -- character spawns. {steamId} and {name} are the player. Needs an admin online (or the
        -- no-admin route: no-admin-commands.txt in the PelicanConsole folder); the kit waits until then. Use commands that name the player: SpawnItem has no target, so it
        -- would drop items in front of the admin instead.
        starterKit = true,
        -- Items given straight into the new player's inventory, no admin needed (not yet
        -- confirmed on a live server; needs itemRewards on).
        -- Item names as in SpawnItem (find them with "Find an item name" on the Admin Console),
        -- e.g. { item = "Water_05l", amount = 1 }.
        -- "basic": water, tuna, beans, apples, bandages, a knife and a small backpack, used while
        -- starterKitItems is empty. "none": only starterKitItems. Items need itemRewards on.
        starterKitPreset = "basic",
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
        dailyEnabled = true,
        dailyCommands = { "ChangeCurrencyBalance Normal 200 {steamId}" },
        dailyMessage = "Daily login bonus: +200 cash.",
        -- Items given with each reward, e.g. { item = "Water_05l", amount = 1 } (needs itemRewards on).
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
        -- Read the player's balance first and refuse bounties they cannot pay. Keep this on
        -- with playerBounties.
        checkBalance = true,
    },

    -- !tp <name>: the player stands still for standStillSeconds, pays the price and is teleported.
    -- Coordinates are SCUM world units (centimetres); admins can type !where to get theirs.
    teleports = {
        enabled = true,
        cooldownMinutes = 30,
        standStillSeconds = 10,
        -- "admin": SCUM's Teleport command (needs an admin online).
        -- "direct": moves the player directly, no admin needed (not yet confirmed on a live server).
        method = "admin",
        -- Read the player's balance first and refuse teleports they cannot pay.
        checkBalance = true,
        command = "Teleport {steamId} {x} {y} {z}",
        chargeCommand = "ChangeCurrencyBalance Normal -{price} {steamId}",
        locations = {
            -- { name = "trader", x = 0, y = 0, z = 0, price = 500 },
        },
        -- !tpto <name>: teleport to another player once they type !tpaccept. Same cooldown,
        -- stand-still time and teleport method as above.
        toPlayer = true,
        toPlayerPrice = 0,
        requestSeconds = 60,   -- how long the other player has to accept
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
    -- Commands need an admin online or the no-admin route (rewards wait until then).
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

    -- One switch for every item list above (starter kit, playtime and daily rewards, manhunt and
    -- King of the Hill rewards). Commands such as cash are not affected. Not yet confirmed on a
    -- live server: try it on yourself first.
    itemRewards = {
        enabled = false,
    },

    -- Economy. Money moves with ChangeCurrencyBalance, so these need an admin online or the
    -- no-admin route (no-admin-commands.txt in the PelicanConsole folder). Spending always checks
    -- the player's balance first; winnings are paid when the winner is next online.

    -- !shop and !buy <name> [count]. Items: { name = "water", item = "Water_05l", amount = 1, price = 50 }
    shop = {
        enabled = false,
        maxPerPurchase = 5,
        items = {},
    },

    -- !sell sells the item in the player's hands; !sell prices lists what the server buys.
    -- The item is dropped (SCUM's own drop), removed, then the player is paid. Do not list
    -- containers such as backpacks: whatever is inside them goes with them.
    -- Items: { name = "AK-47", item = "Weapon_AK47", price = 2000 }
    sell = {
        enabled = false,
        items = {},
    },

    -- !pay <name> <amount> between online players; the fee is taken on top.
    pay = {
        enabled = false,
        minAmount = 10,
        maxAmount = 100000,
        feePercent = 0,
    },

    -- !lottery and !lottery buy [count]. The winner gets the pot minus the house share.
    lottery = {
        enabled = false,
        ticketPrice = 100,
        maxTicketsPerPlayer = 10,
        drawEveryMinutes = 60,
        housePercent = 10,
        minTickets = 2,
    },

    -- !tasks. Kinds: playtime (minutes), kills (player kills), longshot (metres). Reset at midnight UTC.
    dailyTasks = {
        enabled = false,
        tasks = {
            { kind = "playtime", target = 60, reward = 300, text = "Play for 60 minutes" },
            { kind = "kills", target = 3, reward = 500, text = "Kill 3 players" },
            { kind = "longshot", target = 200, reward = 500, text = "Get a kill from 200 m or more" },
        },
    },

    -- Most player kills during the race wins. !race shows the time left.
    killRace = {
        enabled = false,
        everyMinutes = 120,
        durationMinutes = 20,
        minPlayers = 3,
        prize = 2000,
    },

    -- Every so often, this much per squadmate online with the player.
    squadBonus = {
        enabled = false,
        everyMinutes = 60,
        amountPerMate = 25,
        maxMates = 4,
    },
}
