<?php

namespace MrExclusive\ScumManager\Support;

/**
 * Moving our mods from their pre-1.33.0 folder names (PelicanConsole, PlayerTools...) to the
 * Exclsv ones. The folder is renamed as a whole, so config.lua, players.tsv, the lottery,
 * logs and every other file a mod keeps come along.
 */
final class FolderRename
{
    /** What the egg's startup command used to point the Pelican console at. */
    public const OLD_CONSOLE_DIR = 'CMD_DIR=./SCUM/Binaries/Win64/ue4ss/Mods/PelicanConsole;';

    public const NEW_CONSOLE_DIR = 'CMD_DIR=./SCUM/Binaries/Win64/ue4ss/Mods/ExclsvConsole;';

    /**
     * Which old folders to rename, and which to leave because the new folder is already there
     * (then the old one is only switched off, and its data stays for the owner to look at).
     *
     * @param  list<string>  $folders  folder names in the UE4SS Mods directory
     * @return array{rename: array<string, string>, conflicts: array<string, string>}
     */
    public static function plan(array $folders): array
    {
        $plan = ['rename' => [], 'conflicts' => []];

        foreach (Brand::LEGACY_FOLDERS as $old => $new) {
            if (!in_array($old, $folders, true)) {
                continue;
            }
            $plan[in_array($new, $folders, true) ? 'conflicts' : 'rename'][$old] = $new;
        }

        return $plan;
    }

    /**
     * The startup command with the Pelican console pointed at the new folder, or null when it
     * does not use the old one (a current or customised command is left alone).
     */
    public static function startup(string $startup): ?string
    {
        return str_contains($startup, self::OLD_CONSOLE_DIR)
            ? str_replace(self::OLD_CONSOLE_DIR, self::NEW_CONSOLE_DIR, $startup)
            : null;
    }

    /**
     * A settings export keyed by the old folder names, with the new ones (an export made before
     * 1.33.0 still imports). A file that has both keeps the new name's settings.
     *
     * @param  array<string, mixed>  $mods
     * @return array<string, mixed>
     */
    public static function renameKeys(array $mods): array
    {
        $renamed = [];
        foreach ($mods as $name => $settings) {
            $new = Brand::LEGACY_FOLDERS[$name] ?? $name;
            if ($new !== $name && array_key_exists($new, $mods)) {
                continue;
            }
            $renamed[$new] = $settings;
        }

        return $renamed;
    }
}
