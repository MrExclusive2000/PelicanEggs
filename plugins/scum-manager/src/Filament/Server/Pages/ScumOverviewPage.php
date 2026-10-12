<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\ContainerStatus;
use App\Enums\SubuserPermission;
use App\Filament\Server\Resources\Files\Pages\ListFiles;
use App\Models\Server;
use App\Traits\Filament\BlockAccessInConflict;
use Exception;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Infolists\Components\TextEntry;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Illuminate\Support\HtmlString;
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\Brand;
use MrExclusive\ScumManager\Support\Overview;

/**
 * One screen with what needs attention: server and mod state, anti-cheat flags, player reports
 * and the last crash, with shortcuts to the other pages.
 */
class ScumOverviewPage extends Page
{
    use BlockAccessInConflict;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-layout-dashboard';

    protected static ?string $slug = 'scum-overview';

    protected static ?int $navigationSort = 29;

    protected static ?string $navigationLabel = 'Overview';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_OVERVIEW;

    private const CRASHES_DIR = 'SCUM/Saved/Crashes';

    #[Locked]
    public string $serverState = '';

    /** @var array{installed: bool, layout: string} */
    #[Locked]
    public array $ue4ss = ['installed' => false, 'layout' => 'none'];

    /** @var list<array{name: string, label: string, color: string, build: ?string}> */
    #[Locked]
    public array $mods = [];

    #[Locked]
    public ?string $newerManager = null;

    #[Locked]
    public int $knownPlayers = 0;

    /** @var list<string> */
    #[Locked]
    public array $flags = [];

    #[Locked]
    public string $reports = '';

    /** @var array{name: string, modified: string, count: int}|null */
    #[Locked]
    public ?array $crash = null;

    /** @var list<string> */
    #[Locked]
    public array $crashLines = [];

    #[Locked]
    public string $previousLog = '';

