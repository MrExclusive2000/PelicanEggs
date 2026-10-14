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
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\Brand;
use MrExclusive\ScumManager\Support\LuaTable;
use MrExclusive\ScumManager\Support\RestartPlan;
use Throwable;

/**
 * Daily restarts in one place: the Pelican schedules that restart the server and ExclsvMessages'
 * countdown warnings, always set together so they cannot drift apart.
 */
class ScumRestartsPage extends Page
{
    use BlockAccessInConflict;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-clock-hour-4';

    protected static ?string $slug = 'scum-restarts';

    protected static ?int $navigationSort = 32;

    protected static ?string $navigationLabel = 'Restarts';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_RESTARTS;

    /** @var array{ours: list<array{id: int, time: ?string, active: bool, next: ?string}>, others: list<array{id: int, name: string, time: ?string}>} */
    #[Locked]
    public array $schedules = ['ours' => [], 'others' => []];

    /** ExclsvMessages' restart settings, or null when the mod is not installed. */
    #[Locked]
    public ?array $warnings = null;

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return !$server->isInConflictState()
            && parent::canAccess()
            && user()?->can(SubuserPermission::ScheduleRead, $server)
            && app(ScumServerService::class)->isScumServer($server);
    }

    public function mount(): void
    {
        $this->load();
    }

    private function load(): void
    {
        $service = app(ScumServerService::class);
        $server = $this->getServer();

        $this->schedules = $service->restartSchedules($server);
        $this->warnings = null;
        if ($service->installedModsOf($server, ['ExclsvMessages']) !== []) {
            try {
                $config = LuaTable::parse($service->modConfig($server, 'ExclsvMessages') ?? 'return {}');
            } catch (Throwable) {
                $config = [];
            }
            $this->warnings = [
                'times' => array_values(array_map('strval', (array) ($config['restartTimes'] ?? []))),
                'minutes' => array_values(array_map('intval', (array) ($config['restartWarnings'] ?? [30, 15, 5, 1]))),
                'message' => (string) ($config['restartMessage'] ?? 'Server restart in {minutes} minute(s).'),
            ];
        }
    }

    /** @return list<string> */
    private function scheduledTimes(): array
    {
        return array_values(array_filter(array_column($this->schedules['ours'], 'time')));
    }

    public function content(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Daily restarts')
                ->icon('tabler-clock-hour-4')
                ->description('Times are UTC, as Pelican runs schedules in UTC. "Set restart times" above changes the schedule and the countdown together.')
                ->columns(['default' => 1, 'md' => 2])
                ->schema([
                    TextEntry::make('restart_times')->label('Restarts (Pelican schedule)')
                        ->state(fn () => $this->schedules['ours'] === []
                            ? 'None set'
                            : implode('   ', array_map(fn (array $s) => ($s['time'] ?? '?') . ' UTC' . ($s['active'] ? '' : ' (paused)'), $this->schedules['ours']))),
                    TextEntry::make('restart_next')->label('Next restart')
                        ->state(fn () => collect($this->schedules['ours'])->where('active', true)->pluck('next')->filter()->sort()->first() ?? '-')
                        ->hint('UTC'),
                    TextEntry::make('restart_warnings')->label('Countdown (' . Brand::mod('ExclsvMessages') . ')')
                        ->state(fn () => $this->warnings === null
                            ? 'Not installed: restarts happen without a countdown'
                            : ($this->warnings['times'] === [] ? 'No restart times set' : implode(', ', $this->warnings['times']) . ' UTC, warning ' . implode(', ', $this->warnings['minutes']) . ' min before')),
                    TextEntry::make('restart_sync')->label('In step')
                        ->state(fn () => $this->syncText())
                        ->color(fn () => $this->warnings === null || RestartPlan::compare($this->scheduledTimes(), $this->warnings['times'])['inSync'] ? 'success' : 'warning'),
                ]),
            Section::make('Other schedules that restart or stop the server')
                ->icon('tabler-alert-triangle')
                ->visible(fn () => $this->schedules['others'] !== [])
                ->description('Made on the Schedules page, not here. If one does the same job as the restarts above, delete it there, or the server restarts twice.')
                ->schema([
                    TextEntry::make('restart_others')->hiddenLabel()
                        ->state(fn () => implode("\n", array_map(fn (array $s) => $s['name'] . ($s['time'] ? " ({$s['time']} UTC)" : ''), $this->schedules['others']))),
                ]),
        ]);
    }

    private function syncText(): string
    {
        if ($this->warnings === null) {
            return 'Only the schedule is used';
        }
        $compare = RestartPlan::compare($this->scheduledTimes(), $this->warnings['times']);
        if ($compare['inSync']) {
            return 'Yes';
        }
        $parts = [];
        if ($compare['noWarning'] !== []) {
            $parts[] = 'no countdown for ' . implode(', ', $compare['noWarning']);
        }
        if ($compare['noRestart'] !== []) {
            $parts[] = 'countdown but no restart at ' . implode(', ', $compare['noRestart']);
        }

        return 'No: ' . implode('; ', $parts) . '. Save the restart times again to fix it.';
    }

    protected function getHeaderActions(): array
    {
        $server = $this->getServer();

        return [
            Action::make('set_restarts')
                ->label('Set restart times')
                ->icon('tabler-clock-edit')
                ->authorize(fn () => user()?->can(SubuserPermission::ScheduleCreate, $server)
                    && user()?->can(SubuserPermission::ScheduleUpdate, $server)
                    && user()?->can(SubuserPermission::FileUpdate, $server))
                ->modalHeading('Daily restart times')
                ->modalDescription('One Pelican schedule per time restarts the server (only while it is running). ' . Brand::mod('ExclsvMessages') . ' counts down to the same times. Leave the times empty to remove all daily restarts.')
                ->schema(fn () => [
                    TextInput::make('times')->label('Restart times (UTC, 24-hour)')
                        ->placeholder('00:00, 12:00')
                        ->helperText('Now: ' . gmdate('H:i') . ' UTC. Separate times with commas.')
                        ->default(implode(', ', $this->scheduledTimes() ?: ($this->warnings['times'] ?? []))),
                    TextInput::make('warnings')->label('Warn this many minutes before')
                        ->default(implode(', ', $this->warnings['minutes'] ?? [30, 15, 5, 1]))
                        ->visible($this->warnings !== null),
                    TextInput::make('message')->label('Warning message ({minutes} = minutes left)')
                        ->default($this->warnings['message'] ?? 'Server restart in {minutes} minute(s).')
                        ->maxLength(200)
                        ->visible($this->warnings !== null),
                ])
                ->action(function (array $data, ScumServerService $service) use ($server) {
                    try {
                        $times = RestartPlan::parseTimes((string) ($data['times'] ?? ''));
                        $warnings = RestartPlan::parseWarnings((string) ($data['warnings'] ?? '30, 15, 5, 1'));
                        $notes = $service->saveRestarts($server, $times, $warnings, (string) ($data['message'] ?? ''));
                        Notification::make()
                            ->title($times === [] ? 'Daily restarts removed' : 'Restarts set: ' . implode(', ', $times) . ' UTC')
                            ->body(implode(' ', $notes) ?: ($this->warnings !== null ? 'The countdown follows within 30 seconds.' : null))
                            ->status($notes === [] ? 'success' : 'warning')
                            ->send();
                    } catch (Exception $exception) {
                        Notification::make()->title('Could not set the restarts')->body($exception->getMessage())->danger()->persistent()->send();
                    }
                    $this->load();
                }),
        ];
    }

    private function getServer(): Server
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return $server;
    }
}
