<?php

namespace MrExclusive\ScumManager\Support;

use InvalidArgumentException;

/**
 * The commands offered on the Admin Console page, so admins can pick one instead of typing it.
 *
 * "anytime" commands are handled by the PelicanConsole mod itself and work with nobody in game.
 * The rest are SCUM admin commands, which SCUM only runs for an admin who is in game: the mod
 * runs them as the first online admin from AdminUsers.ini.
 *
 * Field types: text, int (min, max), player (SteamID picked from known players), select (options).
 */
final class AdminCommands
{
    public const COMMANDS = [
        'announce' => [
            'label' => 'Announce a message', 'anytime' => true, 'template' => 'Announce {message}',
            'help' => 'Shows the message on every player\'s screen.',
            'fields' => ['message' => ['text', 'Message']],
        ],
        'listplayers' => [
            'label' => 'List players online', 'anytime' => true, 'template' => 'ListPlayers',
            'help' => 'The list appears in the output below.',
            'fields' => [],
        ],
        'kick' => [
            'label' => 'Kick a player', 'anytime' => true, 'template' => 'Kick {name}',
            'help' => 'Kicks an online player by name.',
            'fields' => ['name' => ['playerName', 'Player']],
        ],
        'whereis' => [
            'label' => 'Where is a player?', 'anytime' => true, 'experimental' => true, 'template' => 'WhereIs {name}',
            'help' => 'Shows the player\'s coordinates, for teleports.',
            'fields' => ['name' => ['playerName', 'Player']],
        ],
        'balance' => [
            'label' => 'Check a player\'s money and fame', 'anytime' => true, 'experimental' => true, 'template' => 'Balance {name}',
            'help' => 'Reads the player\'s money, gold and fame.',
            'fields' => ['name' => ['playerName', 'Player']],
        ],
        'teleportplayer' => [
            'label' => 'Teleport a player to coordinates', 'anytime' => true, 'experimental' => true, 'template' => 'TeleportPlayer {name} {x} {y} {z}',
            'help' => 'Moves the player there directly. Get coordinates with "Where is a player?".',
            'fields' => ['name' => ['playerName', 'Player'], 'x' => ['int', 'X', -10000000, 10000000], 'y' => ['int', 'Y', -10000000, 10000000], 'z' => ['int', 'Z', -1000000, 1000000]],
        ],
        'findoutposts' => [
            'label' => 'List the outposts', 'anytime' => true, 'experimental' => true, 'template' => 'FindOutposts',
            'help' => 'Finds the trader outposts on the map. Use "Add outposts as teleports" to make them !tp destinations.',
            'fields' => [],
        ],
        'finditem' => [
            'label' => 'Find an item name', 'anytime' => true, 'experimental' => true, 'template' => 'FindItem {text}',
            'help' => 'Lists loaded item classes whose name contains the text, e.g. water or bandage.',
            'fields' => ['text' => ['text', 'Part of the name']],
        ],
        'giveitem' => [
            'label' => 'Give an item to a player', 'anytime' => true, 'experimental' => true, 'template' => 'GiveItem {name} {item} {amount}',
            'help' => 'Puts the item in the player\'s inventory (or at their feet if it is full). Use a name from "Find an item name". New: try it on yourself first.',
            'fields' => ['name' => ['playerName', 'Player'], 'item' => ['text', 'Item'], 'amount' => ['int', 'Amount', 1, 10]],
        ],
        'settime' => [
            'label' => 'Set the time of day', 'anytime' => false, 'template' => 'SetTime {hour}',
            'help' => 'Hour from 0 to 23.',
            'fields' => ['hour' => ['int', 'Hour', 0, 23]],
        ],
        'setweather' => [
            'label' => 'Set the weather', 'anytime' => false, 'template' => 'SetWeather {weather}',
            'help' => 'SCUM takes a number from 0 (clear) to 1 (heavy rain).',
            'fields' => ['weather' => ['select', 'Weather', ['0' => 'Clear', '0.5' => 'Cloudy / light rain', '1' => 'Storm']]],
        ],
        'money' => [
            'label' => 'Give or take money', 'anytime' => false, 'template' => 'ChangeCurrencyBalance Normal {amount} {steamId}',
            'help' => 'Adds the amount to the player\'s balance. Use a negative amount to take money.',
            'fields' => ['steamId' => ['player', 'Player'], 'amount' => ['int', 'Amount', -1000000, 1000000]],
        ],
        'fame' => [
            'label' => 'Set fame points', 'anytime' => false, 'template' => 'SetFamePoints {amount} {steamId}',
            'help' => 'Sets the player\'s fame points to this value.',
            'fields' => ['steamId' => ['player', 'Player'], 'amount' => ['int', 'Fame points', 0, 100000]],
        ],
        'teleporttome' => [
            'label' => 'Bring a player to the admin', 'anytime' => false, 'template' => 'TeleportToMe {steamId}',
            'help' => 'Teleports the player to the admin the command runs as.',
            'fields' => ['steamId' => ['player', 'Player']],
        ],
        'teleportto' => [
            'label' => 'Take the admin to a player', 'anytime' => false, 'template' => 'TeleportTo {steamId}',
            'help' => 'Teleports the admin the command runs as to the player.',
            'fields' => ['steamId' => ['player', 'Player']],
        ],
        'spawnitem' => [
            'label' => 'Spawn an item at the admin', 'anytime' => false, 'template' => 'SpawnItem {item} {amount}',
            'help' => 'Drops the item in front of the admin the command runs as. Item IDs are like Emergency_Bandage_Big or 12_Gauge.',
            'fields' => ['item' => ['text', 'Item ID'], 'amount' => ['int', 'Amount', 1, 100]],
        ],
        'ban' => [
            'label' => 'Ban a player', 'anytime' => false, 'template' => 'Ban {steamId}',
            'help' => 'Bans and kicks the player.',
            'fields' => ['steamId' => ['player', 'Player']],
        ],
        'unban' => [
            'label' => 'Unban a player', 'anytime' => false, 'template' => 'Unban {steamId}',
            'help' => 'You can also remove them on the SCUM Player Lists page while the server is stopped.',
            'fields' => ['steamId' => ['player', 'Player']],
        ],
        'custom' => [
            'label' => 'Type a command', 'anytime' => null, 'template' => '{command}',
            'help' => 'Any SCUM admin command, without the #.',
            'fields' => ['command' => ['text', 'Command']],
        ],
    ];

