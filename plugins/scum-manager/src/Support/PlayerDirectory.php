<?php

namespace MrExclusive\ScumManager\Support;

/**
 * Everything known about each player, from every file that mentions them:
 *   - PlayerTools' players.tsv (name, kills, deaths, playtime, first and last seen, bounty)
 *   - PlayerTools' online.tsv (who is on now, and where)
 *   - SCUM's player lists (AdminUsers.ini, BannedUsers.ini, WhitelistedUsers.ini, ...)
 *   - ScumAntiCheat's offenses.txt (how often the anti-cheat kicked them)
 *   - SCUM's save database (bank balances, fame, squad, alive; see SaveDatabase::players())
 */
final class PlayerDirectory
{
    /** List file => flag name. */
    public const LISTS = [
        'AdminUsers.ini' => 'admin',
        'ServerSettingsAdminUsers.ini' => 'settingsAdmin',
        'WhitelistedUsers.ini' => 'whitelisted',
        'ExclusiveUsers.ini' => 'exclusive',
        'BannedUsers.ini' => 'banned',
        'SilencedUsers.ini' => 'silenced',
    ];

    /**
     * @param  array<string, ?string>  $lists  list file => its contents
     * @param  list<array<string, mixed>>  $online  OnlinePlayers::parse()['players']
     * @return array<string, array{steamId: string, name: string, kills: int, deaths: int, playtime: int, longest: int, bounty: int, first: int, lastSeen: int, online: bool, where: string, vehicle: bool, kicks: int, flags: array<string, bool>}>
     *         keyed by SteamID, most recently seen first
     */
    public static function build(?string $playersTsv, array $online, array $lists, ?string $offenses, array $save = []): array
    {
        $players = [];
        $player = function (string $id) use (&$players) {
            return $players[$id] ??= [
                'steamId' => $id, 'name' => '', 'kills' => 0, 'deaths' => 0, 'playtime' => 0, 'longest' => 0,
                'bounty' => 0, 'first' => 0, 'lastSeen' => 0, 'online' => false, 'where' => '', 'vehicle' => false,
                'kicks' => 0, 'flags' => array_fill_keys(array_values(self::LISTS), false), 'save' => null,
            ];
        };

        // players.tsv: id, name, kills, deaths, playtime, longest, kit, first, rewarded, daily, bestStreak, bounty, owed, lastSeen
        foreach (self::lines($playersTsv) as $line) {
            $parts = explode("\t", $line);
            if (!self::isSteamId($parts[0] ?? '')) {
                continue;
            }
            $entry = $player($parts[0]);
            $entry['name'] = trim($parts[1] ?? '');
            $entry['kills'] = (int) ($parts[2] ?? 0);
            $entry['deaths'] = (int) ($parts[3] ?? 0);
            $entry['playtime'] = (int) ($parts[4] ?? 0);
            $entry['longest'] = (int) ($parts[5] ?? 0);
            $entry['first'] = (int) ($parts[7] ?? 0);
            $entry['bounty'] = (int) ($parts[11] ?? 0);
            $entry['lastSeen'] = (int) ($parts[13] ?? 0);
            $players[$parts[0]] = $entry;
        }

        foreach ($online as $now) {
            if (!self::isSteamId($now['steamId'] ?? '')) {
                continue;
            }
            $entry = $player($now['steamId']);
            $entry['name'] = $now['name'] ?: $entry['name'];
            $entry['online'] = true;
            $entry['where'] = OnlinePlayers::where($now);
            $entry['vehicle'] = (bool) $now['vehicle'];
            $players[$now['steamId']] = $entry;
        }

        foreach (self::LISTS as $file => $flag) {
            foreach (self::lines($lists[$file] ?? null) as $line) {
                if (preg_match('/^\s*(\d{17})\b/', $line, $match) && self::isSteamId($match[1])) {
                    $entry = $player($match[1]);
                    $entry['flags'][$flag] = true;
                    $players[$match[1]] = $entry;
                }
            }
        }

        // offenses.txt: "<SteamID> <kicks>"
        foreach (self::lines($offenses) as $line) {
            if (preg_match('/^(\d{17})\s+(\d+)$/', trim($line), $match) && self::isSteamId($match[1])) {
                $entry = $player($match[1]);
                $entry['kicks'] = (int) $match[2];
                $players[$match[1]] = $entry;
            }
        }

        foreach ($save as $steamId => $saved) {
            $steamId = (string) $steamId;
            if (!self::isSteamId($steamId)) {
                continue;
            }
            $entry = $player($steamId);
            $entry['name'] = $entry['name'] !== '' ? $entry['name'] : (string) ($saved['name'] ?? '');
            $entry['save'] = $saved;
            $players[$steamId] = $entry;
        }

        uasort($players, fn (array $a, array $b) => [$b['online'], $b['lastSeen'], $a['name']] <=> [$a['online'], $a['lastSeen'], $b['name']]);

        return $players;
    }

    /** Players matching a search (name or SteamID, case-insensitive). */
    public static function search(array $players, ?string $search): array
    {
        $search = strtolower(trim((string) $search));
        if ($search === '') {
            return $players;
        }

        return array_filter($players, fn (array $p) => str_contains(strtolower($p['name']), $search) || str_contains($p['steamId'], $search));
    }

    /**
     * The list file with the player added or removed, keeping every other line (and any
     * [permission] suffixes) as it was.
     */
    public static function setMembership(?string $contents, string $steamId, bool $member): string
    {
        if (!self::isSteamId($steamId)) {
            throw new \InvalidArgumentException('Not a SteamID64.');
        }
        $eol = str_contains((string) $contents, "\r\n") || $contents === null || $contents === '' ? "\r\n" : "\n";
        $kept = [];
        $present = false;
        foreach (self::lines($contents) as $line) {
            if (preg_match('/^\s*' . $steamId . '\b/', $line)) {
                $present = true;
                if (!$member) {
                    continue;
                }
            }
            $kept[] = $line;
        }
        if ($member && !$present) {
            $kept[] = $steamId;
        }

        return $kept === [] ? '' : implode($eol, $kept) . $eol;
    }

    public static function isSteamId(string $value): bool
    {
        return (bool) preg_match('/^7656\d{13}$/', $value);
    }

    /** @return list<string> non-empty lines */
    private static function lines(?string $text): array
    {
        return array_values(array_filter(
            explode("\n", str_replace("\r\n", "\n", $text ?? '')),
            fn (string $line) => trim($line) !== '',
        ));
    }
}
