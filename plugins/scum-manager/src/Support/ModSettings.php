<?php

namespace MrExclusive\ScumManager\Support;

/**
 * The settings of our own mods, as shown on the SCUM Mod Settings page.
 *
 * Each field maps a path in the mod's config.lua (e.g. "afk.minutes") to a form field.
 * Form state is flat, keyed by field id ("PlayerTools__afk__minutes"), because Filament
 * treats dots in state keys as nesting.
 *
 * Field types:
 *   toggle, int, text, select (options), lines (list of strings, one per line),
 *   ints (list of numbers, comma separated), rows (list of tables, edited as a repeater;
 *   "columns" names the keys, or with "tuple" the positions, of each row; "numeric" lists
 *   the column positions saved as numbers; "itemColumn" names a column picked from the
 *   server's item list).
 */
final class ModSettings
{
    public const MODS = [
        'PlayerTools' => [
            'label' => 'Player tools',
            'description' => 'Chat commands, kill feed, stats, AFK kicker, voting, new players, rewards, kill streaks, bounties, teleports, info and reports.',
            'sections' => [
                'Chat commands' => [
                    'description' => 'Players type these in game chat; replies go only to them. !help, !rules, !discord, !online, !stats, !top, !vote',
                    'fields' => [
                        'chatCommands.enabled' => ['toggle', 'Chat commands on', true],
                        'chatCommands.prefix' => ['text', 'Command prefix', '!'],
                        'chatCommands.discord' => ['text', 'Discord link for !discord', ''],
                        'chatCommands.rules' => ['lines', 'Rules for !rules (one per line)', []],
                    ],
                ],
                'Kill feed' => [
                    'description' => 'Announces kills on every player\'s screen. Placeholders: {killer} {victim} {weapon} {distance}',
                    'fields' => [
                        'killFeed.enabled' => ['toggle', 'Kill feed on', true],
                        'killFeed.message' => ['text', 'Message', '{killer} killed {victim} with {weapon} ({distance} m)'],
                        'killFeed.minDistance' => ['int', 'Only kills at least this far (m, 0 = all)', 0],
                    ],
                ],
                'Stats' => [
                    'description' => 'Kills, deaths, K/D, longest kill and playtime per player. Players see them with !stats and !top.',
                    'fields' => [
                        'stats.enabled' => ['toggle', 'Stats on', true],
                        'stats.topCount' => ['int', 'Players on the leaderboard', 3],
                        'stats.announceTopEveryMinutes' => ['int', 'Announce the leaderboard every (min, 0 = never)', 0],
                    ],
                ],
                'AFK kicker' => [
                    'description' => 'Warns, then kicks players who have not moved or looked around.',
                    'fields' => [
                        'afk.enabled' => ['toggle', 'AFK kicker on', false],
                        'afk.minutes' => ['int', 'Kick after (min)', 20],
                        'afk.warnMinutesBefore' => ['int', 'Warn this many minutes before', 2],
                        'afk.onlyWhenPlayersAtLeast' => ['int', 'Only when at least this many players are online (0 = always)', 0],
                        'afk.ignoreAdmins' => ['toggle', 'Never kick admins', true],
                        'afk.kickReason' => ['text', 'Kick reason', 'Kicked for being AFK.'],
                    ],
                ],
                'Voting' => [
                    'description' => 'Players start a vote with !vote <name> and answer with !yes or !no. A passed vote runs the SCUM admin command (without #) as an online admin, so an admin must be online.',
                    'fields' => [
                        'voting.enabled' => ['toggle', 'Voting on', true],
                        'voting.durationSeconds' => ['int', 'Vote length (s)', 60],
                        'voting.cooldownMinutes' => ['int', 'Minutes between votes', 15],
                        'voting.percentNeeded' => ['int', 'Yes votes needed (% of players online)', 50],
                        'voting.minVotes' => ['int', 'At least this many yes votes', 2],
                        'voting.options' => ['rows', 'Vote options', [], 'columns' => ['name' => 'Name (!vote name)', 'label' => 'Description', 'command' => 'Admin command']],
                    ],
                ],
                'New players' => [
                    'description' => 'For a player\'s first join. Placeholders: {name} {steamId}. Starter kit items go straight into the new player\'s inventory (experimental). Starter kit admin commands (without #) run as an online admin, e.g. ChangeCurrencyBalance Normal 500 {steamId}; with commands set, the whole kit waits until an admin is online. Do not use SpawnItem there: it drops items in front of the admin.',
                    'fields' => [
                        'newPlayers.messages' => ['lines', 'Welcome messages (one per line)', []],
                        'newPlayers.starterKit' => ['toggle', 'Starter kit on', true],
                        'newPlayers.starterKitPreset' => ['select', 'Ready-made kit (used while the item list below is empty)', 'basic', 'options' => ['basic' => 'Basic: 2 water, tuna, beans, 2 apples, 3 bandages, knife, small backpack', 'none' => 'None']],
                        'newPlayers.starterKitItems' => ['rows', 'Starter kit items (experimental: needs "Give items" on)', [], 'numeric' => [1], 'itemColumn' => 'item', 'columns' => ['item' => 'Item', 'amount' => 'Amount']],
                        'newPlayers.starterKitCommands' => ['lines', 'Starter kit admin commands (one per line, need an admin online)', []],
                        'newPlayers.starterKitMessage' => ['text', 'Message when the kit is given', ''],
                    ],
                ],
                'Item rewards (experimental)' => [
                    'description' => 'One switch for every item list on this page: starter kit, playtime and daily rewards, manhunt and King of the Hill. Items go straight into the player\'s inventory without an admin. Leave this off until "Give an item" on the Admin Console has worked for you. Cash and other commands are not affected.',
                    'fields' => [
                        'itemRewards.enabled' => ['toggle', 'Give items', false],
                    ],
                ],
                'Without an admin online' => [
                    'description' => 'Cash rewards, the starter kit cash and paid teleports normally run as an online admin and wait until one is on. With this on, PlayerTools checks once per server run whether SCUM accepts the commands without an admin (it adds 1 coin to a player and takes it back) and uses that if it works. The result is in the PlayerTools log.',
                    'fields' => [
                        'noAdminFallback' => ['toggle', 'Try without an admin', true],
                    ],
                ],
                'Welcome back' => [
                    'description' => 'Returning players get their stats when they join. Placeholders: {name} {hours} {kills} {deaths} {bestStreak}',
                    'fields' => [
                        'welcomeBack.enabled' => ['toggle', 'Welcome back on', true],
                        'welcomeBack.message' => ['text', 'Message', 'Welcome back {name}! {hours} played, {kills} kills, {deaths} deaths.'],
                    ],
                ],
                'Playtime rewards' => [
                    'description' => 'SCUM admin commands (without #) run as an online admin; rewards wait until one is online. Placeholders: {name} {steamId}',
                    'fields' => [
                        'playtimeRewards.enabled' => ['toggle', 'Playtime rewards on', true],
                        'playtimeRewards.everyMinutes' => ['int', 'Reward every (min played)', 60],
                        'playtimeRewards.commands' => ['lines', 'Reward commands (one per line)', ['ChangeCurrencyBalance Normal 100 {steamId}']],
                        'playtimeRewards.items' => ['rows', 'Reward items (experimental)', [], 'numeric' => [1], 'itemColumn' => 'item', 'columns' => ['item' => 'Item', 'amount' => 'Amount']],
                        'playtimeRewards.message' => ['text', 'Reward message', '+100 cash for an hour on the server. Thanks for playing!'],
                        'playtimeRewards.dailyEnabled' => ['toggle', 'Daily login bonus on', true],
                        'playtimeRewards.dailyCommands' => ['lines', 'Daily login bonus commands (one per line)', ['ChangeCurrencyBalance Normal 200 {steamId}']],
                        'playtimeRewards.dailyItems' => ['rows', 'Daily bonus items (experimental)', [], 'numeric' => [1], 'itemColumn' => 'item', 'columns' => ['item' => 'Item', 'amount' => 'Amount']],
                        'playtimeRewards.dailyMessage' => ['text', 'Daily bonus message', 'Daily login bonus: +200 cash.'],
                    ],
                ],
                'Kill streaks' => [
                    'description' => 'Placeholders: {name} {count}, and {killer} {victim} {count} for an ended streak.',
                    'fields' => [
                        'killStreaks.enabled' => ['toggle', 'Kill streaks on', true],
                        'killStreaks.announceAt' => ['ints', 'Announce at (comma separated)', [3, 5, 10, 15, 20]],
                        'killStreaks.message' => ['text', 'Streak message', '{name} is on a {count} kill streak!'],
                        'killStreaks.endedMessage' => ['text', 'Streak ended message', '{killer} ended {victim}\'s {count} kill streak!'],
                        'killStreaks.endedMinimum' => ['int', 'Announce ended streaks from', 3],
                        'killStreaks.ignoreSameVictimMinutes' => ['int', 'Ignore repeat kills of the same player for (min)', 30],
                    ],
                ],
                'Bounties' => [
                    'description' => 'The server puts a bounty on players with a kill streak; whoever kills them collects it (paid when an admin is online). Player bounties stay off until the mod can check balances: a broke player could otherwise place a bounty for a friend to collect.',
                    'fields' => [
                        'bounties.enabled' => ['toggle', 'Bounties on', true],
                        'bounties.streakBountyAt' => ['int', 'Bounty from this kill streak (0 = never)', 5],
                        'bounties.streakBountyAmount' => ['int', 'Starting bounty', 500],
                        'bounties.streakBountyIncrease' => ['int', 'Added per further kill', 100],
                        'bounties.checkBalance' => ['toggle', 'Check the player can pay first (experimental; turn on before player bounties)', false],
                        'bounties.playerBounties' => ['toggle', 'Players can place bounties (!bounty <name> <amount>)', false],
                        'bounties.minAmount' => ['int', 'Smallest player bounty', 100],
                        'bounties.maxAmount' => ['int', 'Largest player bounty', 5000],
                        'bounties.payCommand' => ['text', 'Payout command ({amount} {steamId})', 'ChangeCurrencyBalance Normal {amount} {steamId}'],
                        'bounties.chargeCommand' => ['text', 'Charge command ({amount} {steamId})', 'ChangeCurrencyBalance Normal -{amount} {steamId}'],
                    ],
                ],
                'Teleports' => [
                    'description' => '!tp <name>: the player stands still, pays and is teleported (needs an admin online). Coordinates are SCUM world units; type !where in game as an admin to get yours.',
                    'fields' => [
                        'teleports.enabled' => ['toggle', 'Teleports on', true],
                        'teleports.cooldownMinutes' => ['int', 'Cooldown (min)', 30],
                        'teleports.standStillSeconds' => ['int', 'Stand still for (s)', 10],
                        'teleports.method' => ['select', 'How to teleport', 'admin', 'options' => ['admin' => 'SCUM Teleport command (needs an admin online)', 'direct' => 'Direct (experimental, no admin needed)']],
                        'teleports.checkBalance' => ['toggle', 'Check the player can pay first (experimental)', false],
                        'teleports.locations' => ['rows', 'Destinations', [], 'numeric' => [1, 2, 3, 4], 'columns' => ['name' => 'Name (!tp name)', 'x' => 'X', 'y' => 'Y', 'z' => 'Z', 'price' => 'Price']],
                        'teleports.command' => ['text', 'Teleport command ({steamId} {x} {y} {z})', 'Teleport {steamId} {x} {y} {z}'],
                        'teleports.chargeCommand' => ['text', 'Charge command ({price} {steamId})', 'ChangeCurrencyBalance Normal -{price} {steamId}'],
                        'teleports.toPlayer' => ['toggle', 'Teleport to players (!tpto name, they !tpaccept)', true],
                        'teleports.toPlayerPrice' => ['int', 'Price to teleport to a player', 0],
                        'teleports.requestSeconds' => ['int', 'Time to accept a teleport request (s)', 60],
                    ],
                ],
                'Feature tips' => [
                    'description' => 'Tells players what the server offers. The tips are built from the settings on this page, so they only mention what is switched on.',
                    'fields' => [
                        'featureTips.onJoin' => ['toggle', 'Tell each player the server\'s features when they join', true],
                        'featureTips.announceEveryMinutes' => ['int', 'Announce a rotating tip every (min, 0 = never)', 20],
                        'featureTips.extraTips' => ['lines', 'Your own tips (one per line)', []],
                    ],
                ],
                'Death recap and hotspots' => [
                    'description' => 'Death recap: a private message to the player who died. Hotspots: several kills close together are announced by map sector (worked out from the outposts) or the nearest teleport destination.',
                    'fields' => [
                        'deathRecap.enabled' => ['toggle', 'Death recap on', true],
                        'deathRecap.message' => ['text', 'Death recap ({killer} {weapon} {distance})', 'You were killed by {killer} with {weapon} from {distance} m.'],
                        'hotspots.enabled' => ['toggle', 'Hotspots on', true],
                        'hotspots.message' => ['text', 'Hotspot message ({place} {kills})', 'Heavy fighting reported {place}!'],
                        'hotspots.kills' => ['int', 'Kills', 3],
                        'hotspots.withinMinutes' => ['int', 'Within (min)', 5],
                        'hotspots.radius' => ['int', 'Within (m)', 500],
                        'hotspots.cooldownMinutes' => ['int', 'Same place at most every (min)', 10],
                    ],
                ],
                'Manhunt' => [
                    'description' => 'Players volunteer with !manhunt join. Every so often one of them becomes the target; their sector is announced every few minutes. Whoever kills them gets the hunter reward; if they survive, they get the survivor reward. Commands need an admin online; items are experimental.',
                    'fields' => [
                        'manhunt.enabled' => ['toggle', 'Manhunt on', true],
                        'manhunt.everyMinutes' => ['int', 'A manhunt every (min)', 60],
                        'manhunt.durationMinutes' => ['int', 'Lasts (min)', 15],
                        'manhunt.revealEveryMinutes' => ['int', 'Reveal the target every (min)', 3],
                        'manhunt.minPlayers' => ['int', 'Only with at least this many players online', 3],
                        'manhunt.hunterCommands' => ['lines', 'Hunter reward commands ({steamId})', ['ChangeCurrencyBalance Normal 1000 {steamId}']],
                        'manhunt.hunterItems' => ['rows', 'Hunter reward items (experimental)', [], 'numeric' => [1], 'itemColumn' => 'item', 'columns' => ['item' => 'Item', 'amount' => 'Amount']],
                        'manhunt.survivorCommands' => ['lines', 'Survivor reward commands ({steamId})', ['ChangeCurrencyBalance Normal 1000 {steamId}']],
                        'manhunt.survivorItems' => ['rows', 'Survivor reward items (experimental)', [], 'numeric' => [1], 'itemColumn' => 'item', 'columns' => ['item' => 'Item', 'amount' => 'Amount']],
                    ],
                ],
                'King of the Hill' => [
                    'description' => 'Every so often one zone is announced; whoever stays inside it longest wins. Add zones here, or on the Admin Console with "Add a teleport where a player stands" (Add as: King of the Hill zone). Do not use outposts: they are safe zones.',
                    'fields' => [
                        'koth.enabled' => ['toggle', 'King of the Hill on', true],
                        'koth.zones' => ['rows', 'Zones', [], 'numeric' => [1, 2, 3, 4], 'columns' => ['name' => 'Name', 'x' => 'X', 'y' => 'Y', 'z' => 'Z', 'radius' => 'Radius (m)']],
                        'koth.everyMinutes' => ['int', 'An event every (min)', 90],
                        'koth.durationMinutes' => ['int', 'Lasts (min)', 15],
                        'koth.updateEveryMinutes' => ['int', 'Announce the leader every (min)', 5],
                        'koth.minPlayers' => ['int', 'Only with at least this many players online', 3],
                        'koth.minSeconds' => ['int', 'Winner must hold it at least (s)', 60],
                        'koth.rewardCommands' => ['lines', 'Reward commands ({steamId})', ['ChangeCurrencyBalance Normal 1000 {steamId}']],
                        'koth.rewardItems' => ['rows', 'Reward items (experimental)', [], 'numeric' => [1], 'itemColumn' => 'item', 'columns' => ['item' => 'Item', 'amount' => 'Amount']],
                    ],
                ],
                'Info and reports' => [
                    'description' => '!info shows server time, uptime, players online and the next restart (from Messages > Restart warnings), then these lines. !report <name> <what happened> goes to reports.log, the Admin Console page and online admins.',
                    'fields' => [
                        'info.enabled' => ['toggle', '!info on', true],
                        'info.lines' => ['lines', 'Extra !info lines', []],
                        'reports.enabled' => ['toggle', '!report on', true],
                        'reports.cooldownSeconds' => ['int', 'Seconds between reports per player', 60],
                    ],
                ],
            ],
        ],
        'ServerMessages' => [
            'label' => 'Messages',
            'description' => 'Welcome message, rotating announcements, join/leave log and restart warnings.',
            'sections' => [
                'Welcome and joins' => [
                    'description' => 'Placeholders: {name} {players}',
                    'fields' => [
                        'welcome' => ['text', 'Private welcome after spawning (empty = off)', ''],
                        'joinAnnouncement' => ['text', 'Announce joins to everyone (empty = off)', ''],
                        'logJoinsAndLeaves' => ['toggle', 'Log joins and leaves (players.log and console)', true],
                    ],
                ],
                'Announcements' => [
                    'description' => 'Shown on every player\'s screen, one at a time, in turn.',
                    'fields' => [
                        'announcements' => ['lines', 'Messages (one per line)', []],
                        'intervalMinutes' => ['int', 'Every (min)', 30],
                        'onlyWhenPlayersOnline' => ['toggle', 'Skip while the server is empty', true],
                    ],
                ],
                'Restart warnings' => [
                    'description' => 'Countdown announcements before each daily restart. Times are HH:MM in UTC. The restart itself is a Pelican schedule (Schedules), at the same times.',
                    'fields' => [
                        'restartTimes' => ['lines', 'Restart times, UTC (one per line, e.g. 06:00)', []],
                        'restartWarnings' => ['ints', 'Warn this many minutes before (comma separated)', [30, 15, 5, 1]],
                        'restartMessage' => ['text', 'Message ({minutes} = minutes left)', 'Server restart in {minutes} minute(s).'],
                    ],
                ],
            ],
        ],
        'ScumAntiCheat' => [
            'label' => 'Anti-cheat',
            'description' => 'Server-side checks for speed, teleport, fly and hover hacks, map bounds, fake admins and aimbots.',
            'sections' => [
                'Action' => [
                    'description' => 'Start with "log" for a few days and read anticheat.log before kicking or banning.',
                    'fields' => [
                        'action' => ['select', 'When a player reaches the strike limit', 'log', 'options' => ['log' => 'Log only', 'kick' => 'Kick', 'ban' => 'Ban (BannedUsers.ini) and kick']],
                        'strikesToAct' => ['int', 'Strikes', 3],
                        'strikeWindowSeconds' => ['int', 'Within (s)', 60],
                        'banAfterKicks' => ['int', 'With "kick": ban after this many kicks (0 = never)', 3],
                        'kickReason' => ['text', 'Kick reason', 'Kicked by anti-cheat.'],
                    ],
                ],
                'Checks' => [
                    'description' => 'Turning the aim snap check on or off takes effect after a restart.',
                    'fields' => [
                        'checks.speed' => ['toggle', 'Speed', true],
                        'checks.teleport' => ['toggle', 'Teleport', true],
                        'checks.flying' => ['toggle', 'Flying', true],
                        'checks.hovering' => ['toggle', 'Hovering', true],
                        'checks.mapBounds' => ['toggle', 'Map bounds / under the map', true],
                        'checks.unauthorizedAdmin' => ['toggle', 'Admin rights without AdminUsers.ini', true],
                        'checks.names' => ['toggle', 'Staff impersonation names', true],
                        'checks.watchlist' => ['toggle', 'Watchlist', true],
                        'checks.gameLogs' => ['toggle', 'Show SCUM violation and admin logs', true],
                        'checks.killLog' => ['toggle', 'Aimbot signs in the kill log', true],
                        'checks.aimSnap' => ['toggle', 'Aim snaps before kills', true],
                        'checks.magicBullet' => ['toggle', 'Magic bullets (kills without aiming at the victim)', true],
                        'checks.adminLog' => ['toggle', 'Admin commands from players not in AdminUsers.ini', true],
                    ],
                ],
                'Movement limits' => [
                    'description' => 'Metres, metres per second and seconds.',
                    'fields' => [
                        'maxFootSpeed' => ['int', 'Max speed on foot (m/s)', 21],
                        'maxVehicleSpeed' => ['int', 'Max speed in vehicles (m/s)', 120],
                        'teleportDistance' => ['int', 'Teleport distance (m)', 300],
                        'vehicleMapMargin' => ['int', 'Extra room past the map edge in vehicles (m)', 3000],
                        'vehicleMovementStrikes' => ['toggle', 'Count speed and teleports in vehicles as strikes (off: only reported, car glitches are common)', false],
                        'flyingSeconds' => ['int', 'Flying for (s)', 10],
                        'hoverSeconds' => ['int', 'Hovering for (s)', 8],
                    ],
                ],
                'Aimbot' => [
                    'description' => 'These only report suspects unless "count as strikes" is on. Spectate before you ban.',
                    'fields' => [
                        'maxKillDistance' => ['int', 'Longest believable firearm kill (m)', 800],
                        'maxMeleeDistance' => ['int', 'Longest melee kill (m)', 8],
                        'weaponMaxDistance' => ['rows', 'Shorter limits for weapons whose name contains', [], 'tuple' => true, 'numeric' => [1], 'columns' => ['Weapon name contains', 'Max distance (m)']],
                        'killRateKills' => ['int', 'Suspicious kills', 8],
                        'killRateMinutes' => ['int', 'Within (min)', 5],
                        'maxLocationMismatch' => ['int', 'Max client/server position gap (m)', 50],
                        'aimSnapDegrees' => ['int', 'Aim snap (degrees in 0.1 s)', 150],
                        'aimSnapPattern' => ['int', 'Report after this many snapped kills', 3],
                        'magicBulletDegrees' => ['int', 'Magic bullet: aim this many degrees off the victim', 60],
                        'magicBulletPattern' => ['int', 'Report after this many magic bullet kills', 2],
                        'strikeOnKillFlags' => ['toggle', 'Count aimbot suspicions as strikes', false],
                    ],
                ],
                'Players' => [
                    'description' => 'One name or SteamID64 per line.',
                    'fields' => [
                        'ignoreAdmins' => ['toggle', 'Never check admins', true],
                        'ignoreNames' => ['lines', 'Never check these names', []],
                        'ignoreSteamIds' => ['lines', 'Never check these SteamIDs', []],
                        'blockedNames' => ['lines', 'Flag names containing', []],
                        'watchlist' => ['lines', 'Announce when these SteamIDs join', []],
                        'strikeOnGameViolations' => ['toggle', 'Count SCUM\'s own violations as strikes', false],
                    ],
                ],
            ],
        ],
    ];

