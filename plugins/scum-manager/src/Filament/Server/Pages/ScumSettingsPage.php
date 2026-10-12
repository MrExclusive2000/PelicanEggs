<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\ContainerStatus;
use App\Enums\SubuserPermission;
use App\Filament\Server\Pages\ServerFormPage;
use App\Filament\Server\Resources\Files\Pages\ListFiles;
use App\Models\Server;
use Exception;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Notifications\Notification;
use Filament\Schemas\Components\Component;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Components\Tabs;
use Filament\Schemas\Components\Tabs\Tab;
use Filament\Schemas\Components\Text;
use Filament\Schemas\Components\Utilities\Get;
use Filament\Schemas\Schema;
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\IniDocument;
use MrExclusive\ScumManager\Support\SettingLabel;
use MrExclusive\ScumManager\Support\SettingType;
use MrExclusive\ScumManager\Support\Brand;

class ScumSettingsPage extends ServerFormPage
{
    protected static string|\BackedEnum|null $navigationIcon = 'tabler-adjustments-horizontal';

    protected static ?string $slug = 'scum-settings';

    protected static ?int $navigationSort = 31;

    protected static ?string $navigationLabel = Brand::PAGE_SETTINGS;

    protected static ?string $title = Brand::PAGE_SETTINGS;

    /**
     * One entry per setting in the file, keyed by a form-safe id (INI keys contain dots,
     * which Filament would treat as nested state paths).
     *
     * @var array<string, array{section: string, key: string, type: string, value: string, state: mixed, managed: ?string}>
     */
    #[Locked]
    public array $settings = [];

    #[Locked]
    public ?string $fileHash = null;

    #[Locked]
    public bool $fileMissing = false;

