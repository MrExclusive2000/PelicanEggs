<?php

namespace MrExclusive\ScumManager\Support;

/**
 * The Anti-cheat page: ExclsvAntiCheat's flags.tsv (every strike, kick, ban and report, dated)
 * grouped per player, with their kick count (offenses.txt), ban and ignore status and the
 * admins' notes.
 *   flags.tsv: <unix time> <tab> SteamID <tab> name <tab> kind <tab> detail
 */
final class AntiCheatReview
{
    /** kind => [label, weight when sorting players by how worrying they look] */
    public const KINDS = [
        'ban' => ['Bans', 100],
        'kick' => ['Kicks', 30],
        'spectate' => ['Spectate (wallhack)', 20],
        'suspect' => ['Suspect (aimbot)', 15],
        'logonly' => ['Would act', 10],
        'strike' => ['Strikes', 3],
        'glitch' => ['Vehicle glitches', 0],
    ];

    /**
     * @return list<array{time: int, steamId: string, name: string, kind: string, detail: string}>
     */
    public static function parse(?string $tsv, int $from = 0): array
    {
        $flags = [];
        foreach (explode("\n", str_replace("\r\n", "\n", $tsv ?? '')) as $line) {
            $fields = explode("\t", $line);
            if (count($fields) < 5 || !ctype_digit($fields[0]) || (int) $fields[0] < $from || !isset(self::KINDS[trim($fields[3])])) {
                continue;
            }
            $flags[] = [
                'time' => (int) $fields[0], 'steamId' => trim($fields[1]), 'name' => trim($fields[2]),
                'kind' => trim($fields[3]), 'detail' => trim($fields[4]),
            ];
        }
        usort($flags, fn ($a, $b) => $a['time'] <=> $b['time']);

        return $flags;
    }

    /** @return array<string, int> SteamID => times kicked, from offenses.txt */
    public static function offenses(?string $text): array
    {
        $counts = [];
        preg_match_all('/^(\d{17})\s+(\d+)/m', $text ?? '', $matches, PREG_SET_ORDER);
        foreach ($matches as $match) {
            $counts[$match[1]] = (int) $match[2];
        }

        return $counts;
    }

    /** @return list<string> SteamIDs at the start of lines (BannedUsers.ini) */
    public static function steamIds(?string $text): array
    {
        $text = str_replace(["\xFF\xFE", "\xFE\xFF", "\xEF\xBB\xBF", "\0"], '', $text ?? '');   // UTF-16 or UTF-8 BOM
        preg_match_all('/^\s*(\d{17})/m', $text, $matches);

        return array_values(array_unique($matches[1]));
    }

    /**
     * One row per player with flags in the period, most worrying first.
     *
     * @param  array<string, int>  $offenses
     * @param  list<string>  $banned
     * @param  list<string>  $ignored
     * @param  array<string, string>  $notes
     * @return list<array{key: string, steamId: string, name: string, counts: array<string, int>, last: int, lastDetail: string, kicks: int, banned: bool, ignored: bool, note: string, score: int}>
     */
    public static function players(array $flags, array $offenses, array $banned, array $ignored, array $notes): array
    {
        $rows = [];
        foreach ($flags as $flag) {
            $key = $flag['steamId'] !== '' ? $flag['steamId'] : 'name:' . $flag['name'];
            $rows[$key] ??= [
                'key' => $key, 'steamId' => $flag['steamId'], 'name' => $flag['name'], 'counts' => [],
                'last' => 0, 'lastDetail' => '', 'kicks' => 0, 'banned' => false, 'ignored' => false, 'note' => '', 'score' => 0,
            ];
            $row = &$rows[$key];
            $row['name'] = $flag['name'] !== '' ? $flag['name'] : $row['name'];
            $row['counts'][$flag['kind']] = ($row['counts'][$flag['kind']] ?? 0) + 1;
            $row['score'] += self::KINDS[$flag['kind']][1];
            if ($flag['time'] >= $row['last']) {
                $row['last'] = $flag['time'];
                $row['lastDetail'] = self::KINDS[$flag['kind']][0] . ': ' . $flag['detail'];
            }
            unset($row);
        }
        foreach ($rows as &$row) {
            if ($row['steamId'] !== '') {
                $row['kicks'] = $offenses[$row['steamId']] ?? 0;
                $row['banned'] = in_array($row['steamId'], $banned, true);
                $row['ignored'] = in_array($row['steamId'], $ignored, true);
                $row['note'] = $notes[$row['steamId']] ?? '';
            }
        }
        unset($row);
        $rows = array_values($rows);
        usort($rows, fn ($a, $b) => [$b['score'], $b['last']] <=> [$a['score'], $a['last']]);

        return $rows;
    }

    /** "3 strikes, 1 kick" for a row's counts, in KINDS order. */
    public static function countsText(array $counts): string
    {
        $parts = [];
        foreach (self::KINDS as $kind => [$label]) {
            if (($counts[$kind] ?? 0) > 0) {
                $parts[] = $counts[$kind] . ' ' . strtolower($label);
            }
        }

        return implode(', ', $parts);
    }

    /** A note per SteamID, stored as JSON on the server. */
    public static function notes(?string $json): array
    {
        $notes = json_decode($json ?? '', true);

        return is_array($notes) ? array_filter($notes, fn ($note, $id) => is_string($note) && preg_match('/^\d{17}$/', (string) $id), ARRAY_FILTER_USE_BOTH) : [];
    }
}
