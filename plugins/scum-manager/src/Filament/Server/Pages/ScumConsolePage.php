<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\SubuserPermission;
use App\Models\Server;
use App\Traits\Filament\BlockAccessInConflict;
use Exception;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Forms\Components\TextInput;
use Filament\Infolists\Components\TextEntry;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Illuminate\Support\HtmlString;
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Services\ScumServerService;

class ScumConsolePage extends Page
{
    use BlockAccessInConflict;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-terminal-2';

    protected static ?string $slug = 'scum-console';

    protected static ?int $navigationSort = 30;

    protected static ?string $navigationLabel = 'SCUM Admin Console';

    protected static ?string $title = 'SCUM Admin Console';

    #[Locked]
    public bool $modInstalled = false;

    #[Locked]
    public string $output = '';

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return parent::canAccess()
            && user()?->can(SubuserPermission::ControlConsole, $server)
            && user()?->can(SubuserPermission::FileReadContent, $server)
            && app(ScumServerService::class)->isScumServer($server);
    }

    public function mount(): void
    {
        $this->refreshOutput();
    }

    public function refreshOutput(): void
    {
        $service = app(ScumServerService::class);
        $server = $this->getServer();

        $this->modInstalled = $service->consoleModDir($server) !== null;
        $this->output = $this->modInstalled ? $service->consoleOutput($server) : '';
    }

    public function content(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Output')
                ->description(fn () => $this->modInstalled
                    ? 'Runs SCUM admin commands through the PelicanConsole mod. Announce, ListPlayers and Kick <name> work any time; other commands need an admin from AdminUsers.ini online and run as if they typed them in chat. Type commands without the #.'
                    : 'Install the PelicanConsole mod on the SCUM Mods page and restart the server to use this page.')
                ->schema([
                    TextEntry::make('console_output')
                        ->hiddenLabel()
                        ->state(fn () => new HtmlString(
                            '<pre style="white-space: pre-wrap; word-break: break-word; font-family: ui-monospace, monospace; font-size: 0.8rem; max-height: 32rem; overflow-y: auto;">'
                            . e($this->output !== '' ? $this->output : 'No output yet.')
                            . '</pre>'
                        )),
                ]),
        ]);
    }

    protected function getHeaderActions(): array
    {
        return [
            Action::make('send')
                ->label('Send command')
                ->icon('tabler-send')
                ->visible(fn () => $this->modInstalled)
                ->authorize(fn () => user()?->can(SubuserPermission::ControlConsole, $this->getServer())
                    && user()?->can(SubuserPermission::FileUpdate, $this->getServer()))
                ->modalHeading('Send a SCUM admin command')
                ->modalSubmitActionLabel('Send')
                ->schema([
                    TextInput::make('command')
                        ->label('Command')
                        ->placeholder('Announce Hello')
                        ->helperText('Examples: ListPlayers, Announce <message>, Kick <SteamID>, Ban <SteamID>, SetWeather 0, SetTime 12')
                        ->required()
                        ->maxLength(500)
                        ->autofocus(),
                ])
                ->action(function (array $data, ScumServerService $service) {
                    $server = $this->getServer();

                    try {
                        $pickedUp = $service->sendConsoleCommand($server, (string) $data['command']);

                        if ($pickedUp) {
                            Notification::make()->title('Sent to SCUM')->success()->send();
                        } else {
                            Notification::make()
                                ->title('Queued, but SCUM has not picked it up yet')
                                ->body($service->isStopped($server)
                                    ? 'The server is stopped. The command is dropped when it next starts.'
                                    : 'PelicanConsole checks once a second while the server runs. If this keeps happening, check that the mod is enabled and look in ue4ss/UE4SS.log for [PelicanConsole] lines.')
                                ->warning()
                                ->send();
                        }
                    } catch (Exception $exception) {
                        Notification::make()->title('Could not send the command')->body($exception->getMessage())->danger()->send();
                    }

                    // Give the mod a moment to write its result.
                    usleep(1_000_000);
                    $this->refreshOutput();
                }),
            Action::make('refresh')
                ->label('Refresh')
                ->icon('tabler-refresh')
                ->color('gray')
                ->action(fn () => $this->refreshOutput()),
        ];
    }

    private function getServer(): Server
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return $server;
    }
}
