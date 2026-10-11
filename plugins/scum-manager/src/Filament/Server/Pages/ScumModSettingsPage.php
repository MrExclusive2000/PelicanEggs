<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\SubuserPermission;
use App\Filament\Server\Pages\ServerFormPage;
use App\Models\Server;
use Exception;
use Filament\Actions\Action;
use Filament\Facades\Filament;
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

class ScumModSettingsPage extends ServerFormPage
{
    protected static string|\BackedEnum|null $navigationIcon = 'tabler-settings-cog';

    protected static ?string $slug = 'scum-mod-settings';

    protected static ?int $navigationSort = 34;

    protected static ?string $navigationLabel = 'SCUM Mod Settings';

    protected static ?string $title = 'SCUM Mod Settings';

    /** @var array<string, string> mod => sha1 of its config.lua when loaded */
    #[Locked]
    public array $hashes = [];

    /** @var array<string, string> mod => why its settings cannot be shown */
    #[Locked]
    public array $problems = [];

    /** @var list<string> our mods that are installed on this server */
    #[Locked]
    public array $installed = [];

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

        $this->form->fill($state);
    }

    public function form(Schema $schema): Schema
    {
        if ($this->installed === []) {
            return parent::form($schema)->components([
                Section::make('No SCUM Manager mods installed')
                    ->description('Install UE4SS and our mods on the SCUM Mods page ("Install our mods"), then come back here.')
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

            foreach ($definition['sections'] as $title => $section) {
                $components[] = Section::make($title)
                    ->description($section['description'])
                    ->collapsible()
                    ->schema([
                        Grid::make(['default' => 1, 'lg' => 2])->schema(array_map(
                            fn (string $path, array $field) => $this->field($mod, $path, $field),
                            array_keys($section['fields']),
                            $section['fields'],
                        )),
                    ]);
            }

            $tabs[] = Tab::make($definition['label'])->schema($components);
        }

        return parent::form($schema)->components([Tabs::make('mods')->tabs($tabs)->persistTabInQueryString()]);
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
                        ->title("$mod's config.lua changed since you opened this page")
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

                $service->writeModConfig($server, $mod, LuaTable::render($updated, "$mod settings, written by SCUM Manager (SCUM Mod Settings page).\nYou can edit this file by hand; comments are not kept when the page saves it."));
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
            Action::make('refresh')
                ->label('Refresh')
                ->icon('tabler-refresh')
                ->color('gray')
                ->action(fn () => $this->loadSettings()),
        ];
    }
}
