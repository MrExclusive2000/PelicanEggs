<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Enums\SubuserPermission;
use App\Models\Server;
use App\Traits\Filament\BlockAccessInConflict;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Infolists\Components\TextEntry;
use Filament\Pages\Page;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Illuminate\Support\HtmlString;
use Livewire\Attributes\Locked;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\Brand;
use MrExclusive\ScumManager\Support\EconomyReport;
use MrExclusive\ScumManager\Support\LuaTable;
use MrExclusive\ScumManager\Support\OnlinePlayers;
use Throwable;

/**
 * Where the money goes: what ExclsvPlayerTools paid out and took in (economy.log), the lottery,
 * and the bank money players hold (from the save).
 */
class ScumEconomyPage extends Page
{
    use BlockAccessInConflict;

    protected static string|\BackedEnum|null $navigationIcon = 'tabler-coin';

    protected static ?string $slug = 'scum-economy';

    protected static ?int $navigationSort = 35;

    protected static ?string $navigationLabel = 'Economy';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_ECONOMY;

    private const RANGES = ['24h' => ['24 hours', 86400], '7d' => ['7 days', 7 * 86400], '30d' => ['30 days', 30 * 86400], 'all' => ['All', null]];

    public string $range = '7d';

    #[Locked]
    public string $log = '';

    #[Locked]
    public string $lotteryTsv = '';

    /** @var array{ticketPrice: int, housePercent: int, enabled: bool} */
    #[Locked]
    public array $lotterySettings = ['ticketPrice' => 0, 'housePercent' => 0, 'enabled' => false];

    /** @var array<string, array{name: string, cash: ?int, gold: ?int}> */
    #[Locked]
    public array $savePlayers = [];

    #[Locked]
    public ?int $saveReadAt = null;

    #[Locked]
    public bool $installed = false;

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return !$server->isInConflictState()
            && parent::canAccess()
            && user()?->can(SubuserPermission::FileReadContent, $server)
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
        $mods = $service->ue4ss($server)['mods'];

        $this->installed = $service->installedModsOf($server, ['ExclsvPlayerTools']) !== [];
        if ($this->installed) {
            $this->log = ($service->read($server, "$mods/ExclsvPlayerTools/economy.old.log") ?? '')
                . ($service->read($server, "$mods/ExclsvPlayerTools/economy.log") ?? '');
            $this->lotteryTsv = $service->read($server, "$mods/ExclsvPlayerTools/lottery.tsv") ?? '';
            try {
                $lottery = (array) (LuaTable::parse($service->modConfig($server, 'ExclsvPlayerTools') ?? 'return {}')['lottery'] ?? []);
            } catch (Throwable) {
                $lottery = [];
            }
            $this->lotterySettings = [
                'ticketPrice' => (int) ($lottery['ticketPrice'] ?? 100),
                'housePercent' => (int) ($lottery['housePercent'] ?? 10),
                'enabled' => (bool) ($lottery['enabled'] ?? false),
            ];
        }

