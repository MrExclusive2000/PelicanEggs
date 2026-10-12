<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\SubuserPermission;
use App\Filament\Server\Pages\ServerFormPage;
use App\Models\Server;
use Exception;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Forms\Components\FileUpload;
use Filament\Forms\Components\Repeater;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Notifications\Notification;
use Filament\Schemas\Components\Component;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Components\Tabs;
use Filament\Schemas\Components\Tabs\Tab;
use Filament\Schemas\Components\Text;
use Filament\Schemas\Schema;
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\ItemSelect;
use MrExclusive\ScumManager\Support\LuaTable;
use MrExclusive\ScumManager\Support\ModSettings;
use MrExclusive\ScumManager\Support\Brand;
use MrExclusive\ScumManager\Support\SettingsBundle;
use Illuminate\Support\Str;
use InvalidArgumentException;
use Livewire\Features\SupportFileUploads\TemporaryUploadedFile;
use Symfony\Component\HttpFoundation\StreamedResponse;

class ScumModSettingsPage extends ServerFormPage
{
    protected static string|\BackedEnum|null $navigationIcon = 'tabler-settings-cog';

    protected static ?string $slug = 'scum-mod-settings';

    protected static ?int $navigationSort = 34;

    protected static ?string $navigationLabel = 'Mod settings';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_MOD_SETTINGS;

    /** @var array<string, string> mod => sha1 of its config.lua when loaded */
    #[Locked]
    public array $hashes = [];

    /** @var array<string, string> mod => why its settings cannot be shown */
    #[Locked]
    public array $problems = [];

    /** @var list<string> our mods that are installed on this server */
    #[Locked]
    public array $installed = [];

    /** @var list<string> fields of section switches that were off when loaded (those sections start collapsed) */
    #[Locked]
    public array $switchedOff = [];

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

        $this->installed = $service->installedModsOf($server, array_keys(ModSettings::MODS));
        $this->hashes = [];
        $this->problems = [];
        $state = [];

        foreach ($this->installed as $mod) {
            $raw = $service->modConfig($server, $mod);
            $this->hashes[$mod] = sha1($raw ?? '');

            try {
                $config = $raw === null ? [] : LuaTable::parse($raw);
            } catch (Exception $exception) {
                $this->problems[$mod] = $exception->getMessage();
                $config = [];
            }

            $state += ModSettings::toState($mod, $config);
        }

