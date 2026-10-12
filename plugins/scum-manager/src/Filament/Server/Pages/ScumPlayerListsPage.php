<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\SubuserPermission;
use App\Filament\Server\Pages\ServerFormPage;
use App\Models\Server;
use Closure;
use Exception;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Forms\Components\Textarea;
use Filament\Notifications\Notification;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Components\Text;
use Filament\Schemas\Schema;
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\Brand;

class ScumPlayerListsPage extends ServerFormPage
{
    protected static string|\BackedEnum|null $navigationIcon = 'tabler-users-group';

    protected static ?string $slug = 'scum-player-lists';

    protected static ?int $navigationSort = 32;

    protected static ?string $navigationLabel = Brand::PAGE_PLAYERS;

    protected static ?string $title = Brand::PAGE_PLAYERS;

    /** File => [label, description, requires SteamID64 at the start of each line] */
    private const LISTS = [
        'AdminUsers.ini' => ['Admins', 'Players who can use in-game admin (#) commands. Permission suffixes in [brackets] after the ID are kept.', true],
        'ServerSettingsAdminUsers.ini' => ['Settings admins', 'Players who can change server settings from the in-game settings menu.', true],
        'WhitelistedUsers.ini' => ['Whitelist / priority slots', 'Players who get a reserved slot when the server is full.', false],
        'ExclusiveUsers.ini' => ['Exclusive users', 'When this list has entries, only these players can join.', false],
        'BannedUsers.ini' => ['Banned', 'Players who cannot join. Bans issued in-game are added here automatically.', false],
        'SilencedUsers.ini' => ['Silenced', 'Players who cannot use chat.', false],
    ];

    /** @var array<string, string> file => hash of its contents when loaded ('' when missing) */
    #[Locked]
    public array $hashes = [];

    /** @var array<string, string> file => detected line ending */
    #[Locked]
    public array $lineEndings = [];

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
        $this->loadLists();
    }

    public function loadLists(): void
    {
        $service = app(ScumServerService::class);
        $server = $this->getRecord();

        $this->serverState = $service->powerState($server)->value;
        $state = [];

        foreach (array_keys(self::LISTS) as $file) {
            $raw = $service->read($server, $service->configPath($file)) ?? '';
            $this->hashes[$file] = sha1($raw);
            $this->lineEndings[$file] = str_contains($raw, "\n") && !str_contains($raw, "\r\n") ? "\n" : "\r\n";
            $state[$this->field($file)] = rtrim(str_replace("\r\n", "\n", $raw));
        }

        $this->form->fill($state);
    }

    public function form(Schema $schema): Schema
    {
        $components = [
            Text::make(fn () => $this->isStopped()
                ? 'One SteamID64 per line (17 digits, starting with 7656). The server is stopped, so changes can be saved.'
                : 'One SteamID64 per line (17 digits, starting with 7656). Stop the server before saving: SCUM updates these files while it runs.')
                ->color(fn () => $this->isStopped() ? 'gray' : 'warning'),
        ];

        foreach (self::LISTS as $file => [$label, $description, $strict]) {
            $components[] = Section::make($label)
                ->description($description)
                ->collapsible()
                ->schema([
                    Textarea::make($this->field($file))
                        ->hiddenLabel()
                        ->hint($file)
                        ->rows(5)
                        ->autosize()
                        ->placeholder('76561198000000000')
                        ->rules([fn () => $this->steamIdRule($strict)]),
                ]);
        }

        return parent::form($schema)->components($components);
    }

    public function save(): void
    {
        $server = $this->getRecord();
        abort_unless(user()?->can(SubuserPermission::FileUpdate, $server), 403);

        $service = app(ScumServerService::class);
        $data = $this->form->getState();

        if (!$service->isStopped($server)) {
            Notification::make()->title('Stop the server first')->warning()->send();

            return;
        }

        try {
            $saved = [];

            foreach (array_keys(self::LISTS) as $file) {
                $path = $service->configPath($file);
                $current = $service->read($server, $path) ?? '';
                $lines = array_values(array_filter(array_map('trim', explode("\n", str_replace("\r\n", "\n", (string) ($data[$this->field($file)] ?? '')))), fn ($line) => $line !== ''));
                $eol = $this->lineEndings[$file] ?? "\r\n";
                $new = $lines === [] ? '' : implode($eol, $lines) . $eol;

                if (rtrim(str_replace("\r\n", "\n", $current)) === rtrim(str_replace("\r\n", "\n", $new))) {
                    continue;
                }

                if (sha1($current) !== ($this->hashes[$file] ?? '')) {
                    Notification::make()
                        ->title("$file changed since you opened this page")
                        ->body('Reload the page and make your changes again. Nothing was saved for this file.')
                        ->warning()
                        ->persistent()
                        ->send();

                    continue;
                }

                $service->write($server, $path, $new);
                $saved[] = $file;
            }

            Notification::make()
                ->title($saved === [] ? 'No changes to save' : 'Saved ' . implode(', ', $saved))
                ->success()
                ->send();

            $this->loadLists();
        } catch (Exception $exception) {
            report($exception);

            Notification::make()->title('Could not save the player lists')->body($exception->getMessage())->danger()->send();
        }
    }

    protected function getHeaderActions(): array
    {
        $server = $this->getRecord();

        return [
            Action::make('save')
                ->label('Save')
                ->icon('tabler-device-floppy')
                ->visible(fn () => user()?->can(SubuserPermission::FileUpdate, $server))
                ->disabled(fn () => !$this->isStopped())
                ->action(fn () => $this->save()),
            Action::make('refresh')
                ->label('Refresh')
                ->icon('tabler-refresh')
                ->color('gray')
                ->action(fn () => $this->loadLists()),
        ];
    }

    private function steamIdRule(bool $strict): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail) use ($strict) {
            foreach (explode("\n", str_replace("\r\n", "\n", (string) $value)) as $number => $line) {
                $line = trim($line);
                if ($line === '' || str_starts_with($line, ';') || str_starts_with($line, '#')) {
                    continue;
                }

                $pattern = $strict ? '/^7656\d{13}(\[[A-Za-z0-9_,\s]+\])*$/' : '/^7656\d{13}\b/';
                if (!preg_match($pattern, $line)) {
                    $fail('Line ' . ($number + 1) . " is not a valid SteamID64 entry: \"$line\"");

                    return;
                }
            }
        };
    }

    private function field(string $file): string
    {
        return 'list_' . strtolower(str_replace('.', '_', $file));
    }

    private function isStopped(): bool
    {
        return ScumServerService::isStoppedState($this->serverState);
    }
}
