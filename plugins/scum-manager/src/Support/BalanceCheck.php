<?php

namespace MrExclusive\ScumManager\Support;

/**
 * What the last save says a player has, shown next to money commands, and the check that stops
 * an admin taking more money than the player has.
 */
final class BalanceCheck
{
    /** "Bank: 15,000 cash, 3 gold. Fame: 120.6 (from the save 4 min ago)." or null when unknown. */
    public static function summary(?array $saved, ?int $readAt, int $now): ?string
    {
        if ($saved === null) {
            return null;
        }
        $age = $readAt !== null ? ' (from the save ' . OnlinePlayers::duration(max(0, $now - $readAt)) . ' ago)' : '';

        return sprintf('Bank: %s cash, %s gold. Fame: %s%s.',
            $saved['cash'] !== null ? number_format((int) $saved['cash']) : '?',
            $saved['gold'] !== null ? number_format((int) $saved['gold']) : '?',
            (string) ($saved['fame'] ?? '?'),
            $age);
    }

    /** Why taking this much is refused, or null when it is fine (adding money, or enough cash, or no data). */
    public static function shortfall(?array $saved, int $amount): ?string
    {
        if ($amount >= 0 || $saved === null || $saved['cash'] === null) {
            return null;
        }
        $cash = (int) $saved['cash'];
        if (-$amount <= $cash) {
            return null;
        }

        return sprintf('They only have %s cash in the last save, so taking %s would leave them at %s. Reload save data if they earned money since, or switch on "Take it anyway".',
            number_format($cash), number_format(-$amount), number_format($cash + $amount));
    }
}
