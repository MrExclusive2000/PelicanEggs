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
 *   the column positions saved as numbers).
 */
final class ModSettings
{
    public const MODS = [
        'PlayerTools' => [
            'label' => 'Player tools',
            'description' => 'Chat commands, kill feed, stats, AFK kicker, voting and new-player welcome.',
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
                    'description' => 'For a player\'s first join. Placeholders: {name} {steamId}. Starter kit commands are SCUM admin commands (without #) run once per new player as an online admin, e.g. ChangeCurrencyBalance Normal 500 {steamId}. Only use commands that name the player: SpawnItem has no target and would drop items in front of the admin. The kit waits until an admin is online.',
                    'fields' => [
                        'newPlayers.messages' => ['lines', 'Welcome messages (one per line)', []],
                        'newPlayers.starterKit' => ['toggle', 'Starter kit on', true],
                        'newPlayers.starterKitCommands' => ['lines', 'Starter kit commands (one per line)', []],
                        'newPlayers.starterKitMessage' => ['text', 'Message when the kit is given', ''],
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
                    ],
                ],
                'Movement limits' => [
                    'description' => 'Metres, metres per second and seconds.',
                    'fields' => [
                        'maxFootSpeed' => ['int', 'Max speed on foot (m/s)', 15],
                        'maxVehicleSpeed' => ['int', 'Max speed in vehicles (m/s)', 120],
                        'teleportDistance' => ['int', 'Teleport distance (m)', 300],
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
