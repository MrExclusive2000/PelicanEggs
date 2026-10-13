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
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Infolists\Components\TextEntry;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Components\Text;
use Filament\Schemas\Components\Utilities\Get;
use Filament\Schemas\Schema;
use Illuminate\Support\HtmlString;
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Filament\Server\Concerns\RunsPlayerCommands;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\AdminCommands;
use MrExclusive\ScumManager\Support\Accuracy;
use MrExclusive\ScumManager\Support\Brand;
use MrExclusive\ScumManager\Support\ItemSelect;
use MrExclusive\ScumManager\Support\OnlinePlayers;
use MrExclusive\ScumManager\Support\Overview;

/**
 * One screen with what needs attention: server and mod state, anti-cheat flags, player reports
 * and the last crash, with shortcuts to the other pages.
 */
class ScumOverviewPage extends Page
{
    use BlockAccessInConflict;
    use RunsPlayerCommands;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-layout-dashboard';

    protected static ?string $slug = 'scum-overview';

    protected static ?int $navigationSort = 27;

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

    /** null: the egg has no Discord variable (older egg); otherwise whether a webhook is set. */
    #[Locked]
    public ?bool $discord = null;

    #[Locked]
    public string $discordFeed = '';

    /** @var list<string> */
    #[Locked]
    public array $flags = [];

    #[Locked]
    public string $reports = '';

    /** @var list<array{steamId: string, name: string, x: ?int, y: ?int, z: ?int, place: string, vehicle: bool, admin: bool, seconds: int}> */
    #[Locked]
    public array $online = [];

    /** When ExclsvPlayerTools last wrote the online list (null: never). */
    #[Locked]
    public ?int $onlineUpdated = null;

    #[Locked]
    public bool $consoleInstalled = false;

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

