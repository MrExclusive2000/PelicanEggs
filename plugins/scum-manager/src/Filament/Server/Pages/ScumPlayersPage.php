<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\SubuserPermission;
use App\Models\Server;
use App\Traits\Filament\BlockAccessInConflict;
use Exception;
use Filament\Actions\Action;
use Filament\Actions\ActionGroup;
use Filament\Facades\Filament;
use Filament\Infolists\Components\TextEntry;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\EmbeddedTable;
use Filament\Schemas\Schema;
use Filament\Support\Enums\IconSize;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Concerns\InteractsWithTable;
use Filament\Tables\Contracts\HasTable;
use Filament\Tables\Table;
use Illuminate\Support\HtmlString;
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Filament\Server\Concerns\RunsPlayerCommands;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\Accuracy;
use MrExclusive\ScumManager\Support\Brand;
use MrExclusive\ScumManager\Support\OnlinePlayers;
use MrExclusive\ScumManager\Support\PlayerDirectory;
use MrExclusive\ScumManager\Support\SaveDatabase;

/**
 * Every player in one table, combining PlayerTools' stats and online list, SCUM's player lists
 * and the anti-cheat's kick count, with actions for each player.
 */
class ScumPlayersPage extends Page implements HasTable
{
    use BlockAccessInConflict;
    use InteractsWithTable;
    use RunsPlayerCommands;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-users';

    protected static ?string $slug = 'scum-players';

    protected static ?int $navigationSort = 28;

    protected static ?string $navigationLabel = 'Players';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_PLAYERS;

    /** Badge label and colour per list flag. */
    private const FLAG_BADGES = [
        'banned' => ['Banned', 'danger'],
        'admin' => ['Admin', 'warning'],
        'settingsAdmin' => ['Settings admin', 'warning'],
        'whitelisted' => ['Whitelisted', 'info'],
        'exclusive' => ['Exclusive', 'info'],
        'silenced' => ['Silenced', 'gray'],
    ];

    /** List actions: flag => [file, add label, remove label, icon]. */
    private const LIST_ACTIONS = [
        'admin' => ['AdminUsers.ini', 'Make admin', 'Remove admin', 'tabler-shield-star'],
        'whitelisted' => ['WhitelistedUsers.ini', 'Whitelist (priority slot)', 'Remove from whitelist', 'tabler-star'],
        'silenced' => ['SilencedUsers.ini', 'Silence in chat', 'Unsilence', 'tabler-message-off'],
    ];

    #[Locked]
    public string $serverState = '';

