<?php

namespace MrExclusive\ScumManager\Support;

/**
 * Names shown to people, and our mods' folder names. The plugin id and namespaces stay as they
 * are (renaming those would make Pelican treat the plugin as a new install).
 */
final class Brand
{
    public const MANAGER = 'ExclsvSCUM Manager';

    /** Sidebar group that holds all of our pages. */
    public const NAV_GROUP = 'ExclsvSCUM';

    public const PAGE_OVERVIEW = 'ExclsvSCUM Overview';

    public const PAGE_WORLD = 'ExclsvSCUM World';

    public const PAGE_CONSOLE = 'ExclsvSCUM Console';

    public const PAGE_SETTINGS = 'ExclsvSCUM Settings';

    public const PAGE_MODS = 'ExclsvSCUM Mods';

    public const PAGE_MOD_SETTINGS = 'ExclsvSCUM Mod Settings';

    public const PAGE_PLAYERS = 'ExclsvSCUM Players';

    public const PAGE_PLAYER_LISTS = 'ExclsvSCUM Player lists';

    public const PAGE_HELP = 'ExclsvSCUM Help & guide';

    public const PAGE_RESTARTS = 'ExclsvSCUM Restarts';

    /** Mod folder => display name (the same since 1.33.0, when the folders were renamed). */
    public const MODS = [
        'ExclsvPlayerTools' => 'ExclsvPlayerTools',
        'ExclsvAntiCheat' => 'ExclsvAntiCheat',
        'ExclsvMessages' => 'ExclsvMessages',
        'ExclsvConsole' => 'ExclsvConsole',
        'ExclsvProbe' => 'ExclsvProbe',
    ];

    /**
     * Folder names our mods had before 1.33.0 => their folder now. "Install / update our mods"
     * moves old folders (settings and data included) to the new names.
     */
    public const LEGACY_FOLDERS = [
        'PelicanConsole' => 'ExclsvConsole',
        'PlayerTools' => 'ExclsvPlayerTools',
        'ScumAntiCheat' => 'ExclsvAntiCheat',
        'ServerMessages' => 'ExclsvMessages',
        'ScumCommandProbe' => 'ExclsvProbe',
    ];

    /** Display name for a mod folder; mods that are not ours keep their own name. */
    public static function mod(string $folder): string
    {
        return self::MODS[$folder] ?? self::LEGACY_FOLDERS[$folder] ?? $folder;
    }
}