    /** @return array<string, array{0: string, 1: string, 2: mixed, options?: array<string, string>, columns?: array<int|string, string>, tuple?: bool}> */
    public static function fields(string $mod): array
    {
        $fields = [];
        foreach (self::MODS[$mod]['sections'] ?? [] as $section) {
            $fields += $section['fields'];
        }

        return $fields;
    }

    public static function fieldId(string $mod, string $path): string
    {
        return $mod . '__' . str_replace('.', '__', $path);
    }

    /**
     * Form state for one mod from its parsed config.lua.
     *
     * @param  array<mixed>  $config
     * @return array<string, mixed>
     */
    public static function toState(string $mod, array $config): array
    {
        $state = [];
        foreach (self::fields($mod) as $path => $field) {
            $value = self::get($config, $path, $field[2]);
            $state[self::fieldId($mod, $path)] = match ($field[0]) {
                'toggle' => (bool) $value,
                'int' => is_numeric($value) ? $value + 0 : $field[2],
                'text', 'select' => is_scalar($value) ? (string) $value : (string) $field[2],
                'lines' => implode("\n", array_map('strval', array_filter(is_array($value) ? $value : [], 'is_scalar'))),
                'ints' => implode(', ', array_map('strval', array_filter(is_array($value) ? $value : [], 'is_numeric'))),
                'rows' => self::rowsToState($field, is_array($value) ? $value : []),
            };
        }

        return $state;
    }

