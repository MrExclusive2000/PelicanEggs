<?php

namespace MrExclusive\ScumManager\Support;

/**
 * Names shown to people. The plugin id, namespaces and the mods' folder names stay as they are
 * (renaming those would make Pelican and UE4SS treat them as new installs); only what is
 * displayed carries the Exclsv brand.
 */
final class Brand
{
    public const MANAGER = 'ExclsvSCUM Manager';

    /** Sidebar group that holds all of our pages. */
    public const NAV_GROUP = 'ExclsvSCUM';

    public const PAGE_OVERVIEW = 'ExclsvSCUM Overview';

    public const PAGE_CONSOLE = 'ExclsvSCUM Console';

    public const PAGE_SETTINGS = 'ExclsvSCUM Settings';

    public const PAGE_MODS = 'ExclsvSCUM Mods';

    public const PAGE_MOD_SETTINGS = 'ExclsvSCUM Mod Settings';

    public const PAGE_PLAYERS = 'ExclsvSCUM Players';

    /** Mod folder => display name. */
    public const MODS = [
        'PlayerTools' => 'ExclsvPlayerTools',
        'ScumAntiCheat' => 'ExclsvAntiCheat',
        'ServerMessages' => 'ExclsvMessages',
        'PelicanConsole' => 'ExclsvConsole',
        'ScumCommandProbe' => 'ExclsvProbe',
    ];

    /** Display name for a mod folder; mods that are not ours keep their own name. */
    public static function mod(string $folder): string
    {
        return self::MODS[$folder] ?? $folder;
    }
}