    #[Locked]
    public string $serverState = '';

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return parent::canAccess()
            && user()?->can(SubuserPermission::FileReadContent, $server)
            && app(ScumServerService::class)->isScumServer($server);
    }

    protected function fillForm(): void
    {
        $this->loadSettings();
    }

    public function loadSettings(): void
    {
        $service = app(ScumServerService::class);
        $server = $this->getRecord();

        $this->serverState = $service->powerState($server)->value;
        $this->settings = [];
        $state = ['search' => '', 'fields' => []];

        try {
            $raw = $service->read($server, $service->configPath(ScumServerService::SETTINGS_FILE));
        } catch (Exception $exception) {
            report($exception);
            $raw = null;

            Notification::make()
                ->title('Could not read ServerSettings.ini')
                ->body($exception->getMessage())
                ->danger()
                ->send();
        }

        $this->fileMissing = $raw === null;
        $this->fileHash = $raw === null ? null : sha1($raw);

        if ($raw !== null) {
            $managed = $service->eggManagedSettings($server);

            foreach (IniDocument::parse($raw)->entries() as $entry) {
                $id = 'k' . substr(sha1($entry['section'] . "\0" . $entry['key']), 0, 16);
                $type = SettingType::infer($entry['value']);

                $this->settings[$id] = [
                    'section' => $entry['section'],
                    'key' => $entry['key'],
                    'type' => $type->value,
                    'value' => $entry['value'],
                    'state' => $type->toState($entry['value']),
                    'managed' => $managed[$entry['section']][$entry['key']] ?? null,
                ];

                $state['fields'][$id] = $this->settings[$id]['state'];
            }
        }

        $this->form->fill($state);
    }

    public function form(Schema $schema): Schema
    {
        if ($this->fileMissing) {
            return parent::form($schema)->components([
                Section::make('ServerSettings.ini not found')
                    ->description('SCUM creates this file the first time the server starts. Start the server once, wait until it is online, stop it, then come back here.')
                    ->icon('tabler-file-alert'),
            ]);
        }

        $sections = [];
        foreach ($this->settings as $id => $setting) {
            $sections[$setting['section']][$id] = $setting;
        }

        $tabs = [];
        foreach ($sections as $section => $settings) {
            $tabs[] = Tab::make($section)
                ->badge(count($settings))
                ->schema([
                    Grid::make(['default' => 1, 'lg' => 2])
                        ->schema(array_map(
                            fn (string $id) => $this->makeField($id, $settings[$id]),
                            array_keys($settings),
                        )),
                ]);
        }

        return parent::form($schema)->components([
            Section::make()
                ->schema([
                    Text::make(fn () => $this->stateMessage())
                        ->color(fn () => $this->isStopped() ? 'success' : 'warning'),
                    Text::make('Values follow SCUM\'s own conventions: -1 means "use the game default", multipliers use 1 as normal, durations are HH:MM:SS and prices ending in "g" are gold. Keys set by the egg are read-only here; change them on the Startup page.')
                        ->color('gray'),
                    TextInput::make('search')
                        ->hiddenLabel()
                        ->placeholder('Search settings…')
                        ->prefixIcon('tabler-search')
                        ->live(debounce: 400),
                ]),
            Tabs::make('sections')
                ->tabs($tabs)
                ->persistTabInQueryString(),
        ]);
    }

    /** @param  array{section: string, key: string, type: string, value: string, state: mixed, managed: ?string}  $setting */
    private function makeField(string $id, array $setting): Component
    {
        $type = SettingType::from($setting['type']);
        $name = "fields.$id";
        $label = SettingLabel::fromKey($setting['key']);
        $isPassword = str_contains(strtolower($setting['key']), 'password');

        $field = match ($type) {
            SettingType::Toggle => Toggle::make($name)->inline(false),
            SettingType::Integer => TextInput::make($name)->integer(),
            SettingType::Decimal => TextInput::make($name)->numeric(),
            SettingType::Duration => TextInput::make($name)->placeholder('HH:MM:SS'),
            SettingType::Gold => TextInput::make($name)->placeholder('e.g. 2g'),
            SettingType::Text => $isPassword
                ? TextInput::make($name)->password()->revealable()
                : TextInput::make($name),
        };

        $field
            ->label($label)
            ->hint($setting['key'])
            ->rules($type->rules())
            ->validationAttribute($label)
            ->hidden(function (Get $get) use ($setting, $label) {
                $search = strtolower(trim((string) $get('data.search', isAbsolute: true)));

                return $search !== ''
                    && !str_contains(strtolower($setting['key']), $search)
                    && !str_contains(strtolower($label), $search);
            });

        if ($setting['managed'] !== null) {
            $field->disabled()->helperText('Set by the egg on every start. Change it on the Startup page.');
        } elseif (in_array(trim($setting['value']), ['-1', '-1.000000'], true)) {
            $field->helperText('-1 = use the game default');
        }

        return $field;
    }

    public function save(bool $andStart = false): void
    {
        $server = $this->getRecord();
        abort_unless(user()?->can(SubuserPermission::FileUpdate, $server), 403);

        if ($this->fileMissing) {
            return;
        }

        $service = app(ScumServerService::class);
        $data = $this->form->getState();

        if (!$service->isStopped($server)) {
            Notification::make()
                ->title('Stop the server first')
                ->body('SCUM rewrites ServerSettings.ini while it runs, so changes are only saved while the server is stopped.')
                ->warning()
                ->send();

            return;
        }

        try {
            $path = $service->configPath(ScumServerService::SETTINGS_FILE);
            $raw = $service->read($server, $path);

            if ($raw === null || sha1($raw) !== $this->fileHash) {
                Notification::make()
                    ->title('ServerSettings.ini changed since you opened this page')
                    ->body('Reload the page to see the current values, then make your changes again.')
                    ->warning()
                    ->persistent()
                    ->send();

                return;
            }

            $document = IniDocument::parse($raw);
            $changed = [];

            foreach ($this->settings as $id => $setting) {
                if ($setting['managed'] !== null || !array_key_exists($id, $data['fields'] ?? [])) {
                    continue;
                }

                $type = SettingType::from($setting['type']);
                $new = $type->toIni($data['fields'][$id], $setting['value']);

                if ($new !== $type->toIni($setting['state'], $setting['value'])) {
                    $document->set($setting['section'], $setting['key'], $new);
                    $changed[] = $setting['key'];
                }
            }

            if ($changed === []) {
                Notification::make()->title('No changes to save')->info()->send();

                if ($andStart) {
                    $this->startServer();
                }

                return;
            }

            $backup = $service->backup($server, ScumServerService::SETTINGS_FILE, $raw);
            $service->write($server, $path, $document->render());

            Notification::make()
                ->title(count($changed) === 1 ? 'Saved 1 setting' : 'Saved ' . count($changed) . ' settings')
                ->body('Previous version backed up as ' . $backup)
                ->success()
                ->send();

            $this->loadSettings();

            if ($andStart) {
                $this->startServer();
            }
        } catch (Exception $exception) {
            report($exception);

            Notification::make()
                ->title('Could not save ServerSettings.ini')
                ->body($exception->getMessage())
                ->danger()
                ->send();
        }
    }

    private function startServer(): void
    {
        $server = $this->getRecord();
        abort_unless(user()?->can(SubuserPermission::ControlStart, $server), 403);

        app(ScumServerService::class)->power($server, 'start');
        $this->serverState = ContainerStatus::Starting->value;

        Notification::make()->title('Server starting')->success()->send();
    }

    private function isStopped(): bool
    {
        return ScumServerService::isStoppedState($this->serverState);
    }

    private function stateMessage(): string
    {
        if ($this->isStopped()) {
            return 'The server is stopped, so changes can be saved.';
        }

        $label = ContainerStatus::tryFrom($this->serverState)?->getLabel() ?? 'unknown';

        return "The server is $label. Stop it before saving: SCUM rewrites this file while it runs.";
    }

    protected function getHeaderActions(): array
    {
        $server = $this->getRecord();

        return [
            Action::make('save')
                ->label('Save')
                ->icon('tabler-device-floppy')
                ->visible(fn () => !$this->fileMissing && user()?->can(SubuserPermission::FileUpdate, $server))
                ->disabled(fn () => !$this->isStopped())
                ->action(fn () => $this->save()),
            Action::make('save_start')
                ->label('Save & start')
                ->icon('tabler-player-play')
                ->color('success')
                ->visible(fn () => !$this->fileMissing && user()?->can(SubuserPermission::FileUpdate, $server) && user()?->can(SubuserPermission::ControlStart, $server))
                ->disabled(fn () => !$this->isStopped())
                ->action(fn () => $this->save(true)),
            Action::make('stop')
                ->label('Stop server')
                ->icon('tabler-player-stop')
                ->color('danger')
                ->requiresConfirmation()
                ->modalDescription('Players will be disconnected. SCUM saves the world as it shuts down.')
                ->visible(fn () => !$this->isStopped() && user()?->can(SubuserPermission::ControlStop, $server))
                ->action(function (ScumServerService $service) use ($server) {
                    $service->power($server, 'stop');
                    $this->serverState = ContainerStatus::Stopping->value;

                    Notification::make()
                        ->title('Stopping the server')
                        ->body('Click Refresh once it shows as offline.')
                        ->send();
                }),
            Action::make('refresh')
                ->label('Refresh')
                ->icon('tabler-refresh')
                ->color('gray')
                ->action(fn () => $this->loadSettings()),
            Action::make('restore_backup')
                ->label('Backups')
                ->icon('tabler-history')
                ->color('gray')
                ->visible(fn () => user()?->can(SubuserPermission::FileUpdate, $server))
                ->modalHeading('Restore a backup of ServerSettings.ini')
                ->modalDescription('A backup is taken automatically before every save. Restoring also backs up the current file first.')
                ->modalSubmitActionLabel('Restore')
                ->schema(fn (ScumServerService $service) => [
                    Select::make('backup')
                        ->label('Backup')
                        ->options(fn () => collect($service->backups($server, ScumServerService::SETTINGS_FILE))
                            ->mapWithKeys(fn (string $name) => [$name => $this->describeBackup($name)])
                            ->all())
                        ->required()
                        ->native(false),
                ])
                ->action(function (array $data, ScumServerService $service) use ($server) {
                    if (!$service->isStopped($server)) {
                        Notification::make()->title('Stop the server first')->warning()->send();

                        return;
                    }

                    try {
                        $service->restoreBackup($server, ScumServerService::SETTINGS_FILE, $data['backup']);
                        $this->loadSettings();

                        Notification::make()->title('Backup restored')->success()->send();
                    } catch (Exception $exception) {
                        report($exception);

                        Notification::make()->title('Could not restore the backup')->body($exception->getMessage())->danger()->send();
                    }
                }),
            Action::make('open_folder')
                ->label('Open folder')
                ->icon('tabler-folder-open')
                ->color('gray')
                ->url(fn () => ListFiles::getUrl(['path' => config('scum-manager.config_dir')])),
        ];
    }

    private function describeBackup(string $name): string
    {
        if (preg_match('/\.bak-(\d{8}-\d{6})$/', $name, $match)) {
            $date = \Illuminate\Support\Carbon::createFromFormat('Ymd-His', $match[1]);

            return $date->format('j M Y, H:i:s') . ' (' . $date->diffForHumans() . ')';
        }

        return $name;
    }
}