    /**
     * The config with the form's values written in. Keys the form does not know are kept.
     *
     * @param  array<mixed>  $config
     * @param  array<string, mixed>  $state
     * @return array<mixed>
     */
    public static function apply(string $mod, array $config, array $state): array
    {
        foreach (self::fields($mod) as $path => $field) {
            $id = self::fieldId($mod, $path);
            if (!array_key_exists($id, $state)) {
                continue;
            }
            $raw = $state[$id];

            $value = match ($field[0]) {
                'toggle' => (bool) $raw,
                'int' => is_numeric($raw) ? (int) round((float) $raw) : $field[2],
                'text', 'select' => trim((string) $raw),
                'lines' => self::lines((string) $raw),
                'ints' => array_map('intval', array_values(array_filter(array_map('trim', explode(',', (string) $raw)), 'is_numeric'))),
                'rows' => self::rowsFromState($field, is_array($raw) ? $raw : []),
            };

            self::set($config, $path, $value);
        }

        return $config;
    }

    /** @return list<string> */
    public static function lines(string $text): array
    {
        return array_values(array_filter(
            array_map('trim', explode("\n", str_replace("\r\n", "\n", $text))),
            fn (string $line) => $line !== '',
        ));
    }

    /**
     * @param  array<mixed>  $field
     * @param  array<mixed>  $rows
     * @return list<array<string, string>>
     */
    private static function rowsToState(array $field, array $rows): array
    {
        $state = [];
        foreach ($rows as $row) {
            if (!is_array($row)) {
                continue;
            }
            $item = [];
            foreach (array_keys($field['columns']) as $index => $key) {
                $source = ($field['tuple'] ?? false) ? $index : $key;
                $item[($field['tuple'] ?? false) ? 'c' . $index : $key] = isset($row[$source]) && is_scalar($row[$source]) ? (string) $row[$source] : '';
            }
            $state[] = $item;
        }

        return $state;
    }

