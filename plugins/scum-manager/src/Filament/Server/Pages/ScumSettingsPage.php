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
use Filament\Forms\Components\Field;
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
use Illuminate\Support\HtmlString;
use MrExclusive\ScumManager\Support\SettingChoices;
use MrExclusive\ScumManager\Support\SettingDefaults;
use MrExclusive\ScumManager\Support\SettingHelp;
use MrExclusive\ScumManager\Support\SettingLabel;
use MrExclusive\ScumManager\Support\SettingType;
use MrExclusive\ScumManager\Support\Brand;

class ScumSettingsPage extends ServerFormPage
{
    protected static string|\BackedEnum|null $navigationIcon = 'tabler-adjustments-horizontal';

    protected static ?string $slug = 'scum-settings';

    protected static ?int $navigationSort = 30;

    protected static ?string $navigationLabel = 'Server settings';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_SETTINGS;

    /**
     * One entry per setting in the file, keyed by a form-safe id (INI keys contain dots,
     * which Filament would treat as nested state paths).
     *
     * @var array<string, array{section: string, key: string, type: string, value: string, state: mixed, managed: ?string, default: ?string, changed: bool}>
     */
    #[Locked]
    public array $settings = [];

    #[Locked]
    public ?string $fileHash = null;

    #[Locked]
    public bool $fileMissing = false;

    #[Locked]
    public string $serverState = '';

    /** Your settings are set aside while SCUM generates a file with its defaults. */
    #[Locked]
    public bool $capturing = false;

    #[Locked]
    public bool $hasDefaults = false;

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
        $state = ['search' => '', 'changed_only' => false, 'fields' => []];

