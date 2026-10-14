<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\SubuserPermission;
use App\Models\Server;
use App\Traits\Filament\BlockAccessInConflict;
use Exception;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Forms\Components\Textarea;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\EmbeddedTable;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Concerns\InteractsWithTable;
use Filament\Tables\Contracts\HasTable;
use Filament\Tables\Table;
use Illuminate\Support\HtmlString;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\AntiCheatReview;
use MrExclusive\ScumManager\Support\Brand;
use MrExclusive\ScumManager\Support\OnlinePlayers;

/**
 * Everyone ExclsvAntiCheat flagged, one row per player with their strikes, kicks and reports, and
 * what to do about them: see the evidence, clear their strikes, stop checking them, unban, note.
 */
class ScumAntiCheatPage extends Page implements HasTable
{
    use BlockAccessInConflict;
    use InteractsWithTable;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-shield-search';

    protected static ?string $slug = 'scum-anticheat';

    protected static ?int $navigationSort = 36;

    protected static ?string $navigationLabel = 'Anti-cheat';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_ANTICHEAT;

    private const RANGES = ['24h' => ['24 hours', 86400], '7d' => ['7 days', 7 * 86400], '30d' => ['30 days', 30 * 86400], 'all' => ['All', null]];

    public string $range = '7d';

    /** Read once per request (the files can be large, so they are not kept in the page state). */
    private ?array $data = null;

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return !$server->isInConflictState()
            && parent::canAccess()
            && user()?->can(SubuserPermission::FileReadContent, $server)
            && app(ScumServerService::class)->isScumServer($server);
    }

    private function data(): array
    {
        return $this->data ??= app(ScumServerService::class)->antiCheatData($this->getServer());
    }

    private function flags(): array
    {
        $seconds = self::RANGES[$this->range][1] ?? self::RANGES['7d'][1];

        return AntiCheatReview::parse($this->data()['flags'], $seconds === null ? 0 : time() - $seconds);
    }

    public function content(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Flagged players')
                ->icon('tabler-shield-search')
                ->description(fn () => $this->data()['installed']
                    ? 'Everyone ' . Brand::mod('ExclsvAntiCheat') . ' flagged in the last ' . strtolower(self::RANGES[$this->range][0] ?? '7 days') . ', most worrying first. Aimbot and wallhack reports only point at who to spectate; they prove nothing on their own. Flags are recorded from 1.37.0 on.'
                    : Brand::mod('ExclsvAntiCheat') . ' is not installed.')
                ->headerActions(array_map(
                    fn (string $key) => Action::make('range_' . $key)->label(self::RANGES[$key][0])->size('sm')
                        ->color(fn () => $this->range === $key ? 'primary' : 'gray')
                        ->action(fn () => $this->range = $key),
                    array_keys(self::RANGES),
                ))
                ->schema([EmbeddedTable::make()]),
        ]);
    }

    public function table(Table $table): Table
    {
        $server = $this->getServer();

        return $table
            ->records(function () {
                $data = $this->data();

                return collect(AntiCheatReview::players(
                    $this->flags(),
                    AntiCheatReview::offenses($data['offenses']),
                    AntiCheatReview::steamIds($data['banned']),
                    $data['ignored'],
                    $data['notes'],
                ))->keyBy('key')->all();
            })
            ->paginated(false)
            ->emptyStateHeading('Nobody flagged')
            ->emptyStateDescription('Nothing in this period.')
            ->columns([
                TextColumn::make('name')->label('Player')->weight('bold')
                    ->description(fn (array $record) => $record['steamId'] ?: 'SteamID not known'),
                TextColumn::make('counts')->label('Flags')
                    ->state(fn (array $record) => AntiCheatReview::countsText($record['counts']))
                    ->wrap(),
                TextColumn::make('kicks')->label('Kicks (all time)'),
                TextColumn::make('status')->label('Status')->badge()
                    ->state(fn (array $record) => array_values(array_filter([
                        $record['banned'] ? 'Banned' : null,
                        $record['ignored'] ? 'Not checked' : null,
                    ])) ?: ['-'])
                    ->color(fn (string $state) => match ($state) {
                        'Banned' => 'danger',
                        'Not checked' => 'warning',
                        default => 'gray',
                    }),
                TextColumn::make('last')->label('Latest')
                    ->state(fn (array $record) => OnlinePlayers::duration(max(0, time() - $record['last'])) . ' ago')
                    ->description(fn (array $record) => mb_strimwidth($record['lastDetail'], 0, 90, '…'))
                    ->wrap(),
                TextColumn::make('note')->label('Note')->placeholder('-')->wrap()->limit(80),
            ])
            ->recordActions([
                Action::make('details')
                    ->label('Details')
                    ->icon('tabler-list-search')
                    ->color('gray')
                    ->modalHeading(fn (array $record) => $record['name'] . ($record['steamId'] ? " ({$record['steamId']})" : ''))
                    ->modalSubmitAction(false)
                    ->modalCancelActionLabel('Close')
                    ->modalContent(fn (array $record) => new HtmlString($this->detailsHtml($record))),
                Action::make('clear')
                    ->label('Clear strikes')
                    ->icon('tabler-eraser')
                    ->color('gray')
                    ->visible(fn (array $record) => $record['steamId'] !== '' && $this->data()['installed'])
                    ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $server))
                    ->requiresConfirmation()
                    ->modalDescription('Forgets their current strikes and their kick count (so the next kicks start again towards a ban). The flags stay listed here.')
                    ->action(fn (array $record, ScumServerService $service) => $this->run(
                        fn () => $service->clearAntiCheatStrikes($server, $record['steamId']),
                        'Strikes cleared for ' . $record['name'],
                        'Takes effect within a few seconds while the server runs.',
                    )),
                Action::make('ignore')
                    ->label(fn (array $record) => $record['ignored'] ? 'Check again' : 'Stop checking')
                    ->icon(fn (array $record) => $record['ignored'] ? 'tabler-eye' : 'tabler-eye-off')
                    ->color('gray')
                    ->visible(fn (array $record) => $record['steamId'] !== '' && $this->data()['installed'])
                    ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $server))
                    ->requiresConfirmation()
                    ->modalDescription(fn (array $record) => $record['ignored']
                        ? 'Removes them from ignoreSteamIds: they are checked again.'
                        : 'Adds them to ignoreSteamIds: none of the checks apply to them any more. Use it for trusted players who keep being flagged by mistake.')
                    ->action(fn (array $record, ScumServerService $service) => $this->run(
                        fn () => $service->setAntiCheatIgnored($server, $record['steamId'], !$record['ignored']),
                        ($record['ignored'] ? 'Checking ' : 'No longer checking ') . $record['name'],
                        'Takes effect within 30 seconds.',
                    )),
                Action::make('unban')
                    ->label('Unban')
                    ->icon('tabler-circle-check')
                    ->color('success')
                    ->visible(fn (array $record) => $record['banned'])
                    ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $server))
                    ->requiresConfirmation()
                    ->modalDescription('Removes them from BannedUsers.ini. The server must be stopped: SCUM rewrites that file while it runs.')
                    ->action(function (array $record, ScumServerService $service) use ($server) {
                        if (!$service->isStopped($server)) {
                            Notification::make()->title('Stop the server first')->body('SCUM rewrites BannedUsers.ini while it runs, so the change would be lost.')->warning()->send();

                            return;
                        }
                        $this->run(fn () => $service->setPlayerListMembership($server, 'BannedUsers.ini', $record['steamId'], false), 'Unbanned ' . $record['name']);
                    }),
                Action::make('note')
                    ->label('Note')
                    ->icon('tabler-notes')
                    ->color('gray')
                    ->visible(fn (array $record) => $record['steamId'] !== '')
                    ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $server))
                    ->modalHeading(fn (array $record) => 'Note about ' . $record['name'])
                    ->schema(fn (array $record) => [
                        Textarea::make('note')->hiddenLabel()->default($record['note'])->rows(4)->maxLength(1000)
                            ->placeholder('E.g. spectated 14 Oct, looks legit. Empty removes the note.'),
                    ])
                    ->action(fn (array $record, array $data, ScumServerService $service) => $this->run(
                        fn () => $service->saveAntiCheatNote($server, $record['steamId'], (string) ($data['note'] ?? '')),
                        'Note saved',
                    )),
            ]);
    }

    private function run(\Closure $change, string $done, ?string $body = null): void
    {
        try {
            $change();
            Notification::make()->title($done)->body($body)->success()->send();
        } catch (Exception $exception) {
            report($exception);
            Notification::make()->title('Could not do that')->body($exception->getMessage())->danger()->send();
        }
        $this->data = null;
    }

    private function detailsHtml(array $record): string
    {
        $flags = array_reverse(array_filter($this->flags(), fn (array $flag) => ($flag['steamId'] !== '' ? $flag['steamId'] : 'name:' . $flag['name']) === $record['key']));
        $rows = '';
        foreach (array_slice($flags, 0, 200) as $flag) {
            $rows .= '<tr><td style="padding: .25rem .5rem; white-space: nowrap; vertical-align: top;">' . e(gmdate('Y-m-d H:i', $flag['time'])) . '</td>'
                . '<td style="padding: .25rem .5rem; white-space: nowrap; vertical-align: top; font-weight: 600;">' . e(AntiCheatReview::KINDS[$flag['kind']][0]) . '</td>'
                . '<td style="padding: .25rem .5rem;">' . e($flag['detail']) . '</td></tr>';
        }
        $summary = '<p style="margin-bottom: .5rem;">' . e(AntiCheatReview::countsText($record['counts']) . '. Kicked ' . $record['kicks'] . ' time(s) in all.'
            . ($record['banned'] ? ' Banned.' : '') . ($record['ignored'] ? ' Not checked (ignoreSteamIds).' : '')) . '</p>';
        $note = $record['note'] !== '' ? '<p style="margin-bottom: .5rem; opacity: .8;">Note: ' . e($record['note']) . '</p>' : '';

        return $summary . $note . '<div style="max-height: 28rem; overflow-y: auto;"><table style="width: 100%; border-collapse: collapse; font-size: .85rem;">'
            . '<thead><tr><th style="text-align: left; padding: .25rem .5rem;">When (UTC)</th><th style="text-align: left; padding: .25rem .5rem;">What</th><th style="text-align: left; padding: .25rem .5rem;">Detail</th></tr></thead>'
            . '<tbody>' . $rows . '</tbody></table></div>';
    }

    private function getServer(): Server
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return $server;
    }
}
