<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\SubuserPermission;
use App\Models\Server;
use App\Traits\Filament\BlockAccessInConflict;
use Exception;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Infolists\Components\TextEntry;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\Component;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Components\Text;
use Filament\Schemas\Components\Utilities\Get;
use Filament\Schemas\Schema;
use Illuminate\Support\HtmlString;
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\AdminCommands;
use MrExclusive\ScumManager\Support\TeleportDestinations;

class ScumConsolePage extends Page
{
    use BlockAccessInConflict;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-terminal-2';

    protected static ?string $slug = 'scum-console';

    protected static ?int $navigationSort = 30;

    protected static ?string $navigationLabel = 'SCUM Admin Console';

    protected static ?string $title = 'SCUM Admin Console';

    #[Locked]
    public bool $modInstalled = false;

    #[Locked]
    public string $output = '';

    #[Locked]
    public string $reports = '';

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return parent::canAccess()
            && user()?->can(SubuserPermission::ControlConsole, $server)
            && user()?->can(SubuserPermission::FileReadContent, $server)
            && app(ScumServerService::class)->isScumServer($server);
    }

    public function mount(): void
    {
        $this->refreshOutput();
    }

    public function refreshOutput(): void
    {
        $service = app(ScumServerService::class);
        $server = $this->getServer();

        $this->modInstalled = $service->consoleModDir($server) !== null;
        $this->output = $this->modInstalled ? $service->consoleOutput($server) : '';
        $this->reports = $service->playerReports($server);
    }

    public function content(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Output')
                ->description(fn () => $this->modInstalled
                    ? 'Click "Run a command" and pick what to do. "Works any time" commands need nobody in game. "Needs an admin in game" commands only run while an admin from AdminUsers.ini is online, as if that admin typed them in chat.'
                    : 'Install the PelicanConsole mod on the SCUM Mods page ("Install our mods") and restart the server to use this page.')
                ->schema([$this->logEntry('console_output', fn () => $this->output, 'No output yet.')]),
            Section::make('Player reports')
                ->description('Sent by players with !report <name> <what happened> (PlayerTools mod), newest first.')
                ->collapsible()
                ->schema([$this->logEntry('player_reports', fn () => $this->reports, 'No reports.')]),
        ]);
    }

    private function logEntry(string $name, \Closure $text, string $empty): TextEntry
    {
        return TextEntry::make($name)
            ->hiddenLabel()
            ->state(fn () => new HtmlString(
                '<pre style="white-space: pre-wrap; word-break: break-word; font-family: ui-monospace, monospace; font-size: 0.8rem; max-height: 32rem; overflow-y: auto;">'
                . e($text() !== '' ? $text() : $empty)
                . '</pre>'
            ));
    }

    /** @return list<Component> the command picker and each command's fields */
    private function commandForm(): array
    {
        $players = app(ScumServerService::class)->knownPlayers($this->getServer());
        $names = array_combine(
            array_map(fn (string $label) => preg_replace('/ \(\d+\)$/', '', $label), array_values($players)),
            array_map(fn (string $label) => preg_replace('/ \(\d+\)$/', '', $label), array_values($players)),
        ) ?: [];

        $components = [
            Select::make('command')
                ->label('Command')
                ->options(AdminCommands::options())
                ->searchable()
                ->required()
                ->live(),
        ];

        foreach (AdminCommands::COMMANDS as $key => $command) {
            $visible = fn (Get $get) => $get('command') === $key;

            $components[] = Text::make(($command['anytime'] === false ? 'Needs an admin in game. ' : '') . (($command['experimental'] ?? false) ? 'Experimental. ' : '') . $command['help'])
                ->color($command['anytime'] === false ? 'warning' : 'gray')
                ->visible($visible);

            foreach ($command['fields'] as $field => $definition) {
                $name = AdminCommands::fieldName($key, $field);
                [$type, $label] = $definition;

                $component = match (true) {
                    $type === 'player' && $players !== [] => Select::make($name)->options($players)->searchable(),
                    $type === 'playerName' && $names !== [] => Select::make($name)->options($names)->searchable(),
                    $type === 'select' => Select::make($name)->options($definition[2])->selectablePlaceholder(false),
                    $type === 'int' => TextInput::make($name)->integer()->minValue($definition[2])->maxValue($definition[3]),
                    $type === 'player' => TextInput::make($name)->placeholder('76561198000000000')->helperText('No players known yet (PlayerTools lists everyone who has joined). Enter a SteamID64.'),
                    default => TextInput::make($name)->maxLength(400),
                };

                $components[] = $component->label($label)->visible($visible)->required($visible);
            }
        }

        return $components;
    }

    protected function getHeaderActions(): array
    {
        return [
            Action::make('send')
                ->label('Run a command')
                ->icon('tabler-player-play')
                ->visible(fn () => $this->modInstalled)
                ->authorize(fn () => user()?->can(SubuserPermission::ControlConsole, $this->getServer())
                    && user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                ->modalHeading('Run a SCUM admin command')
                ->modalSubmitActionLabel('Run')
                ->schema(fn () => $this->commandForm())
                ->action(function (array $data, ScumServerService $service) {
                    $server = $this->getServer();

                    try {
                        $line = AdminCommands::build((string) ($data['command'] ?? ''), $data);
                        $pickedUp = $service->sendConsoleCommand($server, $line);

                        if ($pickedUp) {
                            Notification::make()->title('Sent to SCUM: ' . $line)->success()->send();
                        } else {
                            Notification::make()
                                ->title('Queued, but SCUM has not picked it up yet')
                                ->body($service->isStopped($server)
                                    ? 'The server is stopped. The command is dropped when it next starts.'
                                    : 'PelicanConsole checks once a second while the server runs. If this keeps happening, check that the mod is enabled and look in ue4ss/UE4SS.log for [PelicanConsole] lines.')
                                ->warning()
                                ->send();
                        }
                    } catch (Exception $exception) {
                        Notification::make()->title('Could not send the command')->body($exception->getMessage())->danger()->send();
                    }

                    // Give the mod a moment to write its result.
                    usleep(1_000_000);
                    $this->refreshOutput();
                }),
            Action::make('outposts')
                ->label('Add outposts as teleports')
                ->icon('tabler-map-pin')
                ->color('gray')
                ->visible(fn () => $this->modInstalled)
                ->authorize(fn () => user()?->can(SubuserPermission::ControlConsole, $this->getServer())
                    && user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                ->modalHeading('Add the outposts as teleport destinations')
                ->modalDescription('Finds the trader outposts on your map (from where the bankers stand) and adds them to PlayerTools, so players can type !tp a0, !tp b4 and so on. Existing destinations with the same names are replaced. The server must be running. Teleport there once yourself to check the spot.')
                ->modalSubmitActionLabel('Find and add')
                ->schema([
                    TextInput::make('price')->label('Price per teleport')->integer()->minValue(0)->default(500)->required(),
                ])
                ->action(function (array $data, ScumServerService $service) {
                    try {
                        $output = $service->runConsoleCommandAndRead($this->getServer(), 'FindOutposts', '/Outpost \S+ at |No outposts found/');
                        $outposts = TeleportDestinations::parseOutposts($output);
                        if ($outposts === []) {
                            throw new \RuntimeException(trim($output) !== '' ? trim(preg_replace('/^.*\] /m', '', $output)) : 'The mod did not answer in time.');
                        }
                        $service->addTeleportDestinations($this->getServer(), $outposts, (int) $data['price']);

                        Notification::make()
                            ->title('Added ' . count($outposts) . ' teleport destination(s): ' . implode(', ', array_column($outposts, 'name')))
                            ->body('Players can now type !tp ' . $outposts[0]['name'] . '. Change names and prices on SCUM Mod Settings > Player tools > Teleports.')
                            ->success()
                            ->persistent()
                            ->send();
                    } catch (Exception $exception) {
                        Notification::make()->title('Could not add the outposts')->body($exception->getMessage())->danger()->persistent()->send();
                    }
                    $this->refreshOutput();
                }),
            Action::make('destination_here')
                ->label('Add a teleport where a player stands')
                ->icon('tabler-map-pin-plus')
                ->color('gray')
                ->visible(fn () => $this->modInstalled)
                ->authorize(fn () => user()?->can(SubuserPermission::ControlConsole, $this->getServer())
                    && user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                ->modalHeading('Add a teleport destination')
                ->modalDescription('Stand where you want the destination in game, then pick yourself here. The spot is added to PlayerTools as !tp <name>.')
                ->schema(function () {
                    $players = app(ScumServerService::class)->knownPlayers($this->getServer());
                    $names = [];
                    foreach ($players as $label) {
                        $name = preg_replace('/ \(\d+\)$/', '', $label);
                        $names[$name] = $name;
                    }

                    return [
                        $names === []
                            ? TextInput::make('player')->label('Player (exact in-game name)')->required()
                            : Select::make('player')->label('Player')->options($names)->searchable()->required(),
                        TextInput::make('name')->label('Destination name (what players type after !tp)')->required()->maxLength(24),
                        TextInput::make('price')->label('Price')->integer()->minValue(0)->default(500)->required(),
                    ];
                })
                ->action(function (array $data, ScumServerService $service) {
                    try {
                        $name = TeleportDestinations::name((string) $data['name']);
                        $player = trim((string) $data['player']);
                        $output = $service->runConsoleCommandAndRead($this->getServer(), 'WhereIs ' . $player, '/ is at |No online player|has no character/');
                        $at = TeleportDestinations::parseWhereIs($output, $player)
                            ?? throw new \RuntimeException(trim($output) !== '' ? trim(preg_replace('/^.*\] /m', '', $output)) : 'The mod did not answer in time.');
                        $service->addTeleportDestinations($this->getServer(), [['name' => $name] + $at], (int) $data['price']);

                        Notification::make()->title("Added !tp $name")->body("At {$at['x']} {$at['y']} {$at['z']}.")->success()->send();
                    } catch (Exception $exception) {
                        Notification::make()->title('Could not add the destination')->body($exception->getMessage())->danger()->persistent()->send();
                    }
                    $this->refreshOutput();
                }),
            Action::make('refresh')
                ->label('Refresh')
                ->icon('tabler-refresh')
                ->color('gray')
                ->action(fn () => $this->refreshOutput()),
        ];
    }

    private function getServer(): Server
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return $server;
    }
}