    /**
     * @param  array<mixed>  $field
     * @param  array<mixed>  $state
     * @return list<array<mixed>>
     */
    private static function rowsFromState(array $field, array $state): array
    {
        $rows = [];
        foreach ($state as $item) {
            if (!is_array($item)) {
                continue;
            }
            $row = [];
            foreach (array_keys($field['columns']) as $index => $key) {
                $value = trim((string) ($item[($field['tuple'] ?? false) ? 'c' . $index : $key] ?? ''));
                $numeric = in_array($index, $field['numeric'] ?? [], true) && is_numeric($value);
                $row[($field['tuple'] ?? false) ? $index : $key] = $numeric ? $value + 0 : $value;
            }
            if (implode('', array_map('strval', $row)) !== '') {
                $rows[] = $row;
            }
        }

        return $rows;
    }

    /** @param array<mixed> $config */
    private static function get(array $config, string $path, mixed $default): mixed
    {
        foreach (explode('.', $path) as $key) {
            if (!is_array($config) || !array_key_exists($key, $config)) {
                return $default;
            }
            $config = $config[$key];
        }

        return $config;
    }

    /** @param array<mixed> $config */
    private static function set(array &$config, string $path, mixed $value): void
    {
        $keys = explode('.', $path);
        $last = array_pop($keys);
        $target = &$config;
        foreach ($keys as $key) {
            if (!isset($target[$key]) || !is_array($target[$key])) {
                $target[$key] = [];
            }
            $target = &$target[$key];
        }
        $target[$last] = $value;
    }
}
