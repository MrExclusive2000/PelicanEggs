<?php

namespace MrExclusive\ScumManager\Support;

/**
 * The parts of the Overview page that only look at text: which anti-cheat lines matter, signs
 * of a crash in a log, the newest crash report folder and how a mod's version compares.
 */
final class Overview
{
    /** Anti-cheat lines worth an admin's attention (not start-up, reload or check-failure noise). */
    private const ANTICHEAT_PATTERNS = [
        '/\[strike \d+\/\d+\]/',
        '/\bKicked\b|\bBanned\b|has now been kicked/',
        '/\bSUSPECT\b|\bSPECTATE\b/',
        '/while aiming at least|snapped \d+ degrees/',
        '/has admin rights but|ran an admin command but/',
        '/Watchlisted player online/',
        '/nothing was done/',
        '/Possible vehicle glitch/',
    ];

    /** Lines in a UE4SS or SCUM log that point at a crash. */
    private const CRASH_PATTERN = '/unhandled exception|access violation|fatal error|exception_|crash(ed)?\b|stack trace|assertion failed/i';

    /** The newest matching anti-cheat lines, newest first. */
    public static function antiCheatEvents(string $log, int $limit = 15): array
    {
        $events = [];
        foreach (array_reverse(explode("\n", str_replace("\r\n", "\n", $log))) as $line) {
            $line = trim($line);
            if ($line === '') {
                continue;
            }
            foreach (self::ANTICHEAT_PATTERNS as $pattern) {
                if (preg_match($pattern, $line)) {
                    $events[] = $line;
                    break;
                }
            }
            if (count($events) >= $limit) {
                break;
            }
        }

        return $events;
    }

    /** Log lines that look like a crash, in order (at most $limit, the last ones). */
    public static function crashLines(string $log, int $limit = 8): array
    {
        $lines = array_values(array_filter(
            array_map('trim', explode("\n", str_replace("\r\n", "\n", $log))),
            fn (string $line) => $line !== '' && preg_match(self::CRASH_PATTERN, $line),
        ));

        return array_slice($lines, -$limit);
    }

    /**
     * The newest crash report folder (SCUM/Saved/Crashes), or null.
     *
     * @param  list<array{name: string, directory: bool, modified: string}>  $entries
     * @return array{name: string, modified: string, count: int}|null
     */
    public static function newestCrash(array $entries): ?array
    {
        $folders = array_values(array_filter($entries, fn (array $entry) => $entry['directory']));
        if ($folders === []) {
            return null;
        }

        usort($folders, fn (array $a, array $b) => strtotime($b['modified'] ?: '0') <=> strtotime($a['modified'] ?: '0'));

        return ['name' => $folders[0]['name'], 'modified' => $folders[0]['modified'], 'count' => count($folders)];
    }

    /**
     * How an installed mod compares with the newest published build.
     *
     * @return array{0: string, 1: string} [label, color]
     */
    public static function modStatus(bool $installed, bool $enabled, ?string $build, ?string $latest): array
    {
        return match (true) {
            !$installed => ['Not installed', 'gray'],
            !$enabled => ['Disabled', 'warning'],
            $latest === null || $build === null => ['Installed', 'success'],
            $build === $latest => ['Up to date', 'success'],
            default => ['Update available', 'info'],
        };
    }
}
