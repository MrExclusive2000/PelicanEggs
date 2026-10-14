<?php

namespace MrExclusive\ScumManager\Support;

use InvalidArgumentException;

/**
 * Daily restarts set in one place: a Pelican schedule per time (power restart) and ExclsvMessages'
 * countdown warnings for the same times. Pelican runs schedules in UTC, and so do the warnings.
 */
final class RestartPlan
{
    /** Our schedules are recognised by this name prefix; other schedules are never touched. */
    public const NAME_PREFIX = 'ExclsvSCUM restart';

    /** Warnings further ahead than this make no sense for a restart countdown. */
    public const MAX_WARNING_MINUTES = 180;

    /**
     * "6:00, 18:00" or one per line -> ["06:00", "18:00"], sorted, without duplicates.
     *
     * @return list<string>
     */
    public static function parseTimes(string $text): array
    {
        $times = [];
        foreach (preg_split('/[\s,;]+/', trim($text)) ?: [] as $part) {
            if ($part === '') {
                continue;
            }
            if (!preg_match('/^(\d{1,2}):(\d{2})$/', $part, $match) || (int) $match[1] > 23 || (int) $match[2] > 59) {
                throw new InvalidArgumentException("\"$part\" is not a time: use HH:MM, 24-hour (e.g. 06:00).");
            }
            $times[sprintf('%02d:%02d', $match[1], $match[2])] = true;
        }
        $times = array_keys($times);
        sort($times);

        return $times;
    }

    /**
     * "30, 15, 5, 1" -> [30, 15, 5, 1], largest first.
     *
     * @return list<int>
     */
    public static function parseWarnings(string $text): array
    {
        $minutes = [];
        foreach (preg_split('/[\s,;]+/', trim($text)) ?: [] as $part) {
            if ($part === '') {
                continue;
            }
            if (!preg_match('/^\d+$/', $part) || (int) $part < 1 || (int) $part > self::MAX_WARNING_MINUTES) {
                throw new InvalidArgumentException("\"$part\" is not a number of minutes from 1 to " . self::MAX_WARNING_MINUTES . '.');
            }
            $minutes[(int) $part] = true;
        }
        $minutes = array_keys($minutes);
        rsort($minutes);

        return $minutes;
    }

    public static function scheduleName(string $time): string
    {
        return self::NAME_PREFIX . " $time UTC";
    }

    public static function isOurs(string $name): bool
    {
        return str_starts_with($name, self::NAME_PREFIX);
    }

    /** @return array{minute: string, hour: string} cron fields for a daily run at $time */
    public static function cron(string $time): array
    {
        [$hour, $minute] = explode(':', $time);

        return ['minute' => (string) (int) $minute, 'hour' => (string) (int) $hour];
    }

    /** The daily time a schedule runs at, or null when it is not a plain once-a-day schedule. */
    public static function timeOf(string $minute, string $hour, string $dayOfMonth = '*', string $month = '*', string $dayOfWeek = '*'): ?string
    {
        if (!ctype_digit($minute) || !ctype_digit($hour) || $dayOfMonth !== '*' || $month !== '*' || $dayOfWeek !== '*') {
            return null;
        }

        return (int) $hour <= 23 && (int) $minute <= 59 ? sprintf('%02d:%02d', $hour, $minute) : null;
    }

    /**
     * Whether the schedules and the warnings agree.
     *
     * @param  list<string>  $scheduled  times our schedules restart at
     * @param  list<string>  $warned  ExclsvMessages' restartTimes
     * @return array{inSync: bool, noWarning: list<string>, noRestart: list<string>}
     */
    public static function compare(array $scheduled, array $warned): array
    {
        $warned = array_map(fn ($time) => preg_match('/^(\d{1,2}):(\d{2})$/', trim((string) $time), $m) ? sprintf('%02d:%02d', $m[1], $m[2]) : trim((string) $time), $warned);
        $noWarning = array_values(array_diff($scheduled, $warned));
        $noRestart = array_values(array_diff($warned, $scheduled));

        return ['inSync' => $noWarning === [] && $noRestart === [], 'noWarning' => $noWarning, 'noRestart' => $noRestart];
    }
}
