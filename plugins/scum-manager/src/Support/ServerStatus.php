<?php

namespace MrExclusive\ScumManager\Support;

/**
 * What the Console page shows about the running server: ExclsvConsole's status.txt (the newest
 * "Global Stats" line from SCUM.log), ExclsvPlayerTools' deaths.log, and Wings' resource figures.
 */
final class ServerStatus
{
    /** status.txt is rewritten every 5 seconds; older than this, the server is not running it. */
    public const FRESH_SECONDS = 30;

    /**
     * status.txt:
     *   # updated <unix time>
     *   [..]LogSCUM: Global Stats:  32.4ms ( 30.8FPS),  38.1ms ( 26.2FPS), 400.0ms (  2.5FPS) | C: 1 (1), P: 1 (1), ...
     * The three timings are SCUM's average, slower and slowest frame over the last few seconds.
     *
     * @return array{updated: ?int, fresh: bool, fps: ?float, frameMs: ?float, slowestMs: ?float, players: ?int}
     */
    public static function parse(?string $status, int $now): array
    {
        $result = ['updated' => null, 'fresh' => false, 'fps' => null, 'frameMs' => null, 'slowestMs' => null, 'players' => null];

        foreach (explode("\n", str_replace("\r\n", "\n", $status ?? '')) as $line) {
            if (preg_match('/^# updated (\d+)$/', trim($line), $match)) {
                $result['updated'] = (int) $match[1];
                continue;
            }
            if (!str_contains($line, 'Global Stats:')) {
                continue;
            }
            if (preg_match_all('/([\d.]+)ms \(\s*([\d.]+)FPS\)/', $line, $timings, PREG_SET_ORDER) && count($timings) >= 1) {
                $result['frameMs'] = (float) $timings[0][1];
                $result['fps'] = (float) $timings[0][2];
                $result['slowestMs'] = (float) end($timings)[1];
            }
            if (preg_match('/\bP:\s*(\d+)/', $line, $match)) {
                $result['players'] = (int) $match[1];
            }
        }

        $result['fresh'] = $result['updated'] !== null && $now - $result['updated'] <= self::FRESH_SECONDS;

        return $result;
    }

    /** How the server is keeping up: SCUM runs at about 30 FPS with players on and idles at 5 without. */
    public static function fpsLabel(array $status): array
    {
        if (!$status['fresh'] || $status['fps'] === null) {
            return ['Unknown', 'gray'];
        }
        $text = sprintf('%.1f FPS (%.0f ms a frame, slowest %.0f ms)', $status['fps'], $status['frameMs'], $status['slowestMs']);
        // With nobody on, SCUM idles at about 5 FPS on purpose and speeds up when someone joins.
        if (($status['players'] ?? null) === 0) {
            return [sprintf('Idle: %.1f FPS while nobody is on (normal, SCUM speeds up when a player joins)', $status['fps']), 'gray'];
        }

        return [$text, match (true) {
            $status['fps'] >= 25 => 'success',
            $status['fps'] >= 15 => 'warning',
            default => 'danger',
        }];
    }

    /**
     * The newest deaths first, from deaths.log ("2026-10-11 13:01:00 | Alice (...) killed Bob (...) with AK47, 250 m").
     *
     * @return list<string>
     */
    public static function deaths(?string $log, int $limit = 50): array
    {
        $lines = array_values(array_filter(
            array_map('trim', explode("\n", str_replace("\r\n", "\n", $log ?? ''))),
            fn (string $line) => $line !== '',
        ));

        return array_slice(array_reverse($lines), 0, $limit);
    }

    /** "3.2 GiB" */
    public static function bytes(int|float $bytes): string
    {
        $units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
        $unit = 0;
        while ($bytes >= 1024 && $unit < count($units) - 1) {
            $bytes /= 1024;
            $unit++;
        }

        return ($unit === 0 ? (string) (int) $bytes : sprintf('%.1f', $bytes)) . ' ' . $units[$unit];
    }

    /** Wings reports uptime in milliseconds: "2 d 3 h", "4 h 05 min", "12 min". */
    public static function uptime(int $milliseconds): string
    {
        $seconds = intdiv(max(0, $milliseconds), 1000);
        if ($seconds >= 86400) {
            return sprintf('%d d %d h', intdiv($seconds, 86400), intdiv($seconds % 86400, 3600));
        }

        return OnlinePlayers::duration($seconds);
    }
}
