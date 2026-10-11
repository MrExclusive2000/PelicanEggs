<?php

namespace MrExclusive\ScumManager\Support;

use InvalidArgumentException;

/** Teleport destinations of the PlayerTools mod, filled from PelicanConsole's output. */
final class TeleportDestinations
{
    /**
     * Outposts from the output of PelicanConsole's FindOutposts.
     *
     * @return list<array{name: string, x: int, y: int, z: int}>
     */
    public static function parseOutposts(string $output): array
    {
        preg_match_all('/Outpost (\S+) at (-?\d+) (-?\d+) (-?\d+)/', $output, $matches, PREG_SET_ORDER);

        $outposts = [];
        foreach ($matches as $match) {
            $outposts[$match[1]] = ['name' => $match[1], 'x' => (int) $match[2], 'y' => (int) $match[3], 'z' => (int) $match[4]];
        }

        return array_values($outposts);
    }

    /**
     * A player's position from the output of PelicanConsole's WhereIs.
     *
     * @return array{x: int, y: int, z: int}|null
     */
    public static function parseWhereIs(string $output, string $player): ?array
    {
        if (!preg_match_all('/' . preg_quote($player, '/') . ' is at (-?\d+) (-?\d+) (-?\d+)/i', $output, $matches, PREG_SET_ORDER)) {
            return null;
        }
        $last = end($matches);

        return ['x' => (int) $last[1], 'y' => (int) $last[2], 'z' => (int) $last[3]];
    }

    public static function name(string $name): string
    {
        $name = strtolower(trim($name));
        if (!preg_match('/^[a-z0-9_-]{1,24}$/', $name)) {
            throw new InvalidArgumentException('Destination names are one word (letters, numbers, - or _), as players type them after !tp.');
        }

        return $name;
    }

    /**
     * PlayerTools' config with a King of the Hill zone added (same name replaced).
     *
     * @param  array<mixed>  $config
     * @param  array{name: string, x: int, y: int, z: int}  $zone
     * @return array<mixed>
     */
    public static function addZone(array $config, array $zone, int $radius): array
    {
        $entry = ['name' => self::name($zone['name']), 'x' => $zone['x'], 'y' => $zone['y'], 'z' => $zone['z'], 'radius' => max(10, $radius)];
        $zones = is_array($config['koth']['zones'] ?? null) ? array_values($config['koth']['zones']) : [];
        $zones = array_values(array_filter($zones, fn ($existing) => !is_array($existing) || strtolower((string) ($existing['name'] ?? '')) !== $entry['name']));
        $zones[] = $entry;

        $config['koth'] = is_array($config['koth'] ?? null) ? $config['koth'] : [];
        $config['koth']['zones'] = $zones;

        return $config;
    }

    /**
     * PlayerTools' config with these destinations added. A destination with the same name is replaced.
     *
     * @param  array<mixed>  $config
     * @param  list<array{name: string, x: int, y: int, z: int}>  $destinations
     * @return array<mixed>
     */
    public static function add(array $config, array $destinations, int $price): array
    {
        $locations = is_array($config['teleports']['locations'] ?? null) ? array_values($config['teleports']['locations']) : [];

        foreach ($destinations as $destination) {
            $entry = ['name' => self::name($destination['name']), 'x' => $destination['x'], 'y' => $destination['y'], 'z' => $destination['z'], 'price' => max(0, $price)];
            $replaced = false;
            foreach ($locations as $index => $location) {
                if (is_array($location) && strtolower((string) ($location['name'] ?? '')) === $entry['name']) {
                    $locations[$index] = $entry;
                    $replaced = true;
                }
            }
            if (!$replaced) {
                $locations[] = $entry;
            }
        }

        $config['teleports'] = (is_array($config['teleports'] ?? null) ? $config['teleports'] : []);
        $config['teleports']['locations'] = $locations;

        return $config;
    }
}