        $this->switchedOff = array_keys(array_filter($state, fn ($value) => $value === false));
        $this->form->fill($state);
    }

    public function form(Schema $schema): Schema
    {
        if ($this->installed === []) {
            return parent::form($schema)->components([
                Section::make('No ' . Brand::MANAGER . ' mods installed')
                    ->description('Install UE4SS and our mods on the ExclsvSCUM Mods page ("Install our mods"), then come back here.')
                    ->icon('tabler-puzzle'),
            ]);
        }

        $tabs = [];
        foreach ($this->installed as $mod) {
            $definition = ModSettings::MODS[$mod];
            $components = [Text::make($definition['description'] . ' Changes apply within 30 seconds; no restart needed.')->color('gray')];

            if (isset($this->problems[$mod])) {
                $components[] = Text::make('Could not read config.lua (' . $this->problems[$mod] . '). Saving writes a fresh config.lua from the values below.')->color('danger');
            }

            // Themed sub-tabs; a switched-off section starts collapsed.
            // Sections are built first and only wrapped in tabs when there is more than one
            // group (reading components back out of an unattached Tab fails in Filament).
            $grouped = [];
            foreach (ModSettings::groups($mod) as $group => $titles) {
                $grouped[$group] = array_map(
                    fn (string $title) => $this->section($mod, $title, $definition['sections'][$title]),
                    $titles,
                );
            }
            if (count($grouped) === 1) {
                array_push($components, ...array_values($grouped)[0]);
            } else {
                $subTabs = [];
                foreach ($grouped as $group => $sections) {
                    $subTabs[] = Tab::make($group)->schema($sections);
                }
                $components[] = Tabs::make($mod . '_groups')->tabs($subTabs)->contained(false);
            }

            $tabs[] = Tab::make($definition['label'])->schema($components);
        }

        return parent::form($schema)->components([Tabs::make('mods')->tabs($tabs)->persistTabInQueryString()]);
    }

    /** @param array<mixed> $section */
    private function section(string $mod, string $title, array $section): Section
    {
        $switch = ModSettings::sectionSwitch($section);
        $switchId = $switch === null ? null : ModSettings::fieldId($mod, $switch);
        $experimental = str_contains(strtolower($title), 'experimental');

        return Section::make($title)
            ->description(($experimental ? 'Experimental: try it on yourself first. ' : '') . $section['description'])
            ->icon($experimental ? 'tabler-flask' : null)
            ->collapsible()
            ->collapsed($switchId !== null && in_array($switchId, $this->switchedOff, true))
            ->schema([
                Grid::make(['default' => 1, 'lg' => 2])->schema(array_map(
                    fn (string $path, array $field) => $this->field($mod, $path, $field),
                    array_keys($section['fields']),
                    $section['fields'],
                )),
            ]);
    }

    /** @param array<mixed> $field */
    private function field(string $mod, string $path, array $field): Component
    {
        $id = ModSettings::fieldId($mod, $path);
        [$type, $label] = $field;

        return match ($type) {
            'toggle' => Toggle::make($id)->label($label),
            'int' => TextInput::make($id)->label($label)->numeric()->minValue(0)->required(),
            'text' => TextInput::make($id)->label($label)->maxLength(500),
            'select' => Select::make($id)->label($label)->options($field['options'])->selectablePlaceholder(false)->required(),
            'lines' => Textarea::make($id)->label($label)->rows(3)->autosize(),
            'ints' => TextInput::make($id)->label($label)->regex('/^\s*\d+(\s*,\s*\d+)*\s*$/'),
            'rows' => Repeater::make($id)
                ->label($label)
                ->columnSpanFull()
                ->defaultItems(0)
                ->reorderable()
                ->columns(count($field['columns']))
                ->schema(array_map(
                    fn ($key, string $column, int $index) => ($field['itemColumn'] ?? null) === $key
                        ? ItemSelect::make($key, $column, fn () => app(ScumServerService::class)->itemCatalog($this->getRecord()))->required()
                        : TextInput::make(($field['tuple'] ?? false) ? 'c' . $index : $key)->label($column)->required(),
                    array_keys($field['columns']),
                    array_values($field['columns']),
                    array_keys(array_values($field['columns'])),
                )),
        };
    }

    public function save(): void
    {
        $server = $this->getRecord();
        abort_unless(user()?->can(SubuserPermission::FileUpdate, $server), 403);

        $service = app(ScumServerService::class);
        $state = $this->form->getState();
        $saved = [];

        try {
            foreach ($this->installed as $mod) {
                $raw = $service->modConfig($server, $mod);

                if (sha1($raw ?? '') !== ($this->hashes[$mod] ?? '')) {
                    Notification::make()
                        ->title(Brand::mod($mod) . "'s config.lua changed since you opened this page")
                        ->body('Reload the page and make your changes again. Nothing was saved for this mod.')
                        ->warning()
                        ->persistent()
                        ->send();

                    continue;
                }

                try {
                    $config = $raw === null ? [] : LuaTable::parse($raw);
                } catch (Exception) {
                    $config = [];
                }

                $updated = ModSettings::apply($mod, $config, $state);
                if ($updated === $config && $raw !== null) {
                    continue;
                }

                $service->writeModConfig($server, $mod, LuaTable::render($updated, Brand::mod($mod) . " settings, written by " . Brand::MANAGER . " (" . Brand::PAGE_MOD_SETTINGS . " page).\nYou can edit this file by hand; comments are not kept when the page saves it."));
                $saved[] = ModSettings::MODS[$mod]['label'];
            }

            Notification::make()
                ->title($saved === [] ? 'No changes to save' : 'Saved: ' . implode(', ', $saved))
                ->body($saved === [] ? null : 'The mods pick up the change within 30 seconds.')
                ->success()
                ->send();

            $this->loadSettings();
        } catch (Exception $exception) {
            report($exception);

            Notification::make()->title('Could not save the mod settings')->body($exception->getMessage())->danger()->send();
        }
    }

    protected function getHeaderActions(): array
    {
        $server = $this->getRecord();

        return [
            Action::make('save')
                ->label('Save')
                ->icon('tabler-device-floppy')
                ->visible(fn () => $this->installed !== [] && user()?->can(SubuserPermission::FileUpdate, $server))
                ->action(fn () => $this->save()),
            Action::make('export')
                ->label('Export settings')
                ->icon('tabler-download')
                ->color('gray')
                ->modalHeading('Export all settings')
                ->modalDescription('Downloads one file with the settings of every installed Exclsv mod, to keep as a backup or to edit and import again.')
                ->modalSubmitActionLabel('Download')
                ->schema([
                    Toggle::make('includeServer')->label('Include ServerSettings.ini')->default(true),
                ])
                ->action(fn (array $data) => $this->exportSettings((bool) ($data['includeServer'] ?? false))),
            Action::make('import')
                ->label('Import settings')
                ->icon('tabler-upload')
                ->color('gray')
                ->visible(fn () => user()?->can(SubuserPermission::FileUpdate, $server))
                ->modalHeading('Import settings')
                ->modalDescription('Upload a settings file made with "Export settings" (edited or not). Each mod in it replaces that mod\'s settings; the previous config.lua is kept as config.before-import-<date>.lua in the mod\'s folder. Mods not in the file are left alone.')
                ->modalSubmitActionLabel('Import')
                ->schema([
                    FileUpload::make('file')
                        ->label('Settings file (.json)')
                        ->required()
                        ->acceptedFileTypes(['application/json', 'text/plain', 'text/json'])
                        ->maxSize((int) (SettingsBundle::MAX_BYTES / 1024))
                        ->previewable(false)
                        ->storeFiles(false),
                    Toggle::make('includeServer')
                        ->label('Also import ServerSettings.ini if the file has it (only while the server is stopped)')
                        ->default(false),
                ])
                ->action(function (array $data) {
                    /** @var TemporaryUploadedFile $file */
                    $file = $data['file'];
                    try {
                        $this->importSettings((string) file_get_contents($file->getRealPath()), (bool) ($data['includeServer'] ?? false));
                    } finally {
                        $file->delete();
                    }
                }),
            Action::make('refresh')
                ->label('Refresh')
                ->icon('tabler-refresh')
                ->color('gray')
                ->action(fn () => $this->loadSettings()),
        ];
    }

    public function exportSettings(bool $includeServer): ?StreamedResponse
    {
        $server = $this->getRecord();
        $service = app(ScumServerService::class);
        $configs = [];
        $skipped = [];

        foreach ($service->installedModsOf($server, array_keys(ModSettings::MODS)) as $mod) {
            $raw = $service->modConfig($server, $mod);
            try {
                $configs[$mod] = $raw === null ? [] : LuaTable::parse($raw);
            } catch (Exception) {
                $skipped[] = Brand::mod($mod);
            }
        }

        $ini = $includeServer ? $service->read($server, $service->configPath(ScumServerService::SETTINGS_FILE)) : null;
        if ($configs === [] && $ini === null) {
            Notification::make()->title('Nothing to export')->body('No Exclsv mods are installed and ServerSettings.ini was not included or not found.')->warning()->send();

            return null;
        }
        if ($skipped !== []) {
            Notification::make()->title('Left out: ' . implode(', ', $skipped))->body('Their config.lua could not be read.')->warning()->send();
        }

        $json = SettingsBundle::make($configs, $ini, $server->name, now()->toIso8601String());
        $filename = 'exclsv-settings-' . (Str::slug($server->name) ?: 'server') . '-' . now()->format('Y-m-d') . '.json';

        return response()->streamDownload(fn () => print($json), $filename, ['Content-Type' => 'application/json']);
    }

    public function importSettings(string $json, bool $includeServer): void
    {
        $server = $this->getRecord();
        abort_unless(user()?->can(SubuserPermission::FileUpdate, $server), 403);
        $service = app(ScumServerService::class);

        try {
            $bundle = SettingsBundle::parse($json);
        } catch (InvalidArgumentException $exception) {
            Notification::make()->title('Could not import that file')->body($exception->getMessage())->danger()->persistent()->send();

            return;
        }

        $installed = $service->installedModsOf($server, array_keys(ModSettings::MODS));
        $done = [];
        $notes = [];

        try {
            foreach ($bundle['mods'] as $mod => $config) {
                if (!in_array($mod, $installed, true)) {
                    $notes[] = Brand::mod($mod) . ' is not installed, skipped.';

                    continue;
                }
                $raw = $service->modConfig($server, $mod);
                if ($raw !== null) {
                    $service->backupModConfig($server, $mod, $raw);
                }
                $service->writeModConfig($server, $mod, LuaTable::render($config, Brand::mod($mod) . ' settings, imported by ' . Brand::MANAGER . ' on ' . now()->toDateTimeString() . ".\nYou can edit this file by hand; comments are not kept when the page saves it."));
                $done[] = Brand::mod($mod);
            }

            if ($bundle['serverSettings'] !== null) {
                if (!$includeServer) {
                    $notes[] = 'ServerSettings.ini in the file was not imported (option off).';
                } elseif (!$service->isStopped($server)) {
                    $notes[] = 'ServerSettings.ini was not imported: stop the server first (SCUM rewrites it while running), then import again.';
                } else {
                    $path = $service->configPath(ScumServerService::SETTINGS_FILE);
                    $current = $service->read($server, $path);
                    $backup = $current !== null ? $service->backup($server, ScumServerService::SETTINGS_FILE, $current) : null;
                    $service->write($server, $path, $bundle['serverSettings']);
                    $done[] = 'ServerSettings.ini' . ($backup ? " (previous kept as $backup)" : '');
                }
            }
        } catch (Exception $exception) {
            report($exception);
            Notification::make()->title('Import stopped part way')->body(($done ? 'Imported: ' . implode(', ', $done) . '. ' : '') . $exception->getMessage())->danger()->persistent()->send();
            $this->loadSettings();

            return;
        }

        Notification::make()
            ->title($done === [] ? 'Nothing was imported' : 'Imported: ' . implode(', ', $done))
            ->body(implode(' ', array_merge($done === [] ? [] : ['Mods pick up their settings within 30 seconds.'], $notes)) ?: null)
            ->status($done === [] ? 'warning' : 'success')
            ->persistent()
            ->send();

        $this->loadSettings();
    }
}
