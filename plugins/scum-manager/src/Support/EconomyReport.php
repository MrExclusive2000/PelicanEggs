<?php

namespace MrExclusive\ScumManager\Support;

/**
 * The Economy page's numbers, from ExclsvPlayerTools' economy.log:
 *   <unix time> <tab> SteamID <tab> name <tab> amount (+ paid to the player, - taken) <tab> what for
 * and lottery.tsv ("draw <tab> time", then "SteamID <tab> name <tab> tickets").
 */
final class EconomyReport
{
    /** Category => [label, pattern matched against "what for"], first match wins. */
    public const CATEGORIES = [
        'shop' => ['Shop purchases', '/^\d+ x /'],
        'refund' => ['Shop refunds', '/^refund:/'],
        'sell' => ['Sold to the server', '/^sold /'],
        'paySent' => ['Payments sent (with fee)', '/^a payment to /'],
        'payReceived' => ['Payments received', '/^payment from /'],
        'lotteryTickets' => ['Lottery tickets', '/lottery ticket/'],
        'lotteryWin' => ['Lottery wins', '/^lottery win/'],
        'lotteryRefund' => ['Lottery refunds', '/^lottery refund/'],
        'tasks' => ['Daily tasks', '/^daily task/'],
        'race' => ['Kill race', '/^kill race/'],
        'squad' => ['Squad bonus', '/^squad bonus/'],
        'daily' => ['Daily bonus', '/^daily bonus/'],
        'playtime' => ['Playtime rewards', '/^playtime reward/'],
        'starter' => ['Starter kits', '/^starter kit/'],
        'events' => ['Manhunt and King of the Hill', '/^(manhunt|King of the Hill)/'],
        'bountyPlaced' => ['Bounties placed', '/^bounty placed/'],
        'bountyCollected' => ['Bounties collected', '/^bounty collected/'],
        'teleport' => ['Teleports', '/^teleport/'],
    ];

    /**
     * @return list<array{time: int, steamId: string, name: string, amount: int, what: string, category: string}>
     */
    public static function parse(?string $log, int $from = 0): array
    {
        $entries = [];
        foreach (explode("\n", str_replace("\r\n", "\n", $log ?? '')) as $line) {
            $fields = explode("\t", $line);
            if (count($fields) < 5 || !ctype_digit($fields[0]) || !preg_match('/^-?\d+$/', $fields[3]) || (int) $fields[0] < $from) {
                continue;
            }
            $what = trim($fields[4]);
            $entries[] = [
                'time' => (int) $fields[0], 'steamId' => trim($fields[1]), 'name' => trim($fields[2]),
                'amount' => (int) $fields[3], 'what' => $what, 'category' => self::category($what),
            ];
        }
        usort($entries, fn ($a, $b) => $a['time'] <=> $b['time']);

        return $entries;
    }

    public static function category(string $what): string
    {
        foreach (self::CATEGORIES as $key => [, $pattern]) {
            if (preg_match($pattern, $what)) {
                return $key;
            }
        }

        return 'other';
    }

    public static function label(string $category): string
    {
        return self::CATEGORIES[$category][0] ?? 'Other';
    }

    /**
     * Totals per category, money paid out and taken in, and the net change.
     *
     * @return array{categories: array<string, array{count: int, total: int}>, paidOut: int, takenIn: int, net: int}
     */
    public static function totals(array $entries): array
    {
        $categories = [];
        $paidOut = 0;
        $takenIn = 0;
        foreach ($entries as $entry) {
            $categories[$entry['category']] ??= ['count' => 0, 'total' => 0];
            $categories[$entry['category']]['count']++;
            $categories[$entry['category']]['total'] += $entry['amount'];
            if ($entry['amount'] > 0) {
                $paidOut += $entry['amount'];
            } else {
                $takenIn -= $entry['amount'];
            }
        }
        uasort($categories, fn ($a, $b) => abs($b['total']) <=> abs($a['total']));

        return ['categories' => $categories, 'paidOut' => $paidOut, 'takenIn' => $takenIn, 'net' => $paidOut - $takenIn];
    }

    /**
     * Players by money received from the mod (earned) and spent through it.
     *
     * @return array{earners: list<array{name: string, steamId: string, amount: int}>, spenders: list<array{name: string, steamId: string, amount: int}>}
     */
    public static function players(array $entries, int $limit = 10): array
    {
        $earned = [];
        $spent = [];
        $names = [];
        foreach ($entries as $entry) {
            $key = $entry['steamId'] !== '' ? $entry['steamId'] : $entry['name'];
            $names[$key] = $entry['name'];
            if ($entry['amount'] > 0) {
                $earned[$key] = ($earned[$key] ?? 0) + $entry['amount'];
            } else {
                $spent[$key] = ($spent[$key] ?? 0) - $entry['amount'];
            }
        }
        $list = function (array $totals) use ($names, $limit) {
            arsort($totals);
            $rows = [];
            foreach (array_slice($totals, 0, $limit, true) as $key => $amount) {
                $rows[] = ['name' => $names[$key], 'steamId' => ctype_digit((string) $key) ? (string) $key : '', 'amount' => $amount];
            }

            return $rows;
        };

        return ['earners' => $list($earned), 'spenders' => $list($spent)];
    }

    /** @return array{draw: ?int, tickets: int, players: int} */
    public static function lottery(?string $tsv): array
    {
        $draw = null;
        $tickets = 0;
        $players = 0;
        foreach (explode("\n", str_replace("\r\n", "\n", $tsv ?? '')) as $line) {
            $fields = explode("\t", trim($line));
            if ($fields[0] === 'draw' && isset($fields[1]) && ctype_digit($fields[1])) {
                $draw = (int) $fields[1];
            } elseif (count($fields) >= 3 && ctype_digit($fields[0]) && ctype_digit($fields[2]) && (int) $fields[2] > 0) {
                $tickets += (int) $fields[2];
                $players++;
            }
        }

        return ['draw' => $draw, 'tickets' => $tickets, 'players' => $players];
    }

    /**
     * Bank money from the save: total and the richest players.
     *
     * @param  array<string, array{name: string, cash: ?int, gold: ?int}>  $savePlayers
     * @return array{cash: int, gold: int, players: int, richest: list<array{name: string, steamId: string, cash: int, gold: int}>}
     */
    public static function circulation(array $savePlayers, int $limit = 10): array
    {
        $cash = 0;
        $gold = 0;
        $rows = [];
        foreach ($savePlayers as $steamId => $player) {
            $playerCash = (int) ($player['cash'] ?? 0);
            $playerGold = (int) ($player['gold'] ?? 0);
            $cash += $playerCash;
            $gold += $playerGold;
            $rows[] = ['name' => (string) $player['name'], 'steamId' => (string) $steamId, 'cash' => $playerCash, 'gold' => $playerGold];
        }
        usort($rows, fn ($a, $b) => $b['cash'] <=> $a['cash']);

        return ['cash' => $cash, 'gold' => $gold, 'players' => count($rows), 'richest' => array_slice($rows, 0, $limit)];
    }
}