    /** @return array<string, array<string, string>> grouped options for a select */
    public static function options(): array
    {
        $groups = ['Works any time' => [], 'Works any time (experimental)' => [], 'Needs an admin in game' => [], 'Other' => []];
        foreach (self::COMMANDS as $key => $command) {
            $group = match (true) {
                ($command['experimental'] ?? false) => 'Works any time (experimental)',
                $command['anytime'] === true => 'Works any time',
                $command['anytime'] === false => 'Needs an admin in game',
                default => 'Other',
            };
            $groups[$group][$key] = $command['label'];
        }

        return $groups;
    }

    public static function fieldName(string $command, string $field): string
    {
        return $command . '__' . $field;
    }

    /**
     * The command line for the picked command and its field values.
     *
     * @param  array<string, mixed>  $values  field name => value (only this command's fields are read)
     */
    public static function build(string $key, array $values): string
    {
        $command = self::COMMANDS[$key] ?? throw new InvalidArgumentException('Pick a command.');

        $replacements = [];
        foreach ($command['fields'] as $field => $definition) {
            $value = trim((string) ($values[self::fieldName($key, $field)] ?? ''));
            $label = $definition[1];

            if ($value === '') {
                throw new InvalidArgumentException("$label is required.");
            }
            if (preg_match('/[\r\n\x00]/', $value)) {
                throw new InvalidArgumentException("$label must be one line.");
            }

            switch ($definition[0]) {
                case 'int':
                    if (!preg_match('/^-?\d+$/', $value) || (int) $value < $definition[2] || (int) $value > $definition[3]) {
                        throw new InvalidArgumentException("$label must be a whole number from {$definition[2]} to {$definition[3]}.");
                    }
                    break;
                case 'player':
                    if (!preg_match('/^7656\d{13}$/', $value)) {
                        throw new InvalidArgumentException("$label must be a SteamID64 (17 digits, starting with 7656).");
                    }
                    break;
                case 'select':
                    if (!array_key_exists($value, $definition[2])) {
                        throw new InvalidArgumentException("Pick a $label.");
                    }
                    break;
                case 'text':
                    if (in_array($field, ['item', 'text'], true) && preg_match('/\s/', $value)) {
                        throw new InvalidArgumentException("$label cannot contain spaces.");
                    }
                    break;
            }

            $replacements['{' . $field . '}'] = $value;
        }

        return ConsoleCommand::normalize(strtr($command['template'], $replacements));
    }

    /**
     * Players the server has seen, from the PlayerTools mod's players.tsv.
     *
     * @return array<string, string> SteamID => "Name (SteamID)", sorted by name
     */
    public static function knownPlayers(?string $playersTsv): array
    {
        $players = [];
        foreach (explode("\n", str_replace("\r\n", "\n", $playersTsv ?? '')) as $line) {
            $parts = explode("\t", $line);
            if (count($parts) >= 2 && preg_match('/^\d{17}$/', $parts[0])) {
                $players[$parts[0]] = trim($parts[1]) . ' (' . $parts[0] . ')';
            }
        }
        asort($players, SORT_NATURAL | SORT_FLAG_CASE);

        return $players;
    }
}
