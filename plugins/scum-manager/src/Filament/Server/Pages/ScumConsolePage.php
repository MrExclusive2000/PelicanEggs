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
use MrExclusive\ScumManager\Support\ItemSelect;
use MrExclusive\ScumManager\Support\TeleportDestinations;
use MrExclusive\ScumManager\Support\Brand;

class ScumConsolePage extends Page
{
    use BlockAccessInConflict;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-terminal-2';

    protected static ?string $slug = 'scum-console';

    protected static ?int $navigationSort = 31;

    protected static ?string $navigationLabel = 'Console';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_CONSOLE;

    #[Locked]
    public bool $modInstalled = false;

    #[Locked]
    public string $output = '';

    #[Locked]
    public string $reports = '';

    /** Re-read the output and reports every few seconds while the page is open. */
    public bool $live = true;

    /** Where the two logs are, found once so live updates only read the files. */
    #[Locked]
    public ?string $consoleLog = null;

    #[Locked]
    public ?string $reportsLog = null;

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        // The trait's canAccess() is replaced by this one, so its check is repeated here: no access
        // while the server is suspended, installing, restoring a backup or being transferred.
        return !$server->isInConflictState()
            && parent::canAccess()
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

        $consoleDir = $service->consoleModDir($server);
        $this->modInstalled = $consoleDir !== null;
        $this->consoleLog = $consoleDir === null ? null : "$consoleDir/console.log";
        $this->reportsLog = $service->reportsLogPath($server);
        $this->output = $this->modInstalled ? $service->consoleOutput($server) : '';
        $this->reports = $service->playerReports($server);
    }

    /** Called every few seconds by the page while live updates are on. */
    public function pollOutput(): void
    {
        if (!$this->live) {
            return;
        }

        $service = app(ScumServerService::class);
        $server = $this->getServer();

        try {
            if ($this->consoleLog !== null) {
                $this->output = $service->tailOf($server, $this->consoleLog, 60);
            }
            if ($this->reportsLog !== null) {
                $this->reports = $service->newestFirst($service->tailOf($server, $this->reportsLog, 30));
            }
        } catch (Exception) {
            // The server's files are briefly out of reach (e.g. restarting): keep what is shown.
        }
    }

    public function content(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Output')
                ->extraAttributes(fn () => $this->live && $this->modInstalled ? ['wire:poll.5s' => 'pollOutput'] : [])
                ->description(fn () => $this->modInstalled
                    ? 'Click "Run a command" and pick what to do. "Works any time" commands need nobody in game. "Needs an admin in game" commands only run while an admin from AdminUsers.ini is online, as if that admin typed them in chat.'
                    : 'Install the ' . Brand::mod('PelicanConsole') . ' mod on the ' . Brand::PAGE_MODS . ' page ("Install our mods") and restart the server to use this page.')
                ->schema([$this->logEntry('console_output', fn () => $this->output, 'No output yet.')]),
            Section::make('Player reports')
                ->description('Sent by players with !report <name> <what happened> (' . Brand::mod('PlayerTools') . ' mod), newest first.')
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

            $components[] = Text::make(($command['anytime'] === false ? 'Needs an admin in game. ' : '') . (($command['experimental'] ?? false) ? 'Not yet confirmed on a live server: try it on yourself first. ' : '') . $command['help'])
                ->color($command['anytime'] === false ? 'warning' : 'gray')
                ->visible($visible);

            foreach ($command['fields'] as $field => $definition) {
                $name = AdminCommands::fieldName($key, $field);
                [$type, $label] = $definition;

                $component = match (true) {
                    $type === 'item' => ItemSelect::make($name, $label, fn () => app(ScumServerService::class)->itemCatalog($this->getServer())),
                    $type === 'player' && $players !== [] => Select::make($name)->options($players)->searchable(),
                    $type === 'playerName' && $names !== [] => Select::make($name)->options($names)->searchable(),
                    $type === 'select' => Select::make($name)->options($definition[2])->selectablePlaceholder(false),
                    $type === 'int' => TextInput::make($name)->integer()->minValue($definition[2])->maxValue($definition[3]),
                    $type === 'player' => TextInput::make($name)->placeholder('76561198000000000')->helperText('No players known yet (' . Brand::mod('PlayerTools') . ' lists everyone who has joined). Enter a SteamID64.'),
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
                                    : Brand::mod('PelicanConsole') . ' checks once a second while the server runs. If this keeps happening, check that the mod is enabled and look in ue4ss/UE4SS.log for [' . Brand::mod('PelicanConsole') . '] lines.')
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
                ->modalDescription('Finds the trader outposts on your map (from where the bankers stand) and adds them to ' . Brand::mod('PlayerTools') . ', so players can type !tp a0, !tp b4 and so on. Existing destinations with the same names are replaced. The server must be running. Teleport there once yourself to check the spot.')
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
                            ->body('Players can now type !tp ' . $outposts[0]['name'] . '. Change names and prices on ExclsvSCUM Mod Settings > Player tools > Teleports.')
                            ->success()
                            ->persistent()
                            ->send();
                    } catch (Exception $exception) {
                        Notification::make()->title('Could not add the outposts')->body($exception->getMessage())->danger()->persistent()->send();
                    }
                    $this->refreshOutput();
                }),
            Action::make('destination_here')
                ->label('Add a place where a player stands')
                ->icon('tabler-map-pin-plus')
                ->color('gray')
                ->visible(fn () => $this->modInstalled)
                ->authorize(fn () => user()?->can(SubuserPermission::ControlConsole, $this->getServer())
                    && user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                ->modalHeading('Add a teleport destination or King of the Hill zone')
                ->modalDescription('Stand where you want it in game, then pick yourself here.')
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
                        Select::make('kind')->label('Add as')->options(['teleport' => 'Teleport destination (!tp <name>)', 'koth' => 'King of the Hill zone'])
                            ->default('teleport')->selectablePlaceholder(false)->required()->live(),
                        TextInput::make('name')->label('Name (one word)')->required()->maxLength(24),
                        TextInput::make('price')->label('Teleport price')->integer()->minValue(0)->default(500)->required()
                            ->visible(fn (\Filament\Schemas\Components\Utilities\Get $get) => $get('kind') !== 'koth'),
                        TextInput::make('radius')->label('Zone radius (m)')->integer()->minValue(10)->default(100)->required()
                            ->visible(fn (\Filament\Schemas\Components\Utilities\Get $get) => $get('kind') === 'koth'),
                    ];
                })
                ->action(function (array $data, ScumServerService $service) {
                    try {
                        $name = TeleportDestinations::name((string) $data['name']);
                        $player = trim((string) $data['player']);
                        $output = $service->runConsoleCommandAndRead($this->getServer(), 'WhereIs ' . $player, '/ is at |No online player|has no character/');
                        $at = TeleportDestinations::parseWhereIs($output, $player)
                            ?? throw new \RuntimeException(trim($output) !== '' ? trim(preg_replace('/^.*\] /m', '', $output)) : 'The mod did not answer in time.');
                        if (($data['kind'] ?? 'teleport') === 'koth') {
                            $service->addKothZone($this->getServer(), ['name' => $name] + $at, (int) ($data['radius'] ?? 100));
                            Notification::make()->title("Added King of the Hill zone $name")->body("At {$at['x']} {$at['y']} {$at['z']}.")->success()->send();
                        } else {
                            $service->addTeleportDestinations($this->getServer(), [['name' => $name] + $at], (int) ($data['price'] ?? 0));
                            Notification::make()->title("Added !tp $name")->body("At {$at['x']} {$at['y']} {$at['z']}.")->success()->send();
                        }
                    } catch (Exception $exception) {
                        Notification::make()->title('Could not add the destination')->body($exception->getMessage())->danger()->persistent()->send();
                    }
                    $this->refreshOutput();
                }),
            Action::make('live')
                ->label(fn () => $this->live ? 'Live updates: on' : 'Live updates: off')
                ->icon(fn () => $this->live ? 'tabler-player-pause' : 'tabler-player-play')
                ->color(fn () => $this->live ? 'success' : 'gray')
                ->tooltip('Re-read the output and player reports every 5 seconds while this page is open.')
                ->action(function () {
                    $this->live = !$this->live;
                    if ($this->live) {
                        $this->refreshOutput();
                    }
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
