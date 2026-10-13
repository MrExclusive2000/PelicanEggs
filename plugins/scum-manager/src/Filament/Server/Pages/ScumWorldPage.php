<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\SubuserPermission;
use App\Filament\Server\Resources\Files\Pages\ListFiles;
use App\Models\Server;
use App\Traits\Filament\BlockAccessInConflict;
use Exception;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Forms\Components\FileUpload;
use Filament\Forms\Components\Select;
use Filament\Infolists\Components\TextEntry;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Illuminate\Support\HtmlString;
use Livewire\Attributes\Locked;
use Livewire\Features\SupportFileUploads\TemporaryUploadedFile;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\Brand;
use MrExclusive\ScumManager\Support\OnlinePlayers;
use MrExclusive\ScumManager\Support\WorldMap;

/**
 * The world at a glance: a live map of players, bases and outposts, every base with its owner
 * and distance to the nearest outpost, and the save backups with restore.
 */
class ScumWorldPage extends Page
{
    use BlockAccessInConflict;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-map-2';

    protected static ?string $slug = 'scum-world';

    protected static ?int $navigationSort = 29;

    protected static ?string $navigationLabel = 'World';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_WORLD;

    /** @var list<array<string, mixed>> */
    #[Locked]
    public array $online = [];

    /** @var list<array<string, mixed>> */
    #[Locked]
    public array $bases = [];

    /** @var list<array{name: string, x: float, y: float}> */
    #[Locked]
    public array $outposts = [];

    /** @var list<array{name: string, size: int, modified: string, wal: bool}> */
    #[Locked]
    public array $backups = [];

    #[Locked]
    public ?string $saveError = null;

    #[Locked]
    public ?int $saveReadAt = null;

    #[Locked]
    public string $serverState = '';