        $this->capturing = $service->capturingDefaults($server);
        $defaults = $this->capturing ? null : $service->settingDefaults($server);
        $this->hasDefaults = $defaults !== null;
        if ($this->capturing) {
            $this->fileMissing = false;
            $this->fileHash = null;
            $this->form->fill($state);

            return;
        }

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
                    'default' => $default = $defaults[$entry['section']][$entry['key']] ?? null,
                    'changed' => $default !== null && SettingDefaults::differs($entry['value'], $default),
                ];

                $state['fields'][$id] = $this->settings[$id]['state'];
            }
        }

        $this->form->fill($state);
    }

    public function form(Schema $schema): Schema
    {
        if ($this->capturing) {
            return parent::form($schema)->components([
                Section::make('Capturing SCUM\'s defaults')
                    ->icon('tabler-file-search')
                    ->description('Your settings are safe in ' . ScumServerService::SETTINGS_SET_ASIDE_FILE . ' while SCUM writes a fresh file with its own defaults.')
                    ->schema([
                        Text::make(fn () => $this->stateMessage(capture: true))
                            ->color(fn () => $this->isStopped() ? 'success' : 'warning'),
                        Text::make('1. Start the server (button above) and wait until the console says it is online.'),
                        Text::make('2. Stop the server.'),
                        Text::make('3. Click "Finish capture". The defaults are kept and your settings go back in place.'),
                        Text::make('Changed your mind? "Cancel capture" puts your settings back without keeping anything. Your server name and password stay in place throughout.')
                            ->color('gray'),
                    ]),
            ]);
        }

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
                    Text::make('Values follow SCUM\'s own conventions: -1 means SCUM picks the value itself, multipliers use 1 as normal, durations are HH:MM:SS and prices ending in "g" are gold. Keys set by the egg are read-only here; change them on the Startup page.')
                        ->color('gray'),
                    Text::make(fn () => $this->hasDefaults
                        ? 'Each field shows SCUM\'s default for your game version. Settings you changed are marked with a pencil; its arrow button puts the default back (then save).'
                        : 'To see SCUM\'s real default under every field, use "Capture defaults" above once (it needs one server start).')
                        ->color('gray'),
                    Grid::make(['default' => 1, 'md' => 4])
                        ->schema([
                            TextInput::make('search')
                                ->hiddenLabel()
                                ->placeholder('Search settings…')
                                ->prefixIcon('tabler-search')
                                ->live(debounce: 400)
                                ->columnSpan(['default' => 1, 'md' => 3]),
                            Toggle::make('changed_only')
                                ->label('Only changed settings')
                                ->visible(fn () => $this->hasDefaults)
                                ->live(),
                        ]),
                ]),
            Tabs::make('sections')
                ->tabs($tabs)
                ->persistTabInQueryString(),
        ]);
    }

    private function plainField(SettingType $type, string $name, bool $isPassword): Component
    {
        return match ($type) {
            SettingType::Toggle => Toggle::make($name)->inline(false),
            SettingType::Integer => TextInput::make($name)->integer(),
            SettingType::Decimal => TextInput::make($name)->numeric(),
            SettingType::Duration => TextInput::make($name)->placeholder('HH:MM:SS'),
            SettingType::Gold => TextInput::make($name)->placeholder('e.g. 2g'),
            SettingType::Text => $isPassword
                ? TextInput::make($name)->password()->revealable()
                : TextInput::make($name),
        };
    }

    /** @param  array{section: string, key: string, type: string, value: string, state: mixed, managed: ?string, default: ?string, changed: bool}  $setting */
    private function makeField(string $id, array $setting): Component
    {
        $type = SettingType::from($setting['type']);
        $name = "fields.$id";
        $label = SettingLabel::fromKey($setting['key']);
        $isPassword = str_contains(strtolower($setting['key']), 'password');

        $choices = SettingChoices::for($setting['key']);
        if ($choices !== null && !array_key_exists(trim($setting['value']), $choices)) {
            $choices = null; // a value SCUM added later: keep the plain number box
        }

        $field = match (true) {
            $choices !== null => Select::make($name)->options($choices)->selectablePlaceholder(false),
            default => $this->plainField($type, $name, $isPassword),
        };

        $field
            // Fields hidden by the search box still save what was typed in them.
            ->dehydratedWhenHidden()
            ->label($label)
            ->hint($setting['key'])
            ->rules($type->rules())
            ->validationAttribute($label)
            ->hidden(function (Get $get) use ($setting, $label) {
                if ($get('data.changed_only', isAbsolute: true) && !$setting['changed']) {
                    return true;
                }

                $search = strtolower(trim((string) $get('data.search', isAbsolute: true)));

                return $search !== ''
                    && !str_contains(strtolower($setting['key']), $search)
                    && !str_contains(strtolower($label), $search);
            });

        $help = [];
        if ($setting['managed'] !== null) {
            $field->disabled();
            $help[] = 'Set by the egg on every start. Change it on the Startup page.';
        }
        if ($description = SettingHelp::describe($setting['key'], $setting['value'])) {
            $help[] = $description;
        }
        if ($setting['default'] !== null && $setting['managed'] === null) {
            $help[] = SettingDefaults::label($setting['default']);
        } elseif ($setting['default'] === null && in_array(trim($setting['value']), ['-1', '-1.000000'], true) && !str_contains(implode(' ', $help), '-1')) {
            $help[] = '-1 = SCUM decides (its built-in value).';
        }
        if ($help !== []) {
            $field->helperText(new HtmlString(implode('<br>', array_map('e', $help))));
        }

        if ($setting['changed'] && $setting['managed'] === null) {
            $defaultState = $type->toState($setting['default']);
            $field
                ->hintIcon('tabler-pencil', 'Changed from SCUM\'s default')
                ->hintColor('warning')
                ->hintAction(
                    Action::make('reset_' . $id)
                        ->label('Back to default')
                        ->tooltip('Back to the default (' . trim($setting['default']) . '). Save to keep it.')
                        ->icon('tabler-arrow-back-up')
                        ->action(fn (Field $component) => $component->state($defaultState)),
                );
        }

        return $field;
    }

    public function save(bool $andStart = false): void
    {
        $server = $this->getRecord();
        abort_unless(user()?->can(SubuserPermission::FileUpdate, $server), 403);

        if ($this->fileMissing || $this->capturing) {
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

    private function stateMessage(bool $capture = false): string
    {
        $label = ContainerStatus::tryFrom($this->serverState)?->getLabel() ?? 'unknown';
        if ($capture) {
            return $this->isStopped() ? 'The server is stopped.' : "The server is $label. Click Refresh after you stop it.";
        }

        if ($this->isStopped()) {
            return 'The server is stopped, so changes can be saved.';
        }

        return "The server is $label. Stop it before saving: SCUM rewrites this file while it runs.";
    }

    protected function getHeaderActions(): array
    {
        $server = $this->getRecord();

        $canEdit = fn () => user()?->can(SubuserPermission::FileUpdate, $server);

        return [
            Action::make('capture_finish')
                ->label('Finish capture')
                ->icon('tabler-check')
                ->color('success')
                ->visible(fn () => $this->capturing && $canEdit())
                ->disabled(fn () => !$this->isStopped())
                ->action(fn (ScumServerService $service) => $this->runCaptureStep(function () use ($service, $server) {
                    $count = $service->finishDefaultsCapture($server);

                    return "Captured $count defaults. Your settings are back in place.";
                })),
            Action::make('capture_cancel')
                ->label('Cancel capture')
                ->icon('tabler-x')
                ->color('gray')
                ->visible(fn () => $this->capturing && $canEdit())
                ->disabled(fn () => !$this->isStopped())
                ->action(fn (ScumServerService $service) => $this->runCaptureStep(function () use ($service, $server) {
                    $service->cancelDefaultsCapture($server);

                    return 'Your settings are back in place.';
                })),
            Action::make('capture_start')
                ->label('Start server')
                ->icon('tabler-player-play')
                ->color('success')
                ->visible(fn () => $this->capturing && $this->isStopped() && user()?->can(SubuserPermission::ControlStart, $server))
                ->action(fn () => $this->startServer()),
            Action::make('save')
                ->label('Save')
                ->icon('tabler-device-floppy')
                ->visible(fn () => !$this->fileMissing && !$this->capturing && $canEdit())
                ->disabled(fn () => !$this->isStopped())
                ->action(fn () => $this->save()),
            Action::make('save_start')
                ->label('Save & start')
                ->icon('tabler-player-play')
                ->color('success')
                ->visible(fn () => !$this->fileMissing && !$this->capturing && $canEdit() && user()?->can(SubuserPermission::ControlStart, $server))
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
            Action::make('capture_defaults')
                ->label($this->hasDefaults ? 'Re-capture defaults' : 'Capture defaults')
                ->icon('tabler-file-search')
                ->color('gray')
                ->visible(fn () => !$this->fileMissing && !$this->capturing && $canEdit())
                ->disabled(fn () => !$this->isStopped())
                ->requiresConfirmation()
                ->modalHeading('Capture SCUM\'s default settings')
                ->modalDescription('SCUM writes a complete ServerSettings.ini with its own defaults when it starts without one. This sets your file aside (and backs it up) and leaves only your server name, description, password and playstyle in place. You start the server once until it is online and stop it, then Finish keeps what SCUM wrote as the defaults and puts your settings back. While it runs the server uses SCUM\'s default rules, so do it when nobody is playing. Do it again after big SCUM updates.')
                ->modalSubmitActionLabel('Set my settings aside')
                ->action(fn (ScumServerService $service) => $this->runCaptureStep(function () use ($service, $server) {
                    $service->prepareDefaultsCapture($server);

                    return 'Your settings are set aside. Now start the server and wait until it is online.';
                })),
            Action::make('restore_backup')
                ->label('Backups')
                ->icon('tabler-history')
                ->color('gray')
                ->visible(fn () => !$this->capturing && $canEdit())
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

    /** @param  \Closure(): string  $step */
    private function runCaptureStep(\Closure $step): void
    {
        try {
            $message = $step();
            Notification::make()->title($message)->success()->send();
        } catch (Exception $exception) {
            Notification::make()->title('Could not do that')->body($exception->getMessage())->warning()->persistent()->send();
        }

        $this->loadSettings();
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
