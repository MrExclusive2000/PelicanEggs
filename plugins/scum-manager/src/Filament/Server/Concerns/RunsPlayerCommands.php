<?php

namespace MrExclusive\ScumManager\Filament\Server\Concerns;

use Closure;
use Exception;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Components\Text;
use Filament\Schemas\Components\Utilities\Get;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\AdminCommands;
use MrExclusive\ScumManager\Support\ItemSelect;
use RuntimeException;

/**
 * The common commands for one player (where is, money, items, teleports, kick, ban), run
 * through the PelicanConsole mod. Used by the Overview and Players pages.
 */
trait RunsPlayerCommands
{
    /** @return list<string> AdminCommands keys offered for a player */
    protected static function playerCommandKeys(bool $online = true): array
    {
        return $online
            ? ['whereis', 'balance', 'giveitem', 'money', 'fame', 'teleportplayer', 'teleporttome', 'teleportto', 'kick', 'ban']
            : ['money', 'fame', 'ban'];
    }

    /**
     * @param  Closure|null  $playerOptions  "steamId|name" => label, to pick the player in the form
     * @return list<\Filament\Schemas\Components\Component>
     */
    protected function playerCommandSchema(?Closure $playerOptions = null, bool $online = true): array
    {
        $actions = [];
        foreach (static::playerCommandKeys($online) as $key) {
            $command = AdminCommands::COMMANDS[$key];
            $actions[$key] = $command['label'] . ($command['anytime'] === false ? ' (needs an admin in game)' : '');
        }
        $is = fn (string ...$keys) => fn (Get $get) => in_array($get('action'), $keys, true);

        return array_values(array_filter([
            $playerOptions !== null ? Select::make('player')->label('Player')->options($playerOptions)->searchable()->required() : null,
            Select::make('action')->label('Do')->options($actions)->required()->live(),
            Text::make(fn (Get $get) => AdminCommands::COMMANDS[$get('action')]['help'] ?? '')->color('gray'),
            ItemSelect::make('item', 'Item', fn () => app(ScumServerService::class)->itemCatalog($this->getServer()))
                ->visible($is('giveitem'))->required($is('giveitem')),
            TextInput::make('amount')->label('Amount')->integer()->minValue(1)->maxValue(10)->default(1)
                ->visible($is('giveitem'))->required($is('giveitem')),
            TextInput::make('money')->label('Amount (negative takes money)')->integer()->minValue(-1000000)->maxValue(1000000)
                ->visible($is('money'))->required($is('money')),
            TextInput::make('fame')->label('Fame points')->integer()->minValue(0)->maxValue(100000)
                ->visible($is('fame'))->required($is('fame')),
            Grid::make(3)->visible($is('teleportplayer'))->schema([
                TextInput::make('x')->label('X')->integer()->required($is('teleportplayer')),
                TextInput::make('y')->label('Y')->integer()->required($is('teleportplayer')),
                TextInput::make('z')->label('Z')->integer()->required($is('teleportplayer')),
            ]),
        ]));
    }

    /** Runs the picked command for the player and shows what the console mod answered. */
    protected function runPlayerCommand(string $steamId, string $name, array $data, ScumServerService $service): void
    {
        $key = (string) ($data['action'] ?? '');
        abort_unless(in_array($key, static::playerCommandKeys(), true), 422);

        $amount = match ($key) {
            'money' => $data['money'] ?? '',
            'fame' => $data['fame'] ?? '',
            default => $data['amount'] ?? '',
        };
        $values = [];
        foreach (['name' => $name, 'steamId' => $steamId, 'item' => $data['item'] ?? '', 'amount' => $amount,
            'x' => $data['x'] ?? '', 'y' => $data['y'] ?? '', 'z' => $data['z'] ?? ''] as $field => $value) {
            $values[AdminCommands::fieldName($key, $field)] = (string) $value;
        }

        try {
            if ($steamId === '' && array_key_exists('steamId', AdminCommands::COMMANDS[$key]['fields'])) {
                throw new RuntimeException("$name's SteamID is not known yet, so this command cannot be used for them.");
            }
            $line = AdminCommands::build($key, $values);
            $until = '/' . preg_quote($name !== '' ? $name : $steamId, '/') . '|' . preg_quote($steamId !== '' ? $steamId : $name, '/') . '|No online player|Usage:|failed|no admin/i';
            $answer = trim(preg_replace('/^\S+ \[[^\]]+\] /m', '', $service->runConsoleCommandAndRead($this->getServer(), $line, $until, 6)));

            Notification::make()
                ->title($line)
                ->body($answer !== '' ? $answer : 'Sent. No answer yet: see the Console page.')
                ->status(preg_match('/failed|No online player|no admin|Usage:/i', $answer) ? 'warning' : 'success')
                ->persistent()
                ->send();
        } catch (Exception $exception) {
            Notification::make()->title('Could not run that')->body($exception->getMessage())->danger()->send();
        }
    }
}