    #[Locked]
    public bool $consoleInstalled = false;

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        // The trait's canAccess() is replaced by this one, so its check is repeated here.
        return !$server->isInConflictState()
            && parent::canAccess()
            && user()?->can(SubuserPermission::FileReadContent, $server)
            && app(ScumServerService::class)->isScumServer($server);
    }

    public function mount(): void
    {
        $this->refreshState();
        // Read the save once when the page opens (if the snapshot is older than five minutes);
        // the table and its 30 s refresh only use the snapshot.
        app(ScumServerService::class)->saveData($this->getServer());
    }

    private function refreshState(): void
    {
        $service = app(ScumServerService::class);
        $this->serverState = $service->powerState($this->getServer())->value;
        $this->consoleInstalled = $service->consoleModDir($this->getServer()) !== null;
    }

    public function content(Schema $schema): Schema
    {
        return $schema->components([EmbeddedTable::make()]);
    }

    public function table(Table $table): Table
    {
        return $table
            ->records(function (?string $search, ?string $sortColumn, ?string $sortDirection) {
                $players = PlayerDirectory::search(app(ScumServerService::class)->playerDirectory($this->getServer()), $search);
                $value = fn (array $p) => in_array($sortColumn, ['cash', 'gold', 'fame'], true) ? ($p['save'][$sortColumn] ?? -INF) : ($p[$sortColumn] ?? 0);
                if (in_array($sortColumn, ['kills', 'deaths', 'playtime', 'lastSeen', 'kicks', 'bounty', 'cash', 'gold', 'fame'], true)) {
                    uasort($players, fn (array $a, array $b) => $sortDirection === 'asc' ? $value($a) <=> $value($b) : $value($b) <=> $value($a));
                }

                return $players;
            })
            ->searchable()
            ->paginated(false)
            ->poll('30s')
            ->heading('Everyone who has played, or is on one of your lists')
            ->description(fn () => $this->saveSummary())
            ->emptyStateHeading('No players yet')
            ->emptyStateDescription(Brand::mod('PlayerTools') . ' records everyone who joins.')
            ->columns([
                TextColumn::make('name')
                    ->label('Player')
                    ->weight('bold')
                    ->state(fn (array $record) => $record['name'] !== '' ? $record['name'] : 'Unknown name')
                    ->description(fn (array $record) => $record['steamId'])
                    ->searchable(),
                TextColumn::make('status')
                    ->label('Status')
                    ->badge()
                    ->state(fn (array $record) => $this->badges($record))
                    ->color(fn (string $state) => match (true) {
                        $state === 'Online' || $state === 'Online, driving' => 'success',
                        default => collect(self::FLAG_BADGES)->firstWhere(0, $state)[1] ?? ($state === 'Anti-cheat kicks' ? 'danger' : 'gray'),
                    }),
                TextColumn::make('where')
                    ->label('Where / last seen')
                    ->state(fn (array $record) => $record['online']
                        ? $record['where']
                        : ($record['lastSeen'] > 0 ? OnlinePlayers::duration(max(0, time() - $record['lastSeen'])) . ' ago' : 'never seen by ' . Brand::mod('PlayerTools')))
                    ->wrap(),
                TextColumn::make('cash')->label('Cash')->sortable()
                    ->state(fn (array $record) => $record['save']['cash'] ?? null)
                    ->numeric()
                    ->placeholder('-')
                    ->tooltip('Bank balance from the save (updates when SCUM saves)'),
                TextColumn::make('gold')->label('Gold')->sortable()
                    ->state(fn (array $record) => $record['save']['gold'] ?? null)
                    ->numeric()
                    ->placeholder('-'),
                TextColumn::make('fame')->label('Fame')->sortable()
                    ->state(fn (array $record) => $record['save']['fame'] ?? null)
                    ->placeholder('-'),
                TextColumn::make('squad')->label('Squad')
                    ->state(fn (array $record) => ($record['save']['squad'] ?? '') !== '' ? $record['save']['squad'] . ' (' . $record['save']['squadRank'] . ')' : null)
                    ->placeholder('-')
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('accuracy')->label('Hit %')
                    ->state(fn (array $record) => ($p = Accuracy::percent($record['save']['stats'] ?? [], 50)) !== null ? $p . '%' : null)
                    ->placeholder('-')
                    ->color(fn (array $record) => Accuracy::suspicious($record['save']['stats'] ?? []) ? 'danger' : null)
                    ->weight(fn (array $record) => Accuracy::suspicious($record['save']['stats'] ?? []) ? 'bold' : null)
                    ->tooltip(fn (array $record) => Accuracy::suspicious($record['save']['stats'] ?? [])
                        ? 'Hits ' . Accuracy::percent($record['save']['stats']) . '% of ' . number_format((int) $record['save']['stats']['shots_fired']) . ' shots (SCUM lifetime stats). Worth spectating.'
                        : 'Share of shots that hit, from SCUM\'s lifetime stats (50+ shots)'),
                TextColumn::make('kills')->label('Kills')->sortable()->numeric(),
                TextColumn::make('deaths')->label('Deaths')->sortable()->numeric(),
                TextColumn::make('kd')->label('K/D')
                    ->state(fn (array $record) => $record['deaths'] > 0 ? number_format($record['kills'] / $record['deaths'], 2) : (string) $record['kills']),
                TextColumn::make('playtime')->label('Played')->sortable()
                    ->formatStateUsing(fn ($state) => (int) $state > 0 ? OnlinePlayers::duration((int) $state) : '-'),
                TextColumn::make('kicks')->label('AC kicks')->sortable()
                    ->color(fn ($state) => (int) $state > 0 ? 'danger' : 'gray')
                    ->tooltip('Times ' . Brand::mod('ScumAntiCheat') . ' kicked this player'),
                TextColumn::make('bounty')->label('Bounty')->sortable()
                    ->formatStateUsing(fn ($state) => (int) $state > 0 ? (string) $state : '-')
                    ->toggleable(isToggledHiddenByDefault: true),
            ])
            ->recordActions([
                Action::make('details')
                    ->label('Details')
                    ->icon('tabler-id')
                    ->color('gray')
                    ->modalHeading(fn (array $record) => ($record['name'] ?: $record['steamId']) . ' (' . $record['steamId'] . ')')
                    ->modalSubmitAction(false)
                    ->modalCancelActionLabel('Close')
                    ->schema(fn (array $record) => [
                        TextEntry::make('details')
                            ->hiddenLabel()
                            ->state(fn () => new HtmlString($this->detailsHtml($record))),
                    ]),
                Action::make('command')
                    ->label('Run a command')
                    ->icon('tabler-player-play')
                    ->visible(fn () => $this->consoleInstalled)
                    ->authorize(fn () => user()?->can(SubuserPermission::ControlConsole, $this->getServer())
                        && user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                    ->modalHeading(fn (array $record) => 'Run a command for ' . ($record['name'] ?: $record['steamId']))
                    ->modalDescription(fn (array $record) => $record['online'] ? null : 'Offline: only commands that work by SteamID are offered.')
                    ->modalSubmitActionLabel('Run')
                    ->schema(fn (array $record) => $this->playerCommandSchema(null, $record['online'], (string) $record['steamId']))
                    ->action(fn (array $record, array $data, ScumServerService $service) => $this->runPlayerCommand($record['steamId'], $record['name'], $data, $service)),
                ActionGroup::make([
                    Action::make('ban')
                        ->grouped()
                        ->iconSize(IconSize::Small)
                        ->label('Ban')
                        ->icon('tabler-ban')
                        ->color('danger')
                        ->hidden(fn (array $record) => $record['flags']['banned'])
                        ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                        ->requiresConfirmation()
                        ->modalHeading(fn (array $record) => 'Ban ' . ($record['name'] ?: $record['steamId']) . '?')
                        ->modalDescription(fn (array $record) => 'Adds them to BannedUsers.ini' . ($record['online'] ? ' and kicks them now.' : '.') . ' Unban here or on the Player lists page.')
                        ->action(fn (array $record, ScumServerService $service) => $this->ban($record, $service)),
                    Action::make('unban')
                        ->grouped()
                        ->iconSize(IconSize::Small)
                        ->label('Unban')
                        ->icon('tabler-circle-check')
                        ->visible(fn (array $record) => $record['flags']['banned'])
                        ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                        ->requiresConfirmation()
                        ->action(fn (array $record, ScumServerService $service) => $this->setList($record, 'BannedUsers.ini', false, 'Unbanned', $service)),
                    ...$this->listActions(),
                ])->tooltip('Lists')->label('Lists'),
            ])
            ->headerActions([
                Action::make('reload_save')
                    ->label('Reload save data')
                    ->icon('tabler-refresh')
                    ->color('gray')
                    ->authorize(fn () => user()?->can(SubuserPermission::FileReadContent, $this->getServer()))
                    ->action(function (ScumServerService $service) {
                        $data = $service->saveData($this->getServer(), fresh: true);
                        $data['error'] === null
                            ? Notification::make()->title('Save data reloaded')->body(count($data['players']) . ' players in the save.')->success()->send()
                            : Notification::make()->title('Could not read the save')->body($data['error'])->danger()->send();
                    }),
                Action::make('lists')
                    ->label('Edit list files')
                    ->icon('tabler-file-text')
                    ->color('gray')
                    ->url(fn () => ScumPlayerListsPage::getUrl()),
            ]);
    }

    private function saveSummary(): string
    {
        $data = app(ScumServerService::class)->saveSnapshot($this->getServer());
        $parts = ['Stats from ' . Brand::mod('PlayerTools') . ', bans and admins from SCUM\'s player lists, kicks from ' . Brand::mod('ScumAntiCheat') . '.'];
        $parts[] = $data['error'] !== null
            ? 'Money, fame and inventories could not be read from the save: ' . $data['error']
            : 'Money, fame and inventories from SCUM\'s save, read ' . OnlinePlayers::duration(max(0, time() - (int) $data['readAt'])) . ' ago (SCUM saves every few minutes).';

        return implode(' ', $parts);
    }

    private function detailsHtml(array $record): string
    {
        $save = $record['save'];
        $data = app(ScumServerService::class)->saveSnapshot($this->getServer());
        $rows = [];
        $row = fn (string $label, string $value) => '<tr><th style="text-align:left;padding:.2rem 1rem .2rem 0;font-weight:600;vertical-align:top;">' . e($label) . '</th><td style="padding:.2rem 0;">' . e($value) . '</td></tr>';

        if ($save === null) {
            $rows[] = $row('Save', $data['error'] !== null ? 'Not readable: ' . $data['error'] : 'Not in the save yet (SCUM writes new players on its next save).');
        } else {
            $rows[] = $row('Bank', number_format((int) ($save['cash'] ?? 0)) . ' cash, ' . number_format((int) ($save['gold'] ?? 0)) . ' gold');
            $rows[] = $row('Fame', (string) $save['fame']);
            $rows[] = $row('Squad', $save['squad'] !== '' ? $save['squad'] . ' (' . $save['squadRank'] . ')' : 'none');
            $rows[] = $row('Character', $save['alive'] === null ? 'unknown' : ($save['alive'] ? 'alive' : 'dead'));
            $stats = $save['stats'];
            if ($stats !== []) {
                $fired = (int) ($stats['shots_fired'] ?? 0);
                $hit = (int) ($stats['shots_hit'] ?? 0);
                $kills = (int) ($stats['kills'] ?? 0);
                $rows[] = $row('Lifetime (SCUM)', sprintf('%d kills (%d players), %d deaths, longest kill %d m, %s survived',
                    $kills, (int) ($stats['prisoner_kills'] ?? 0), (int) ($stats['deaths'] ?? 0), (int) ($stats['longest_kill_distance'] ?? 0),
                    OnlinePlayers::duration((int) round(((float) ($stats['minutes_survived'] ?? 0)) * 60))));
                $rows[] = $row('Shooting', $fired > 0
                    ? sprintf('%d shots, %d%% hit (headshots on anything, melee included: %d)', $fired, (int) round(100 * $hit / $fired), (int) ($stats['headshots'] ?? 0))
                    : 'no shots recorded');
            }
        }
        $rows[] = $row('Anti-cheat kicks', (string) $record['kicks']);

        $items = $data['inventories'][(string) $record['steamId']] ?? [];
        $grouped = SaveDatabase::groupInventory($items);
        if ($grouped['cash'] > 0) {
            $rows[] = $row('Cash on hand', number_format($grouped['cash']) . ' (banknotes in their inventory)');
        }
        $listOf = fn (array $group) => '<ul style="margin:0 0 .75rem;padding-left:1rem;columns:2;column-gap:2rem;">' . implode('', array_map(
            fn (string $name, int $count) => '<li>' . e($name) . ($count > 1 ? ' &times; ' . number_format($count) : '') . '</li>',
            array_keys($group), $group,
        )) . '</ul>';
        $carrying = $items === []
            ? '<p style="opacity:.7;">' . ($save === null ? 'No inventory data.' : 'Nothing found on the character.') . '</p>'
            : ($grouped['worn'] !== [] ? '<p style="font-weight:600;margin:.25rem 0;">Wearing and holding</p>' . $listOf($grouped['worn']) : '')
                . ($grouped['carried'] !== [] ? '<p style="font-weight:600;margin:.25rem 0;">In pockets and bags</p>' . $listOf($grouped['carried']) : '');

        return '<table style="font-size:.875rem;border-collapse:collapse;margin-bottom:1rem;">' . implode('', $rows) . '</table>'
            . '<p style="font-size:.75rem;opacity:.7;margin:.25rem 0 .5rem;">Inventory as of SCUM\'s last save.</p>' . $carrying;
    }

    /** @return list<string> */
    private function badges(array $record): array
    {
        $badges = [];
        if ($record['online']) {
            $badges[] = $record['vehicle'] ? 'Online, driving' : 'Online';
        }
        foreach (self::FLAG_BADGES as $flag => [$label]) {
            if ($record['flags'][$flag] ?? false) {
                $badges[] = $label;
            }
        }

        return $badges;
    }

    /** @return list<Action> add/remove actions for the admin, whitelist and silence lists */
    private function listActions(): array
    {
        $actions = [];
        foreach (self::LIST_ACTIONS as $flag => [$file, $add, $remove, $icon]) {
            $actions[] = Action::make("list_$flag")
                ->grouped()
                ->iconSize(IconSize::Small)
                ->label(fn (array $record) => $record['flags'][$flag] ? $remove : $add)
                ->icon($icon)
                ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                ->requiresConfirmation()
                ->modalDescription("Changes $file. SCUM reads it at start and rewrites it while running, so the server must be stopped.")
                ->action(fn (array $record, ScumServerService $service) => $this->setList($record, $file, !$record['flags'][$flag], $record['flags'][$flag] ? $remove : $add, $service));
        }

        return $actions;
    }

    private function ban(array $record, ScumServerService $service): void
    {
        $server = $this->getServer();
        try {
            // Like the anti-cheat: add to the list (works while running), then kick if online.
            $service->setPlayerListMembership($server, 'BannedUsers.ini', $record['steamId'], true);
            $kicked = $record['online'] && $this->consoleInstalled && $record['name'] !== ''
                && $service->sendConsoleCommand($server, 'Kick ' . $record['name']);
            Notification::make()
                ->title('Banned ' . ($record['name'] ?: $record['steamId']))
                ->body($record['online'] ? ($kicked ? 'They were kicked.' : 'Kick them from the Console page; the ban applies when they next join.') : 'The ban applies when they next try to join.')
                ->success()
                ->send();
        } catch (Exception $exception) {
            report($exception);
            Notification::make()->title('Could not ban')->body($exception->getMessage())->danger()->send();
        }
        $this->refreshState();
    }

    private function setList(array $record, string $file, bool $member, string $done, ScumServerService $service): void
    {
        $server = $this->getServer();
        $this->refreshState();
        if (!ScumServerService::isStoppedState($this->serverState)) {
            Notification::make()
                ->title('Stop the server first')
                ->body("SCUM rewrites $file while it runs, so the change would be lost.")
                ->warning()
                ->send();

            return;
        }

        try {
            $service->setPlayerListMembership($server, $file, $record['steamId'], $member);
            Notification::make()->title($done . ': ' . ($record['name'] ?: $record['steamId']))->success()->send();
        } catch (Exception $exception) {
            report($exception);
            Notification::make()->title('Could not change ' . $file)->body($exception->getMessage())->danger()->send();
        }
    }

    private function getServer(): Server
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return $server;
    }
}