        $save = $service->saveData($server);
        $this->savePlayers = array_map(fn (array $p) => ['name' => $p['name'], 'cash' => $p['cash'], 'gold' => $p['gold']], $save['players'] ?? []);
        $this->saveReadAt = $save['readAt'] ?? null;
    }

    private function entries(): array
    {
        $seconds = self::RANGES[$this->range][1] ?? self::RANGES['7d'][1];

        return EconomyReport::parse($this->log, $seconds === null ? 0 : time() - $seconds);
    }

    public function content(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Summary')
                ->icon('tabler-coin')
                ->description(fn () => $this->installed
                    ? 'Money moved by ' . Brand::mod('ExclsvPlayerTools') . ' (rewards, shop, sales, payments, lottery, events) in the last ' . strtolower(self::RANGES[$this->range][0] ?? '7 days') . '. Money players earn or spend in SCUM itself (traders, quests) is not in here.'
                    : Brand::mod('ExclsvPlayerTools') . ' is not installed: only the bank money from the save is shown.')
                ->headerActions(array_map(
                    fn (string $key) => Action::make('range_' . $key)->label(self::RANGES[$key][0])->size('sm')
                        ->color(fn () => $this->range === $key ? 'primary' : 'gray')
                        ->action(fn () => $this->range = $key),
                    array_keys(self::RANGES),
                ))
                ->columns(['default' => 1, 'md' => 3])
                ->schema([
                    TextEntry::make('paid_out')->label('Paid to players')
                        ->state(fn () => number_format(EconomyReport::totals($this->entries())['paidOut'])),
                    TextEntry::make('taken_in')->label('Taken from players')
                        ->state(fn () => number_format(EconomyReport::totals($this->entries())['takenIn'])),
                    TextEntry::make('net')->label('Money added to the economy')
                        ->state(fn () => $this->signed(EconomyReport::totals($this->entries())['net']))
                        ->helperText('Paid out minus taken in. Steadily high means prices or rewards are generous.'),
                    TextEntry::make('lottery')->label('Lottery')
                        ->state(fn () => $this->lotteryText()),
                    TextEntry::make('bank_total')->label('Bank money held by players')
                        ->state(fn () => $this->bankText()),
                    TextEntry::make('bank_average')->label('Average per player')
                        ->state(fn () => ($c = EconomyReport::circulation($this->savePlayers))['players'] > 0 ? number_format(intdiv($c['cash'], $c['players'])) : '-'),
                ]),
            Section::make('Where it came from and went')
                ->icon('tabler-list-details')
                ->schema([TextEntry::make('categories')->hiddenLabel()->state(fn () => new HtmlString($this->categoryTable()))]),
            Grid::make(['default' => 1, 'lg' => 3])->schema([
                Section::make('Top earners')
                    ->description('Received the most from the mod')
                    ->schema([TextEntry::make('earners')->hiddenLabel()->state(fn () => new HtmlString($this->playerTable(EconomyReport::players($this->entries())['earners'], 'amount')))]),
                Section::make('Top spenders')
                    ->description('Spent the most through the mod')
                    ->schema([TextEntry::make('spenders')->hiddenLabel()->state(fn () => new HtmlString($this->playerTable(EconomyReport::players($this->entries())['spenders'], 'amount')))]),
                Section::make('Richest players')
                    ->description('Bank cash, from the save')
                    ->schema([TextEntry::make('richest')->hiddenLabel()->state(fn () => new HtmlString($this->playerTable(EconomyReport::circulation($this->savePlayers)['richest'], 'cash')))]),
            ]),
            Section::make('Latest money movements')
                ->icon('tabler-history')
                ->collapsible()
                ->schema([TextEntry::make('latest')->hiddenLabel()->state(fn () => new HtmlString($this->latestTable()))]),
        ]);
    }

    private function signed(int $value): string
    {
        return ($value > 0 ? '+' : '') . number_format($value);
    }

    private function lotteryText(): string
    {
        if (!$this->lotterySettings['enabled']) {
            return 'Off';
        }
        $lottery = EconomyReport::lottery($this->lotteryTsv);
        $pot = $lottery['tickets'] * $this->lotterySettings['ticketPrice'];
        $prize = intdiv($pot * (100 - $this->lotterySettings['housePercent']), 100);
        $next = $lottery['draw'] !== null ? ' Draw in ' . OnlinePlayers::duration(max(0, $lottery['draw'] - time())) . '.' : '';

        return sprintf('%d ticket(s) from %d player(s): pot %s, prize %s.%s', $lottery['tickets'], $lottery['players'], number_format($pot), number_format($prize), $next);
    }

    private function bankText(): string
    {
        $circulation = EconomyReport::circulation($this->savePlayers);
        if ($circulation['players'] === 0) {
            return 'Not read yet (the save is read every few minutes)';
        }
        $age = $this->saveReadAt !== null ? ' (save read ' . OnlinePlayers::duration(max(0, time() - $this->saveReadAt)) . ' ago)' : '';

        return number_format($circulation['cash']) . ' cash, ' . number_format($circulation['gold']) . ' gold, ' . $circulation['players'] . ' players' . $age;
    }

    private function categoryTable(): string
    {
        $totals = EconomyReport::totals($this->entries());
        if ($totals['categories'] === []) {
            return $this->empty();
        }
        $rows = '';
        foreach ($totals['categories'] as $category => $total) {
            $rows .= '<tr>' . $this->cell(EconomyReport::label($category)) . $this->cell(number_format($total['count']), true)
                . $this->cell($this->signed($total['total']), true, $total['total'] >= 0 ? '#16a34a' : '#dc2626') . '</tr>';
        }

        return $this->table(['What', 'Times', 'Money to players (+) / from players (-)'], $rows);
    }

    /** @param list<array{name: string, steamId: string}> $players */
    private function playerTable(array $players, string $column): string
    {
        if ($players === []) {
            return $this->empty();
        }
        $rows = '';
        foreach ($players as $index => $player) {
            $rows .= '<tr>' . $this->cell(($index + 1) . '. ' . $player['name']) . $this->cell(number_format((int) $player[$column]), true) . '</tr>';
        }

        return $this->table(['Player', 'Amount'], $rows);
    }

    private function latestTable(): string
    {
        $entries = array_slice(array_reverse($this->entries()), 0, 50);
        if ($entries === []) {
            return $this->empty();
        }
        $rows = '';
        foreach ($entries as $entry) {
            $rows .= '<tr>' . $this->cell(gmdate('Y-m-d H:i', $entry['time'])) . $this->cell($entry['name']) . $this->cell($entry['what'])
                . $this->cell($this->signed($entry['amount']), true, $entry['amount'] >= 0 ? '#16a34a' : '#dc2626') . '</tr>';
        }

        return $this->table(['When (UTC)', 'Player', 'What for', 'Amount'], $rows);
    }

    private function empty(): string
    {
        return '<p style="opacity: .7; font-size: .875rem;">' . e($this->installed ? 'Nothing in this period yet. ' . Brand::mod('ExclsvPlayerTools') . ' logs money from 1.37.0 on.' : 'Nothing to show.') . '</p>';
    }

    /** @param list<string> $headers */
    private function table(array $headers, string $rows): string
    {
        $head = implode('', array_map(fn (string $h, int $i) => '<th style="text-align: ' . ($i > 0 && $i === count($headers) - 1 ? 'right' : 'left') . '; padding: .25rem .5rem; font-weight: 600; opacity: .8;">' . e($h) . '</th>', $headers, array_keys($headers)));

        return '<div style="overflow-x: auto;"><table style="width: 100%; border-collapse: collapse; font-size: .875rem;"><thead><tr>' . $head . '</tr></thead><tbody>' . $rows . '</tbody></table></div>';
    }

    private function cell(string $text, bool $right = false, ?string $color = null): string
    {
        return '<td style="padding: .25rem .5rem; border-top: 1px solid rgba(127,127,127,.2);' . ($right ? ' text-align: right; font-variant-numeric: tabular-nums;' : '') . ($color ? " color: $color;" : '') . '">' . e($text) . '</td>';
    }

    protected function getHeaderActions(): array
    {
        return [
            Action::make('refresh')->label('Refresh')->icon('tabler-refresh')->color('gray')
                ->action(fn () => $this->load()),
        ];
    }

    private function getServer(): Server
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return $server;
    }
}
