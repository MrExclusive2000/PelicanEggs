<?php

namespace MrExclusive\ScumManager\Support;

/**
 * Shooting accuracy from SCUM's own lifetime stats (survival_stats in the save). Human players
 * rarely hit more than about a third of their shots over hundreds of shots; aimbots hit far more.
 */
final class Accuracy
{
    /** Below this many shots the hit rate means little. */
    public const MIN_SHOTS = 200;

    /** Hit rate (%) from which a player is worth spectating. */
    public const WATCH_PERCENT = 55;

    /** Hit rate in percent, or null with too few shots to judge. */
    public static function percent(array $stats, int $minShots = self::MIN_SHOTS): ?int
    {
        $fired = (int) ($stats['shots_fired'] ?? 0);
        if ($fired < max(1, $minShots)) {
            return null;
        }

        return (int) round(100 * min($fired, (int) ($stats['shots_hit'] ?? 0)) / $fired);
    }

    public static function suspicious(array $stats): bool
    {
        $percent = self::percent($stats);

        return $percent !== null && $percent >= self::WATCH_PERCENT;
    }
}
