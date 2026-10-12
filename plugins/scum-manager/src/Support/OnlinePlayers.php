<?php

namespace MrExclusive\ScumManager\Support;

/**
 * PlayerTools' online.tsv: who is online and where, rewritten every 15 seconds while the
 * server runs.
 *
 *   # updated <unix time>
 *   steamId <tab> name <tab> x <tab> y <tab> z <tab> place <tab> vehicle <tab> admin <tab> online seconds
 */
final class OnlinePlayers
{
    /** Older than this, the list is not current (server stopped, crashed or the mod is off). */
    public const FRESH_SECONDS = 60;

    /**
     * @return array{updated: ?int, fresh: bool, players: list<array{steamId: string, name: string, x: ?int, y: ?int, z: ?int, place: string, vehicle: bool, admin: bool, seconds: int}>}
     */
    public static function parse(?string $tsv, int $now): array
    {
        $updated = null;
        $players = [];

        foreach (explode("\n", str_replace("\r\n", "\n", $tsv ?? '')) as $line) {
            if (preg_match('/^# updated (\d+)$/', trim($line), $match)) {
                $updated = (int) $match[1];
                continue;
            }
            $parts = explode("\t", $line);
            if (count($parts) < 9 || trim($parts[1]) === '') {
                continue;
            }
            $coordinate = fn (string $value) => preg_match('/^-?\d+$/', trim($value)) ? (int) $value : null;
            $players[] = [
                'steamId' => preg_match('/^\d{17}$/', $parts[0]) ? $parts[0] : '',
                'name' => trim($parts[1]),
                'x' => $coordinate($parts[2]),
                'y' => $coordinate($parts[3]),
                'z' => $coordinate($parts[4]),
                'place' => trim($parts[5]),
                'vehicle' => trim($parts[6]) === '1',
                'admin' => trim($parts[7]) === '1',
                'seconds' => max(0, (int) $parts[8]),
            ];
        }

        usort($players, fn (array $a, array $b) => strcasecmp($a['name'], $b['name']));
        $fresh = $updated !== null && $now - $updated <= self::FRESH_SECONDS;

        return ['updated' => $updated, 'fresh' => $fresh, 'players' => $fresh ? $players : []];
    }

    /** "2 h 05 min", "12 min", "40 s" */
    public static function duration(int $seconds): string
    {
        return match (true) {
            $seconds >= 3600 => sprintf('%d h %02d min', intdiv($seconds, 3600), intdiv($seconds % 3600, 60)),
            $seconds >= 60 => intdiv($seconds, 60) . ' min',
            default => $seconds . ' s',
        };
    }

    /** "in sector B2 (X=123400 Y=-56700 Z=8900)": centimetres, as the teleport commands take them. */
    public static function where(array $player): string
    {
        if ($player['x'] === null || $player['y'] === null) {
            return 'unknown (not spawned)';
        }
        $coordinates = sprintf('X=%d Y=%d Z=%d', $player['x'], $player['y'], $player['z'] ?? 0);

        return $player['place'] !== '' ? "{$player['place']} ($coordinates)" : $coordinates;
    }
}
