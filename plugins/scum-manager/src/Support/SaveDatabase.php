<?php

namespace MrExclusive\ScumManager\Support;

use PDO;
use RuntimeException;

/**
 * Reads a copy of SCUM's save database (SCUM/Saved/SaveFiles/SCUM.db, SQLite): player profiles,
 * bank balances, fame, inventories, squads, vehicles and bases. Only ever opened on a copy,
 * never on the live file, and only read.
 */
final class SaveDatabase
{
    private PDO $pdo;

    public function __construct(string $path)
    {
        if (!is_file($path)) {
            throw new RuntimeException('The save database copy is missing.');
        }
        $header = (string) file_get_contents($path, false, null, 0, 16);
        if ($header !== "SQLite format 3\0") {
            throw new RuntimeException('SCUM.db is not an SQLite database (or the copy is incomplete).');
        }

        $this->pdo = new PDO('sqlite:' . $path, null, null, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
        $this->pdo->exec('PRAGMA query_only = ON');
    }

    /**
     * Tables with their columns and row counts.
     *
     * @return array<string, array{rows: int, columns: list<array{name: string, type: string, pk: bool}>}>
     */
    public function schema(): array
    {
        $tables = [];
        $names = $this->pdo->query("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")->fetchAll(PDO::FETCH_COLUMN);
        foreach ($names as $name) {
            $quoted = '"' . str_replace('"', '""', $name) . '"';
            $columns = array_map(fn (array $column) => [
                'name' => (string) $column['name'],
                'type' => (string) $column['type'],
                'pk' => (int) $column['pk'] > 0,
            ], $this->pdo->query("PRAGMA table_info($quoted)")->fetchAll());
            $tables[$name] = [
                'rows' => (int) $this->pdo->query("SELECT COUNT(*) FROM $quoted")->fetchColumn(),
                'columns' => $columns,
            ];
        }

        return $tables;
    }

    /** SCUM's ECurrencyType (from the game): 1 Normal (cash), 2 Gold. */
    private const CASH = 1;

    private const GOLD = 2;

    /** SCUM's EConZSquadMemberRank (from the game). */
    public const SQUAD_RANKS = [0 => 'None', 1 => 'Member', 2 => 'Enforcer', 3 => 'Underboss', 4 => 'Boss'];

    /**
     * What the save knows about each player, keyed by SteamID64.
     *
     * @return array<string, array{steamId: string, name: string, profileId: int, prisonerId: ?int, fame: float, profileMoney: int, cash: ?int, gold: ?int, playtime: int, alive: ?bool, squad: string, squadRank: string, stats: array<string, float|int>}>
     */
    public function players(): array
    {
        $players = [];
        $byProfile = [];
        $rows = $this->rows('SELECT up.id, up.user_id, up.name, up.fame_points, up.money_balance, up.play_time, up.prisoner_id FROM user_profile up');
        foreach ($rows as $row) {
            $steamId = (string) $row['user_id'];
            if (!preg_match('/^7656\d{13}$/', $steamId)) {
                continue; // the server's own profile and non-Steam entries
            }
            $players[$steamId] = [
                'steamId' => $steamId,
                'name' => (string) $row['name'],
                'profileId' => (int) $row['id'],
                'prisonerId' => $row['prisoner_id'] !== null ? (int) $row['prisoner_id'] : null,
                'fame' => round((float) $row['fame_points'], 1),
                'profileMoney' => (int) $row['money_balance'],
                'cash' => null,
                'gold' => null,
                'playtime' => (int) $row['play_time'],
                'alive' => null,
                'squad' => '',
                'squadRank' => '',
                'stats' => [],
            ];
            $byProfile[(int) $row['id']] = $steamId;
        }

        $bank = $this->rows('SELECT r.account_owner_user_profile_id AS profile, c.currency_type AS type, SUM(c.account_balance) AS balance
            FROM bank_account_registry r JOIN bank_account_registry_currencies c ON c.bank_account_id = r.id
            GROUP BY r.account_owner_user_profile_id, c.currency_type');
        foreach ($bank as $row) {
            $steamId = $byProfile[(int) $row['profile']] ?? null;
            if ($steamId !== null && (int) $row['type'] === self::CASH) {
                $players[$steamId]['cash'] = (int) $row['balance'];
            } elseif ($steamId !== null && (int) $row['type'] === self::GOLD) {
                $players[$steamId]['gold'] = (int) $row['balance'];
            }
        }

        foreach ($this->rows('SELECT sm.user_profile_id AS profile, sm.rank, s.name FROM squad_member sm JOIN squad s ON s.id = sm.squad_id') as $row) {
            if ($steamId = $byProfile[(int) $row['profile']] ?? null) {
                $players[$steamId]['squad'] = (string) $row['name'];
                $players[$steamId]['squadRank'] = self::SQUAD_RANKS[(int) $row['rank']] ?? '';
            }
        }

        foreach ($this->rows('SELECT id, is_alive FROM prisoner') as $row) {
            foreach ($players as $steamId => $player) {
                if ($player['prisonerId'] === (int) $row['id']) {
                    $players[$steamId]['alive'] = (bool) $row['is_alive'];
                }
            }
        }

        $stats = $this->rows('SELECT user_profile_id AS profile, kills, deaths, prisoner_kills, headshots, shots_fired, shots_hit,
            longest_kill_distance, minutes_survived, puppets_killed, animals_killed, locks_picked, containers_looted FROM survival_stats');
        foreach ($stats as $row) {
            if ($steamId = $byProfile[(int) $row['profile']] ?? null) {
                unset($row['profile']);
                $players[$steamId]['stats'] = array_map(fn ($value) => is_numeric($value) ? $value + 0 : 0, $row);
            }
        }

        return $players;
    }

    /**
     * What a player's character carries: every entity below their prisoner entity, with stack
     * sizes where the save has them. Experimental: follows parent_entity_id.
     *
     * @return list<array{item: string, class: string, quantity: ?int, depth: int}>
     */
    public function inventory(int $prisonerId, int $limit = 300): array
    {
        $rows = $this->rows('WITH RECURSIVE tree(id, depth) AS (
                SELECT entity_id, 0 FROM prisoner_entity WHERE prisoner_id = :prisoner
                UNION ALL
                SELECT e.id, t.depth + 1 FROM entity e JOIN tree t ON e.parent_entity_id = t.id WHERE t.depth < 8
            )
            SELECT e.class, t.depth,
                (SELECT SUM(d.quantity) FROM entity_component ec JOIN discrete_amount_entity_component d ON d.entity_component_id = ec.id WHERE ec.entity_id = e.id) AS quantity
            FROM tree t JOIN entity e ON e.id = t.id
            WHERE t.depth > 0
            ORDER BY t.depth, e.class
            LIMIT ' . max(1, $limit), ['prisoner' => $prisonerId]);

        return array_map(fn (array $row) => [
            'item' => self::itemName((string) $row['class']),
            'class' => (string) $row['class'],
            'quantity' => $row['quantity'] !== null ? (int) $row['quantity'] : null,
            'depth' => (int) $row['depth'],
        ], $rows);
    }

    /**
     * Every base in the save, biggest first: where it is, who owns it, how many building parts
     * and flags it has, and who is taking it over (if anyone).
     *
     * @return list<array{id: int, name: string, x: float, y: float, owner: string, ownerId: string, elements: int, flags: int, overtaker: string}>
     */
    public function bases(): array
    {
        $rows = $this->rows('SELECT b.id, b.name, b.location_x, b.location_y, up.name AS owner, up.user_id AS owner_id,
                (SELECT COUNT(*) FROM base_element e WHERE e.base_id = b.id) AS elements,
                (SELECT COUNT(*) FROM base_element_flag f JOIN base_element e ON e.element_id = f.element_id WHERE e.base_id = b.id) AS flags,
                (SELECT o.name FROM base_element_flag f JOIN base_element e ON e.element_id = f.element_id
                    LEFT JOIN user_profile o ON o.id = f.overtaker_user_profile_id
                    WHERE e.base_id = b.id AND f.overtaker_user_profile_id > 0 LIMIT 1) AS overtaker
            FROM base b LEFT JOIN user_profile up ON up.id = b.owner_user_profile_id
            ORDER BY elements DESC, b.id');

        return array_map(fn (array $row) => [
            'id' => (int) $row['id'],
            'name' => (string) ($row['name'] ?? ''),
            'x' => (float) $row['location_x'],
            'y' => (float) $row['location_y'],
            'owner' => (string) ($row['owner'] ?? ''),
            'ownerId' => preg_match('/^7656\d{13}$/', (string) $row['owner_id']) ? (string) $row['owner_id'] : '',
            'elements' => (int) $row['elements'],
            'flags' => (int) $row['flags'],
            'overtaker' => (string) ($row['overtaker'] ?? ''),
        ], $rows);
    }

    /** "BP_Weapon_AK47_C" -> "Weapon AK47" */
    public static function itemName(string $class): string
    {
        $name = preg_replace(['/^(BPC?|BP_Item)_/', '/_C$/'], '', $class);

        return trim(str_replace('_', ' ', (string) $name)) ?: $class;
    }

    /** @return list<array<string, mixed>> rows, or none when a table SCUM no longer has is asked for */
    private function rows(string $sql, array $params = []): array
    {
        try {
            $statement = $this->pdo->prepare($sql);
            $statement->execute($params);

            return $statement->fetchAll();
        } catch (\PDOException) {
            return [];
        }
    }

    /**
     * A plain-text report of the schema: table names, column names and types, row counts.
     * No row contents, so it holds no player data and can be shared.
     */
    public function schemaReport(string $server, string $generatedAt): string
    {
        $lines = [
            'ExclsvSCUM save database scan (schema only, no player data)',
            "Server: $server",
            "Generated: $generatedAt",
            '',
        ];
        foreach ($this->schema() as $table => $info) {
            $lines[] = "== $table ({$info['rows']} rows)";
            foreach ($info['columns'] as $column) {
                $lines[] = '   ' . $column['name'] . ($column['type'] !== '' ? ' ' . $column['type'] : '') . ($column['pk'] ? ' PRIMARY KEY' : '');
            }
            $lines[] = '';
        }

        return implode("\n", $lines);
    }
}