        // The trait's canAccess() is replaced by this one, so its check is repeated here: no access
        // while the server is suspended, installing, restoring a backup or being transferred.
        return !$server->isInConflictState()
            && parent::canAccess()
            && user()?->can(SubuserPermission::FileReadContent, $server)
            && app(ScumServerService::class)->isScumServer($server);
    }

    public function mount(): void
    {
        $this->load();
    }

    protected function load(): void
    {
        // Refresh the save snapshot on open and on Refresh (at most every five minutes); polls only read it.
        app(ScumServerService::class)->saveData($this->getServer());

        $service = app(ScumServerService::class);
        $server = $this->getServer();

        $this->serverState = $service->powerState($server)->value;
        $ue4ss = $service->ue4ss($server);
        $this->ue4ss = ['installed' => $ue4ss['installed'], 'layout' => $ue4ss['layout']];
        $this->knownPlayers = count($service->knownPlayers($server));
        $webhook = $service->variable($server, 'DISCORD_WEBHOOK_URL');
        $this->discord = $webhook === null ? null : trim($webhook) !== '';
        $this->discordFeed = str_replace(',', ', ', trim((string) $service->variable($server, 'DISCORD_FEED')) ?: 'status,flags,reports');

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
            // With a source set but unreachable there is nothing to compare with: a mod installed from
            // GitHub earlier can be newer than the bundled copy.
            $newest = $service->modSource() === null
                ? (ScumServerService::bundledBuilds()[$mod]['build'] ?? null)
                : ($latest['mods'][$mod]['build'] ?? null);
            [$label, $color] = Overview::modStatus($installed, (bool) ($present[$mod]['enabled'] ?? false), $build, $newest);
            $old = array_search($mod, Brand::LEGACY_FOLDERS, true);
            if (!$installed && $old !== false && $present->has($old)) {
                // Still in its pre-1.33.0 folder: the update moves it across.
                [$label, $color, $installed] = ['Update available', 'info', true];
            }
            if ($mod === 'ExclsvProbe' && !$installed) {
                continue; // the probe is a tool, not something every server needs
            }
            $this->mods[] = ['name' => $mod, 'label' => $label, 'color' => $color, 'build' => $build];
        }

        $this->consoleInstalled = $present->has('ExclsvConsole');
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
                ? Overview::antiCheatEvents($service->tailOf($server, $ue4ss['mods'] . '/ExclsvAntiCheat/anticheat.log', 400))
                : [];
            $this->reports = $service->playerReports($server, 10);
            $online = $service->onlinePlayers($server);
            $this->online = $online['players'];
            $this->onlineUpdated = $online['updated'];
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
                            ->state(fn () => $this->knownPlayers > 0 ? (string) $this->knownPlayers : 'None yet (' . Brand::mod('ExclsvPlayerTools') . ' records everyone who joins)'),
                        TextEntry::make('discord')->label('Discord feed')
                            ->state(fn () => match ($this->discord) {
                                true => 'On (' . $this->discordFeed . ')',
                                false => 'Off: paste a channel webhook into "[Exclsv] Discord webhook URL" on the Startup page',
                                null => 'Re-import the SCUM egg to get the Discord feed',
                            })
                            ->color(fn () => $this->discord === true ? 'success' : 'gray'),
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
            Section::make('Online players')
                ->icon('tabler-users')
                ->description(fn () => $this->onlineSummary())
                ->extraAttributes(['wire:poll.15s' => 'loadLive'])
                ->schema([
                    TextEntry::make('online_players')
                        ->hiddenLabel()
                        ->state(fn () => new HtmlString($this->onlineTable())),
                ]),
            Grid::make(['default' => 1, 'lg' => 2])->schema([
                Section::make('Anti-cheat flags')
                    ->icon('tabler-shield-exclamation')
                    ->description('Strikes, kicks, bans and spectate flags from ' . Brand::mod('ExclsvAntiCheat') . ', newest first. Updates every 15 seconds.')
                    ->schema([$this->logEntry('flags', fn () => implode("\n", $this->flags), 'Nothing flagged.')]),
                Section::make('Player reports')
                    ->icon('tabler-message-report')
                    ->description('Sent with !report, newest first.')
                    ->schema([$this->logEntry('reports', fn () => $this->reports, 'No reports.')]),
            ]),
            Section::make('Accuracy watch')
                ->icon('tabler-target')
                ->description('Players who hit ' . Accuracy::WATCH_PERCENT . '% or more of at least ' . Accuracy::MIN_SHOTS . ' shots in SCUM\'s lifetime stats (from the save). Most players stay well under that; spectate anyone listed.')
                ->collapsible()
                ->collapsed(fn () => $this->accuracyWatch() === [])
                ->schema([$this->logEntry('accuracy', fn () => implode("\n", $this->accuracyWatch()), 'Nobody stands out.')]),
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

    private function onlineSummary(): string
    {
        if ($this->onlineUpdated === null) {
            return Brand::mod('ExclsvPlayerTools') . ' has not written the online list yet (it does every 15 seconds while the server runs). Update our mods if this stays empty.';
        }
        if ($this->online === [] && time() - $this->onlineUpdated > OnlinePlayers::FRESH_SECONDS) {
            return 'Not current: last updated ' . OnlinePlayers::duration(time() - $this->onlineUpdated) . ' ago (server stopped or restarting).';
        }

        return count($this->online) . ' online. Updates every 15 seconds. Use "Manage a player" above for items, money, teleports, kicks and bans.';
    }

    private function onlineTable(): string
    {
        if ($this->online === []) {
            return '<p style="opacity: .7; font-size: .875rem;">Nobody online.</p>';
        }

        $cell = 'style="padding: .35rem .75rem .35rem 0; text-align: left; vertical-align: top;"';
        $rows = '';
        foreach ($this->online as $player) {
            $tags = trim(($player['admin'] ? 'admin ' : '') . ($player['vehicle'] ? 'in a vehicle' : ''));
            $rows .= '<tr style="border-top: 1px solid rgba(127,127,127,.2);">'
                . "<td $cell><strong>" . e($player['name']) . '</strong>' . ($tags !== '' ? ' <span style="opacity: .7;">(' . e($tags) . ')</span>' : '') . '</td>'
                . "<td $cell><code style=\"font-size: .75rem;\">" . e($player['steamId'] ?: 'unknown') . '</code></td>'
                . "<td $cell>" . e(OnlinePlayers::where($player)) . '</td>'
                . "<td $cell>" . e(OnlinePlayers::duration($player['seconds'])) . '</td>'
                . '</tr>';
        }

        return '<div style="overflow-x: auto;"><table style="width: 100%; font-size: .875rem; border-collapse: collapse;">'
            . "<thead><tr><th $cell>Player</th><th $cell>SteamID</th><th $cell>Where</th><th $cell>Online for</th></tr></thead>"
            . "<tbody>$rows</tbody></table></div>";
    }

    /** @return array<string, string> "steamId|name" => label */
    private function playerOptions(): array
    {
        $options = [];
        foreach ($this->online as $player) {
            $options[$player['steamId'] . '|' . $player['name']] = $player['name'] . ($player['steamId'] !== '' ? " ({$player['steamId']})" : '');
        }

        return $options;
    }

    /** @return list<string> "Name (SteamID): 71% of 830 shots, 25 kills" for suspicious players */
    private function accuracyWatch(): array
    {
        $lines = [];
        foreach (app(ScumServerService::class)->saveSnapshot($this->getServer())['players'] as $player) {
            if (Accuracy::suspicious($player['stats'])) {
                $lines[] = sprintf('%s (%s): %d%% of %s shots, %d kills, %d headshots', $player['name'], $player['steamId'],
                    Accuracy::percent($player['stats']), number_format((int) $player['stats']['shots_fired']),
                    (int) ($player['stats']['kills'] ?? 0), (int) ($player['stats']['headshots'] ?? 0));
            }
        }

        return $lines;
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
                    try {
                        $service->power($server, 'start');
                        $this->serverState = ContainerStatus::Starting->value;
                        Notification::make()->title('Server starting')->success()->send();
                    } catch (Exception $exception) {
                        report($exception);
                        Notification::make()->title('Could not start')->body($exception->getMessage())->danger()->send();
                    }
                }),
            Action::make('manage')
                ->label('Manage a player')
                ->icon('tabler-user-cog')
                ->visible(fn () => $this->consoleInstalled && $this->online !== [])
                ->authorize(fn () => user()?->can(SubuserPermission::ControlConsole, $server)
                    && user()?->can(SubuserPermission::FileUpdate, $server))
                ->modalHeading('Manage a player')
                ->modalDescription('Runs through the ' . Brand::mod('ExclsvConsole') . ' mod; the answer is shown when it arrives.')
                ->modalSubmitActionLabel('Run')
                ->schema(fn () => $this->playerCommandSchema(fn () => $this->playerOptions()))
                ->action(function (array $data, ScumServerService $service) {
                    [$steamId, $name] = array_pad(explode('|', (string) ($data['player'] ?? ''), 2), 2, '');
                    $this->runPlayerCommand($steamId, $name, $data, $service);
                    $this->loadLive();
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
