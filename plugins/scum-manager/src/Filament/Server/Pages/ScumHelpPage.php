<?php

namespace MrExclusive\ScumManager\Filament\Server\Pages;

use App\Models\Server;
use Filament\Facades\Filament;
use Filament\Infolists\Components\TextEntry;
use Filament\Pages\Page;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;
use Illuminate\Support\HtmlString;
use MrExclusive\ScumManager\Services\ScumServerService;
use MrExclusive\ScumManager\Support\Brand;
use MrExclusive\ScumManager\Support\Guide;

/**
 * How to set up and use the plugin and our mods, for anyone who can see the SCUM pages. Reads no
 * server files, so it also works while the server is stopped or installing.
 */
class ScumHelpPage extends Page
{
    protected static string|\BackedEnum|null $navigationIcon = 'tabler-help';

    protected static ?string $slug = 'scum-help';

    protected static ?int $navigationSort = 37;

    protected static ?string $navigationLabel = 'Help & guide';

    /** Grouped in the sidebar under the brand (a method, so it fits every Filament version). */
    public static function getNavigationGroup(): ?string
    {
        return Brand::NAV_GROUP;
    }

    protected static ?string $title = Brand::PAGE_HELP;

    public static function canAccess(): bool
    {
        /** @var Server $server */
        $server = Filament::getTenant();

        return parent::canAccess() && app(ScumServerService::class)->isScumServer($server);
    }

    public function content(Schema $schema): Schema
    {
        $components = [
            Section::make('Contents')
                ->icon('tabler-list')
                ->description(Brand::MANAGER . ' ' . ScumServerService::managerVersion())
                ->schema([
                    TextEntry::make('guide_contents')->hiddenLabel()->state(fn () => new HtmlString(Guide::contents())),
                ]),
        ];

        foreach (Guide::topics() as $topic) {
            $components[] = Section::make($topic['title'])
                ->icon($topic['icon'])
                ->description($topic['summary'])
                ->extraAttributes(['id' => 'guide-' . $topic['id'], 'style' => 'scroll-margin-top: 5rem;'])
                ->schema([
                    TextEntry::make('guide_' . $topic['id'])->hiddenLabel()->state(fn () => new HtmlString(Guide::html($topic))),
                ]);
        }

        return $schema->components($components);
    }
}
