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
