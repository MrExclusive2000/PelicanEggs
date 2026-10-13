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
use Filament\Infolists\Components\TextEntry;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\EmbeddedTable;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Concerns\InteractsWithTable;
use Filament\Tables\Contracts\HasTable;
use Filament\Tables\Table;
use Livewire\Features\SupportFileUploads\TemporaryUploadedFile;
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\Brand;

class ScumModsPage extends Page implements HasTable
{
    use BlockAccessInConflict;
    use InteractsWithTable;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-puzzle';

    protected static ?string $slug = 'scum-mods';

    protected static ?int $navigationSort = 33;

    protected static ?string $navigationLabel = 'Mods';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_MODS;

    /** @var array{installed: bool, root: string, mods: string, layout: string, proxy: bool}|null */
    #[Locked]
    public ?array $ue4ss = null;

    #[Locked]
    public bool $dwmapiOverride = false;

    #[Locked]
    public ?bool $overrideVariableExists = null;

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        // The trait's canAccess() is replaced by this one, so its check is repeated here: no access
        // while the server is suspended, installing, restoring a backup or being transferred.
        return !$server->isInConflictState()
            && parent::canAccess()
            && user()?->can(SubuserPermission::FileRead, $server)
            && app(ScumServerService::class)->isScumServer($server);
    }

    public function mount(): void
    {
        $this->refreshStatus();
    }

    public function refreshStatus(): void
    {
        $service = app(ScumServerService::class);
        $server = $this->getServer();

        $this->ue4ss = $service->ue4ss($server);
        $this->overrideVariableExists = $service->variable($server, 'WINEDLLOVERRIDES') !== null;
        $this->dwmapiOverride = $service->hasDwmapiOverride($server);
    }

    public function content(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('UE4SS')
                ->description('SCUM has no official mod support yet. Server-side mods run through UE4SS, a script loader for Unreal Engine games. Players do not need to install anything, and BattlEye stays on.')
                ->schema([
                    Grid::make(['default' => 1, 'md' => 3])->schema([
                        TextEntry::make('ue4ss_status')
                            ->label('UE4SS')
                            ->state(fn () => ($this->ue4ss['installed'] ?? false) ? 'Installed' : 'Not installed')
                            ->badge()
                            ->color(fn () => ($this->ue4ss['installed'] ?? false) ? 'success' : 'gray'),
                        TextEntry::make('wine_override')
                            ->label('Wine DLL override (dwmapi=n,b)')
                            ->state(fn () => $this->dwmapiOverride ? 'Set' : 'Missing')
                            ->badge()
                            ->color(fn () => $this->dwmapiOverride ? 'success' : 'danger')
                            ->helperText(fn () => $this->dwmapiOverride ? null : $this->overrideHelp()),
                        TextEntry::make('mods_folder')
                            ->label('Mods folder')
                            ->state(fn () => $this->ue4ss['mods'] ?? '-'),
                    ]),
                ]),
            EmbeddedTable::make(),
        ]);
    }

    private function overrideHelp(): string
    {
        return $this->overrideVariableExists
            ? 'Add ";dwmapi=n,b" to the WINEDLLOVERRIDES variable on the Startup page, or Wine ignores UE4SS.'
            : 'This egg has no WINEDLLOVERRIDES variable. Re-import the updated SCUM egg, or Wine ignores UE4SS.';
    }

    public function table(Table $table): Table
    {
        return $table
            ->records(fn () => collect(app(ScumServerService::class)->mods($this->getServer()))->keyBy('name')->all())
            ->paginated(false)
            ->emptyStateHeading(fn () => ($this->ue4ss['installed'] ?? false) ? 'No mods yet' : 'UE4SS is not installed')
            ->emptyStateDescription(fn () => ($this->ue4ss['installed'] ?? false)
                ? 'Upload a mod zip to get started.'
                : 'Install UE4SS first, then upload mods.')
            ->columns([
                TextColumn::make('name')
                    ->label('Mod')
                    ->weight('bold')
                    ->formatStateUsing(fn (string $state) => Brand::mod($state))
                    ->description(fn (array $record) => $record['builtin'] ? 'Ships with UE4SS' : (($record['bundled'] ?? false) ? 'Ships with ' . Brand::MANAGER . ' (folder ' . $record['name'] . ')' : null)),
                TextColumn::make('type')
                    ->badge()
                    ->color('gray'),
                IconColumn::make('enabled')
                    ->boolean(),
            ])
            ->recordActions([
                Action::make('toggle')
                    ->label(fn (array $record) => $record['enabled'] ? 'Disable' : 'Enable')
                    ->icon(fn (array $record) => $record['enabled'] ? 'tabler-toggle-right' : 'tabler-toggle-left')
                    ->color(fn (array $record) => $record['enabled'] ? 'warning' : 'success')
                    ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                    ->action(function (array $record, ScumServerService $service) {
                        try {
                            $service->setModEnabled($this->getServer(), $record['name'], !$record['enabled']);

                            Notification::make()
                                ->title(($record['enabled'] ? 'Disabled ' : 'Enabled ') . $record['name'])
                                ->body('Restart the server to apply.')
                                ->success()
                                ->send();
                        } catch (Exception $exception) {
                            report($exception);
                            Notification::make()->title('Could not change the mod')->body($exception->getMessage())->danger()->send();
                        }
                    }),
                Action::make('files')
                    ->label('Files')
                    ->icon('tabler-folder-open')
                    ->color('gray')
                    ->url(fn (array $record) => ListFiles::getUrl(['path' => ($this->ue4ss['mods'] ?? '') . '/' . $record['name']])),
                Action::make('delete')
                    ->label('Delete')
                    ->icon('tabler-trash')
                    ->color('danger')
                    ->hidden(fn (array $record) => $record['builtin'])
                    ->authorize(fn () => user()?->can(SubuserPermission::FileDelete, $this->getServer()))
                    ->requiresConfirmation()
                    ->modalHeading(fn (array $record) => "Delete {$record['name']}?")
                    ->modalDescription('The mod folder and its config are deleted from the server.')
                    ->action(function (array $record, ScumServerService $service) {
                        try {
                            $service->deleteMod($this->getServer(), $record['name']);

                            Notification::make()->title("Deleted {$record['name']}")->success()->send();
                        } catch (Exception $exception) {
                            report($exception);
                            Notification::make()->title('Could not delete the mod')->body($exception->getMessage())->danger()->send();
                        }
                    }),
            ]);
    }

    /** What "Install / update our mods" will do, mod by mod. */
    private function updateSummary(ScumServerService $service): string
    {
        $server = $this->getServer();
        $installed = $service->installedModsOf($server, array_keys(Brand::MODS));

        try {
            $latest = $service->modSource() !== null ? $service->latestModManifest() : null;
        } catch (Exception) {
            $latest = null;
        }

        $wanted = array_values(array_unique(array_merge(array_keys(ScumServerService::bundledMods()), $installed)));
        $lines = [];
        foreach ($wanted as $mod) {
            $build = in_array($mod, $installed, true) ? $service->installedBuild($server, $mod) : null;
            // With a source set but unreachable there is nothing to compare with: a mod installed from
            // GitHub earlier can be newer than the bundled copy.
            $newest = $service->modSource() === null
                ? (ScumServerService::bundledBuilds()[$mod]['build'] ?? null)
                : ($latest['mods'][$mod]['build'] ?? null);
            $lines[] = Brand::mod($mod) . ': ' . match (true) {
                !in_array($mod, $installed, true) => 'will be installed',
                $newest === null => 'kept as it is',
                $build === $newest => 'up to date (reinstalled)',
                default => 'update available',
            };
        }

        $from = $latest !== null
            ? 'The latest versions are downloaded from GitHub and checked before installing.'
            : ($service->modSource() !== null
                ? 'GitHub cannot be reached right now: only missing mods are installed (from the copies bundled with the panel); installed ones are kept.'
                : 'The copies bundled with the panel are used.');

        $legacy = $service->legacyFolders($server);
        $moves = $legacy['rename'] + $legacy['conflicts'];
        $move = $moves === [] ? '' : ' First, our mods move to their new folder names ('
            . implode(', ', array_map(fn ($old, $new) => "$old → $new", array_keys($moves), $moves))
            . '), with their settings and player data. The server must be stopped for that.';

        return $from . $move . ' Settings (config.lua) are kept. ' . implode('. ', $lines) . '. Restart the server afterwards.';
    }

    protected function getHeaderActions(): array
    {
        return [
            Action::make('upload')
                ->label('Upload mod')
                ->icon('tabler-upload')
                ->visible(fn () => $this->ue4ss['installed'] ?? false)
                ->authorize(fn () => user()?->can(SubuserPermission::FileCreate, $this->getServer()))
                ->modalHeading('Upload a UE4SS mod')
                ->modalDescription('Upload the mod\'s .zip as downloaded. Each folder in it that contains Scripts/main.lua or dlls/main.dll is installed and enabled. Uploading a mod that already exists updates its files and keeps its settings (config.lua).')
                ->schema([
                    FileUpload::make('archive')
                        ->label('Mod archive (.zip)')
                        ->required()
                        ->acceptedFileTypes(['application/zip', 'application/zip-compressed', 'application/x-zip-compressed'])
                        ->maxSize((int) config('scum-manager.mod_upload_max_kb', 51200))
                        ->preserveFilenames()
                        ->previewable(false)
                        ->storeFiles(false),
                ])
                ->action(function (array $data, ScumServerService $service) {
                    /** @var TemporaryUploadedFile $file */
                    $file = $data['archive'];

                    try {
                        // An update must not reset the mod's settings: an existing config.lua is kept.
                        $installed = $service->installModArchive($this->getServer(), $file->getRealPath(), $file->getClientOriginalName(), keepSettings: true);

                        Notification::make()
                            ->title('Installed ' . implode(', ', $installed))
                            ->body('Restart the server to load it.')
                            ->success()
                            ->send();
                    } catch (Exception $exception) {
                        report($exception);
                        Notification::make()->title('Could not install the mod')->body($exception->getMessage())->danger()->persistent()->send();
                    } finally {
                        $file->delete();
                    }
                }),
            Action::make('install_ue4ss')
                ->label(fn () => ($this->ue4ss['installed'] ?? false) ? 'Update UE4SS' : 'Install UE4SS')
                ->icon('tabler-download')
                ->color(fn () => ($this->ue4ss['installed'] ?? false) ? 'gray' : 'primary')
                ->authorize(fn () => user()?->can(SubuserPermission::FileCreate, $this->getServer()) && user()?->can(SubuserPermission::FileArchive, $this->getServer()))
                ->requiresConfirmation()
                ->modalHeading(fn () => ($this->ue4ss['installed'] ?? false) ? 'Update UE4SS?' : 'Install UE4SS?')
                ->modalDescription(fn () => 'Downloads the latest ' . config('scum-manager.ue4ss_channel') . ' UE4SS build from GitHub into ' . config('scum-manager.binaries_dir') . '. Your mods, mods.txt and UE4SS-settings.ini are kept. A fresh install also installs the mods that ship with SCUM Manager. The server must be stopped.')
                ->action(function (ScumServerService $service) {
                    $server = $this->getServer();

                    if (!$service->isStopped($server)) {
                        Notification::make()->title('Stop the server first')->warning()->send();

                        return;
                    }

                    try {
                        $url = $service->installUe4ss($server);
                        $this->refreshStatus();

                        Notification::make()
                            ->title('UE4SS installed')
                            ->body(basename($url) . ($this->dwmapiOverride ? '' : '. ' . $this->overrideHelp()))
                            ->success()
                            ->persistent()
                            ->send();
                    } catch (Exception $exception) {
                        report($exception);
                        Notification::make()->title('Could not install UE4SS')->body($exception->getMessage())->danger()->persistent()->send();
                    }
                }),
            Action::make('install_bundled')
                ->label('Install / update our mods')
                ->icon('tabler-package')
                ->color('gray')
                ->visible(fn () => ($this->ue4ss['installed'] ?? false) && (ScumServerService::bundledMods() !== [] || app(ScumServerService::class)->modSource() !== null))
                ->authorize(fn () => user()?->can(SubuserPermission::FileCreate, $this->getServer()))
                ->requiresConfirmation()
                ->modalHeading('Install or update the ' . Brand::MANAGER . ' mods?')
                ->modalDescription(fn (ScumServerService $service) => $this->updateSummary($service))
                ->action(function (ScumServerService $service) {
                    try {
                        $result = $service->installLatestMods($this->getServer());
                        $names = implode(', ', array_map(Brand::mod(...), $result['installed']));
                        $body = array_merge(
                            [$result['fromSource'] !== [] ? 'Latest versions downloaded from GitHub; settings kept.' : 'Bundled versions installed; settings kept.'],
                            $result['notes'],
                            $result['manager'] !== null ? [Brand::MANAGER . ' ' . $result['manager'] . ' is available: import the new plugin zip to update the panel itself.'] : [],
                            ['Restart the server to load them.'],
                        );

                        Notification::make()
                            ->title($names === '' ? 'Nothing was installed' : 'Installed ' . $names)
                            ->body(implode(' ', $body))
                            ->status($result['notes'] === [] ? 'success' : 'warning')
                            ->persistent($result['notes'] !== [] || $result['manager'] !== null)
                            ->send();
                    } catch (Exception $exception) {
                        report($exception);
                        Notification::make()->title('Could not install the mods')->body($exception->getMessage())->danger()->persistent()->send();
                    }
                }),
            Action::make('safe_settings')
                ->label('SCUM-safe UE4SS settings')
                ->icon('tabler-shield-check')
                ->color('gray')
                ->visible(fn () => $this->ue4ss['installed'] ?? false)
                ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                ->requiresConfirmation()
                ->modalHeading('Apply SCUM-safe UE4SS settings?')
                ->modalDescription('UE4SS turns on about sixteen engine hooks by default, and on SCUM 1.3 those crash the server as soon as a player joins. This turns off every hook except HookCallFunctionByNameWithArguments and HookEngineTick, and disables the UE4SS console window. Fresh installs already get these settings. Restart the server to apply.')
                ->action(function (ScumServerService $service) {
                    try {
                        $service->applyScumSafeUe4ssSettings($this->getServer());

                        Notification::make()->title('UE4SS-settings.ini updated')->body('Restart the server to apply.')->success()->send();
                    } catch (Exception $exception) {
                        report($exception);
                        Notification::make()->title('Could not update UE4SS-settings.ini')->body($exception->getMessage())->danger()->send();
                    }
                }),
            Action::make('disable_builtins')
                ->label('Disable built-in mods')
                ->icon('tabler-toggle-left')
                ->color('gray')
                ->visible(fn () => $this->ue4ss['installed'] ?? false)
                ->authorize(fn () => user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                ->requiresConfirmation()
                ->modalHeading('Disable the mods that ship with UE4SS?')
                ->modalDescription('They are client tools: the in-game console, the cheat manager (which hooks every player spawn), keybinds and the Blueprint mod loader. None are needed on a dedicated server. Your own mods are not touched. Re-enable BPModLoaderMod and BPML_GenericFunctions only if a mod says it needs them. Restart the server to apply.')
                ->action(function (ScumServerService $service) {
                    try {
                        $service->disableBuiltinMods($this->getServer());

                        Notification::make()->title('Built-in mods disabled')->body('Restart the server to apply.')->success()->send();
                    } catch (Exception $exception) {
                        report($exception);
                        Notification::make()->title('Could not update mods.txt')->body($exception->getMessage())->danger()->send();
                    }
                }),
            Action::make('open_folder')
                ->label('Open folder')
                ->icon('tabler-folder-open')
                ->color('gray')
                ->url(fn () => ListFiles::getUrl(['path' => ($this->ue4ss['installed'] ?? false) ? $this->ue4ss['mods'] : config('scum-manager.binaries_dir')])),
            Action::make('refresh')
                ->label('Refresh')
                ->icon('tabler-refresh')
                ->color('gray')
                ->action(fn () => $this->refreshStatus()),
        ];
    }

    private function getServer(): Server
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return $server;
    }
}