    /** Whether a map picture is stored. The picture itself is drawn from the cache, never kept in
     * the page's state (Livewire refuses requests over 1 MB). */
    #[Locked]
    public bool $hasMapPicture = false;

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
        $this->load();
    }

    protected function load(bool $freshSave = false): void
    {
        $service = app(ScumServerService::class);
        $server = $this->getServer();

        $save = $service->saveData($server, $freshSave);
        $this->bases = $save['bases'] ?? [];
        $this->saveError = $save['error'];
        $this->saveReadAt = $save['readAt'];
        $this->outposts = $service->outposts($server);
        $this->backups = $service->saveBackups($server);
        $this->serverState = $service->powerState($server)->value;
        $this->hasMapPicture = $this->mapPicture() !== null;
        $this->loadLive();
    }

    /** Online players move: re-read every 15 seconds. */
    public function loadLive(): void
    {
        try {
            $this->online = app(ScumServerService::class)->onlinePlayers($this->getServer())['players'];
        } catch (Exception) {
            // Files briefly out of reach: keep what is shown.
        }
    }

    public function content(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Live map')
                ->icon('tabler-map-pin')
                ->description('Players (green, live), bases (orange; red when close to an outpost) and outposts (blue). Hover a marker for details. Bases are as of SCUM\'s last save.')
                ->extraAttributes(['wire:poll.15s' => 'loadLive'])
                ->schema([TextEntry::make('map')->hiddenLabel()->state(fn () => new HtmlString(WorldMap::svg($this->markers(), 640, $this->hasMapPicture ? $this->mapPicture() : null)))]),
            Section::make('Bases')
                ->icon('tabler-building-castle')
                ->description(fn () => $this->saveError !== null
                    ? 'Could not read the save: ' . $this->saveError
                    : count($this->bases) . ' bases in the save, read ' . OnlinePlayers::duration(max(0, time() - (int) $this->saveReadAt)) . ' ago. Red: within ' . WorldMap::OUTPOST_WARNING_METRES . ' m of an outpost (your rules keep outposts clear).')
                ->collapsible()
                ->schema([TextEntry::make('bases')->hiddenLabel()->state(fn () => new HtmlString($this->basesTable()))]),
            Section::make('Save backups')
                ->icon('tabler-database-export')
                ->description('SCUM.db is copied into SaveFiles/' . ScumServerService::SAVE_BACKUP_DIR . ' every time the server starts (the newest 14 are kept), so the daily restart makes a daily backup. Use "Back up now" before anything risky, and "Restore a backup" with the server stopped.')
                ->collapsible()
                ->schema([TextEntry::make('backups')->hiddenLabel()->state(fn () => new HtmlString($this->backupsTable()))]),
        ]);
    }

    /** The map picture as a data: URI (cached by the service), or null. */
    private function mapPicture(): ?string
    {
        try {
            return app(ScumServerService::class)->mapPicture($this->getServer());
        } catch (Exception) {
            return null; // the grid works without it
        }
    }

    /** @return list<array{x: float|int, y: float|int, label: string, kind: string}> */
    private function markers(): array
    {
        $markers = [];
        foreach ($this->outposts as $outpost) {
            $markers[] = ['x' => $outpost['x'], 'y' => $outpost['y'], 'label' => $outpost['name'], 'kind' => 'outpost'];
        }
        foreach ($this->bases as $base) {
            $near = WorldMap::nearest($base['x'], $base['y'], $this->outposts);
            $close = $near !== null && $near['metres'] < WorldMap::OUTPOST_WARNING_METRES;
            $markers[] = ['x' => $base['x'], 'y' => $base['y'], 'kind' => $close ? 'warning' : 'base',
                'label' => trim(($base['name'] !== '' ? $base['name'] . ' - ' : '') . ($base['owner'] ?: 'unknown owner') . ", {$base['elements']} parts" . ($near ? ", {$near['metres']} m from {$near['name']}" : ''))];
        }
        foreach ($this->online as $player) {
            if ($player['x'] !== null && $player['y'] !== null) {
                $markers[] = ['x' => $player['x'], 'y' => $player['y'], 'label' => $player['name'] . ($player['vehicle'] ? ' (driving)' : ''), 'kind' => 'player'];
            }
        }

        return $markers;
    }

    private function basesTable(): string
    {
        if ($this->bases === []) {
            return '<p style="opacity:.7;font-size:.875rem;">No bases in the save.</p>';
        }
        $cell = 'style="padding:.3rem .75rem .3rem 0;text-align:left;vertical-align:top;"';
        $rows = '';
        foreach ($this->bases as $base) {
            $near = WorldMap::nearest($base['x'], $base['y'], $this->outposts);
            $close = $near !== null && $near['metres'] < WorldMap::OUTPOST_WARNING_METRES;
            $rows .= '<tr style="border-top:1px solid rgba(127,127,127,.2);' . ($close ? 'color:#dc2626;' : '') . '">'
                . "<td $cell><strong>" . e($base['owner'] ?: 'Unknown') . '</strong>' . ($base['name'] !== '' ? '<br><span style="opacity:.7;">' . e($base['name']) . '</span>' : '') . '</td>'
                . "<td $cell>" . e(WorldMap::sector($base['x'], $base['y']) ?? '?') . '</td>'
                . "<td $cell>" . (int) $base['elements'] . '</td>'
                . "<td $cell>" . (int) $base['flags'] . '</td>'
                . "<td $cell>" . ($base['overtaker'] !== '' ? 'Being taken over by ' . e($base['overtaker']) : '-') . '</td>'
                . "<td $cell>" . ($near ? e($near['name']) . ', ' . number_format($near['metres']) . ' m' : '-') . '</td>'
                . '</tr>';
        }

        return '<div style="overflow-x:auto;"><table style="width:100%;font-size:.875rem;border-collapse:collapse;">'
            . "<thead><tr><th $cell>Owner</th><th $cell>Sector</th><th $cell>Parts</th><th $cell>Flags</th><th $cell>Takeover</th><th $cell>Nearest outpost</th></tr></thead>"
            . "<tbody>$rows</tbody></table></div>";
    }

    private function backupsTable(): string
    {
        if ($this->backups === []) {
            return '<p style="opacity:.7;font-size:.875rem;">No backups yet. One is made the next time the server starts (re-import the egg first), or press "Back up now".</p>';
        }
        $cell = 'style="padding:.3rem .75rem .3rem 0;text-align:left;"';
        $rows = '';
        foreach ($this->backups as $backup) {
            $rows .= '<tr style="border-top:1px solid rgba(127,127,127,.2);">'
                . "<td $cell><code style=\"font-size:.8rem;\">" . e($backup['name']) . '</code></td>'
                . "<td $cell>" . e($backup['modified'] !== '' ? date('Y-m-d H:i', strtotime($backup['modified'])) . ' UTC' : '?') . '</td>'
                . "<td $cell>" . number_format($backup['size'] / 1048576, 1) . ' MB</td>'
                . '</tr>';
        }

        return '<table style="width:100%;font-size:.875rem;border-collapse:collapse;">'
            . "<thead><tr><th $cell>Backup</th><th $cell>Taken</th><th $cell>Size</th></tr></thead><tbody>$rows</tbody></table>";
    }

    protected function getHeaderActions(): array
    {
        $server = $this->getServer();

        return [
            Action::make('backup')
                ->label('Back up now')
                ->icon('tabler-database-export')
                ->authorize(fn () => user()?->can(SubuserPermission::FileCreate, $server))
                ->requiresConfirmation()
                ->modalDescription('Copies the live SCUM.db into the backups folder. Backups taken while the server runs can miss the last few seconds of changes; the automatic ones at each start are the cleanest.')
                ->action(function (ScumServerService $service) {
                    try {
                        $name = $service->backupSaveNow($this->getServer());
                        Notification::make()->title('Save backed up')->body($name)->success()->send();
                    } catch (Exception $exception) {
                        report($exception);
                        Notification::make()->title('Could not back up the save')->body($exception->getMessage())->danger()->persistent()->send();
                    }
                    $this->backups = $service->saveBackups($this->getServer());
                }),
            Action::make('restore')
                ->label('Restore a backup')
                ->icon('tabler-restore')
                ->color('danger')
                ->visible(fn () => $this->backups !== [])
                ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $server) && user()?->can(SubuserPermission::FileDelete, $server))
                ->modalHeading('Restore a save backup')
                ->modalDescription('The server must be stopped. The world goes back to the moment of the backup: everything after it (bases, items, money) is lost. The current save is kept as SCUM-before-restore-<time>.db, so this can be undone.')
                ->modalSubmitActionLabel('Restore')
                ->schema(fn () => [
                    Select::make('backup')->label('Backup')
                        ->options(collect($this->backups)->mapWithKeys(fn (array $b) => [$b['name'] => $b['name'] . ($b['modified'] !== '' ? ' (' . date('Y-m-d H:i', strtotime($b['modified'])) . ' UTC)' : '')])->all())
                        ->required(),
                ])
                ->action(function (array $data, ScumServerService $service) {
                    try {
                        $service->restoreSave($this->getServer(), (string) $data['backup']);
                        Notification::make()->title('Save restored')->body('Start the server to load ' . $data['backup'] . '.')->success()->persistent()->send();
                    } catch (Exception $exception) {
                        report($exception);
                        Notification::make()->title('Could not restore')->body($exception->getMessage())->danger()->persistent()->send();
                    }
                    $this->load();
                }),
            Action::make('map_picture')
                ->label(fn () => $this->hasMapPicture ? 'Change map picture' : 'Add map picture')
                ->icon('tabler-photo')
                ->color('gray')
                ->authorize(fn () => user()?->can(SubuserPermission::FileCreate, $server) && user()?->can(SubuserPermission::FileUpdate, $server))
                ->modalHeading('Map picture')
                ->modalDescription('A picture of SCUM\'s full map, square, edge to edge (the island\'s full 5 x 5 sector grid), with sector D at the top and column 4 on the left as in game. It is stored in ' . ScumServerService::EXTRAS_DIR . '/ on this server and only shown here.')
                ->schema([
                    FileUpload::make('picture')
                        ->label('Picture (.webp, .png or .jpg, up to 8 MB)')
                        ->required()
                        ->acceptedFileTypes(['image/webp', 'image/png', 'image/jpeg'])
                        ->maxSize(8192)
                        ->storeFiles(false),
                ])
                ->extraModalFooterActions(fn () => !$this->hasMapPicture ? [] : [
                    Action::make('remove_map_picture')
                        ->label('Remove picture')
                        ->color('danger')
                        ->requiresConfirmation()
                        ->action(function (ScumServerService $service) {
                            $service->removeMapPicture($this->getServer());
                            $this->hasMapPicture = false;
                            Notification::make()->title('Map picture removed')->success()->send();
                        }),
                ])
                ->action(function (array $data, ScumServerService $service) {
                    /** @var TemporaryUploadedFile $file */
                    $file = $data['picture'];
                    try {
                        $service->saveMapPicture($this->getServer(), (string) file_get_contents($file->getRealPath()), pathinfo($file->getClientOriginalName(), PATHINFO_EXTENSION));
                        $this->hasMapPicture = true;
                        Notification::make()->title('Map picture saved')->success()->send();
                    } catch (Exception $exception) {
                        report($exception);
                        Notification::make()->title('Could not save the picture')->body($exception->getMessage())->danger()->send();
                    }
                }),
            Action::make('reload')
                ->label('Reload save data')
                ->icon('tabler-refresh')
                ->color('gray')
                ->action(fn () => $this->load(freshSave: true)),
            Action::make('folder')
                ->label('Backups folder')
                ->icon('tabler-folder-open')
                ->color('gray')
                ->url(fn () => ListFiles::getUrl(['path' => ScumServerService::SAVE_DIR . '/' . ScumServerService::SAVE_BACKUP_DIR])),
        ];
    }

    private function getServer(): Server
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return $server;
    }
}
