<?php

namespace MrExclusive\ScumManager\Support;

use Closure;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;

/**
 * A searchable dropdown of the server's items (from PelicanConsole's items.txt). The list is
 * searched on the server, so thousands of items are not sent to the browser. Before the list
 * exists (the mod writes it a minute after the server is online) it is a plain text field.
 */
final class ItemSelect
{
    /** @param Closure(): array<string, string> $catalog */
    public static function make(string $name, string $label, Closure $catalog): Select|TextInput
    {
        if ($catalog() === []) {
            return TextInput::make($name)
                ->label($label)
                ->placeholder('BP_Water_05l_C')
                ->helperText('The item list appears here a minute after the server is online with PelicanConsole.');
        }

        return Select::make($name)
            ->label($label)
            ->searchable()
            ->getSearchResultsUsing(fn (string $search) => self::search($catalog(), $search))
            ->getOptionLabelUsing(fn ($value) => $catalog()[$value] ?? (string) $value)
            ->placeholder('Type to search, e.g. water');
    }

    /**
     * @param  array<string, string>  $catalog
     * @return array<string, string> the first 50 items whose name contains every typed word
     */
    public static function search(array $catalog, string $search): array
    {
        $words = array_filter(preg_split('/\s+/', strtolower(trim($search))) ?: []);
        $results = [];
        foreach ($catalog as $value => $label) {
            $haystack = strtolower($label);
            foreach ($words as $word) {
                if (!str_contains($haystack, $word)) {
                    continue 2;
                }
            }
            $results[$value] = $label;
            if (count($results) >= 50) {
                break;
            }
        }

        return $results;
    }
}