    #[Locked]
    public ?string $logDir = null;

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return parent::canAccess()
            && user()?->can(SubuserPermission::FileReadContent, $server)
            && app(ScumServerService::class)->isScumServer($server);
    }

    public function mount(): void
    {
        $this->load();
    }

    public function load(): void
    {
        $service = app(ScumServerService::class);
        $server = $this->getServer();

        $this->serverState = $service->powerState($server)->value;
        $ue4ss = $service->ue4ss($server);
        $this->ue4ss = ['installed' => $ue4ss['installed'], 'layout' => $ue4ss['layout']];
        $this->knownPlayers = count($service->knownPlayers($server));

        try {
            $latest = $service->modSource() !== null ? $service->latestModManifest() : null;
        } catch (Exception) {
            $latest = null; // GitHub out of reach: versions are shown without comparison
        }
        $this->newerManager = isset($latest['manager']) && version_compare($latest['manager'], ScumServerService::managerVersion(), '>') ? $latest['manager'] : null;

        $present = collect($service->mods($server))->keyBy('name');
        $this->mods = [];
        foreach (array_keys(Brand::MODS) as $mod) {
            $installed = $present->has($mod);
            $build = $installed ? $service->installedBuild($server, $mod) : null;
            $newest = $latest['mods'][$mod]['build'] ?? ScumServerService::bundledBuilds()[$mod]['build'] ?? null;
            [$label, $color] = Overview::modStatus($installed, (bool) ($present[$mod]['enabled'] ?? false), $build, $newest);
            if ($mod === 'ScumCommandProbe' && !$installed) {
                continue; // the probe is a tool, not something every server needs
            }
            $this->mods[] = ['name' => $mod, 'label' => $label, 'color' => $color, 'build' => $build];
        }

        $this->logDir = $ue4ss['installed'] ? $ue4ss['root'] : null;
        $this->previousLog = $this->logDir === null ? '' : $service->tailOf($server, $this->logDir . '/UE4SS.previous.log', 40);
        $this->crashLines = Overview::crashLines($this->previousLog);
        $this->crash = Overview::newestCrash($service->listDirectory($server, self::CRASHES_DIR));

        $this->loadLive();
    }

    /** The parts that change while the server runs; re-read every 15 seconds. */
    public function loadLive(): void
    {
        $service = app(ScumServerService::class);
        $server = $this->getServer();

        try {
            $ue4ss = $service->ue4ss($server);
            $this->flags = $ue4ss['installed']
                ? Overview::antiCheatEvents($service->tailOf($server, $ue4ss['mods'] . '/ScumAntiCheat/anticheat.log', 400))
                : [];
            $this->reports = $service->playerReports($server, 10);
            $this->serverState = $service->powerState($server)->value;
        } catch (Exception) {
            // Files briefly out of reach (e.g. restarting): keep what is shown.
        }
    }

    public function content(Schema $schema): Schema
    {
        return $schema->components([
            Grid::make(['default' => 1, 'lg' => 2])->schema([
                Section::make('Server')
                    ->icon('tabler-server')
                    ->schema([
                        TextEntry::make('state')->label('Status')
                            ->state(fn () => ContainerStatus::tryFrom($this->serverState)?->getLabel() ?? 'Unknown')
                            ->badge()
                            ->color(fn () => ScumServerService::isStoppedState($this->serverState) ? 'danger' : 'success'),
                        TextEntry::make('ue4ss')->label('UE4SS')
                            ->state(fn () => $this->ue4ss['installed'] ? 'Installed (' . $this->ue4ss['layout'] . ')' : 'Not installed: needed for our mods')
                            ->color(fn () => $this->ue4ss['installed'] ? null : 'warning'),
                        TextEntry::make('players')->label('Players seen')
                            ->state(fn () => $this->knownPlayers > 0 ? (string) $this->knownPlayers : 'None yet (' . Brand::mod('PlayerTools') . ' records everyone who joins)'),
                        TextEntry::make('manager')->label(Brand::MANAGER)
                            ->state(fn () => ScumServerService::managerVersion() . ($this->newerManager !== null ? '  →  ' . $this->newerManager . ' available (import the new plugin zip)' : ''))
                            ->color(fn () => $this->newerManager !== null ? 'info' : null),
                    ])
                    ->columns(2),
                Section::make('Our mods')
                    ->icon('tabler-puzzle')
                    ->description(fn () => collect($this->mods)->contains('label', 'Update available')
                        ? 'Updates are waiting: Mods → "Install / update our mods" (settings are kept), then restart.'
                        : 'Versions compared with the latest builds on GitHub.')
                    ->schema(fn () => array_map(
                        fn (array $mod) => TextEntry::make('mod_' . $mod['name'])
                            ->label(Brand::mod($mod['name']))
                            ->state($mod['label'] . ($mod['build'] !== null ? ' · ' . $mod['build'] : ''))
                            ->badge()
                            ->color($mod['color']),
                        $this->mods,
                    ))
                    ->columns(2),
            ]),
            Grid::make(['default' => 1, 'lg' => 2])->schema([
                Section::make('Anti-cheat flags')
                    ->icon('tabler-shield-exclamation')
                    ->description('Strikes, kicks, bans and spectate flags from ' . Brand::mod('ScumAntiCheat') . ', newest first. Updates every 15 seconds.')
                    ->extraAttributes(['wire:poll.15s' => 'loadLive'])
                    ->schema([$this->logEntry('flags', fn () => implode("\n", $this->flags), 'Nothing flagged.')]),
                Section::make('Player reports')
                    ->icon('tabler-message-report')
                    ->description('Sent with !report, newest first.')
                    ->schema([$this->logEntry('reports', fn () => $this->reports, 'No reports.')]),
            ]),
            Section::make('Last session')
                ->icon(fn () => $this->crashLines !== [] ? 'tabler-alert-triangle' : 'tabler-history')
                ->description(fn () => $this->crashSummary())
                ->collapsible()
                ->collapsed(fn () => $this->crashLines === [])
                ->schema([
                    $this->logEntry('crash_lines', fn () => implode("\n", $this->crashLines), 'No crash lines in the previous UE4SS log.'),
                    $this->logEntry('previous_log', fn () => $this->previousLog, 'No previous UE4SS log yet (it is kept from the next restart on).'),
                ]),
        ]);
    }

    private function crashSummary(): string
    {
        $parts = [$this->crashLines !== []
            ? 'Crash signs found in the UE4SS log from before the last restart (UE4SS.previous.log): see the lines below.'
            : 'The end of the UE4SS log from before the last restart (UE4SS.previous.log). No crash signs.'];
        if ($this->crash !== null) {
            $parts[] = sprintf('SCUM has %d crash report%s; the newest is %s (%s).',
                $this->crash['count'], $this->crash['count'] === 1 ? '' : 's', $this->crash['name'], $this->crash['modified'] ?: 'date unknown');
        }

        return implode(' ', $parts);
    }

    private function logEntry(string $name, \Closure $text, string $empty): TextEntry
    {
        return TextEntry::make($name)
            ->hiddenLabel()
            ->state(fn () => new HtmlString(
                '<pre style="white-space: pre-wrap; word-break: break-word; font-family: ui-monospace, monospace; font-size: 0.8rem; max-height: 20rem; overflow-y: auto;">'
                . e($text() !== '' ? $text() : $empty)
                . '</pre>'
            ));
    }

    protected function getHeaderActions(): array
    {
        $server = $this->getServer();

        return [
            Action::make('restart')
                ->label('Restart server')
                ->icon('tabler-reload')
                ->color('warning')
                ->visible(fn () => !ScumServerService::isStoppedState($this->serverState))
                ->authorize(fn () => user()?->can(SubuserPermission::ControlRestart, $server))
                ->requiresConfirmation()
                ->modalDescription('Players are disconnected. SCUM takes a few minutes to come back up.')
                ->action(function (ScumServerService $service) use ($server) {
                    try {
                        $service->power($server, 'restart');
                        $this->serverState = ContainerStatus::Starting->value;
                        Notification::make()->title('Server restarting')->success()->send();
                    } catch (Exception $exception) {
                        report($exception);
                        Notification::make()->title('Could not restart')->body($exception->getMessage())->danger()->send();
                    }
                }),
            Action::make('start')
                ->label('Start server')
                ->icon('tabler-player-play')
                ->visible(fn () => ScumServerService::isStoppedState($this->serverState))
                ->authorize(fn () => user()?->can(SubuserPermission::ControlStart, $server))
                ->action(function (ScumServerService $service) use ($server) {
                    $service->power($server, 'start');
                    $this->serverState = ContainerStatus::Starting->value;
                    Notification::make()->title('Server starting')->success()->send();
                }),
            Action::make('mods')
                ->label('Update mods')
                ->icon('tabler-package')
                ->color('gray')
                ->url(fn () => ScumModsPage::getUrl()),
            Action::make('console')
                ->label('Console')
                ->icon('tabler-terminal-2')
                ->color('gray')
                ->url(fn () => ScumConsolePage::getUrl()),
            Action::make('crashes')
                ->label('Crash reports')
                ->icon('tabler-folder-open')
                ->color('gray')
                ->visible(fn () => $this->crash !== null)
                ->url(fn () => ListFiles::getUrl(['path' => self::CRASHES_DIR])),
            Action::make('refresh')
                ->label('Refresh')
                ->icon('tabler-refresh')
                ->color('gray')
                ->action(fn () => $this->load()),
        ];
    }

    private function getServer(): Server
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return $server;
    }
}
