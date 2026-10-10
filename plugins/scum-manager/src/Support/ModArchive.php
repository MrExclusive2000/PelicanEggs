<?php

namespace MrExclusive\ScumManager\Support;

use RuntimeException;
use ZipArchive;

/**
 * Inspects an uploaded UE4SS mod zip. A mod is a folder that contains Scripts/main.lua
 * (Lua mod) or dlls/main.dll (C++ mod). Zips are packaged in many ways ("MyMod/...",
 * "Mods/MyMod/...", "ue4ss/Mods/MyMod/...", or the mod's contents at the root), so the
 * mod folders are found by looking for those entry points.
 */
final class ModArchive
{
    /** @var array<string, array{name: string, type: string, files: array<string, int>}> */
    private array $mods = [];

    private function __construct(private readonly ZipArchive $zip) {}

    /**
     * @param  string  $fallbackName  mod name to use when the mod's files sit at the zip root
     *
     * @throws RuntimeException when the zip is unreadable, unsafe, too large or holds no mod
     */
    public static function open(string $path, string $fallbackName, int $maxBytes, int $maxFiles): self
    {
        $zip = new ZipArchive();
        if ($zip->open($path, ZipArchive::RDONLY) !== true) {
            throw new RuntimeException('The file is not a valid zip archive.');
        }

        if ($zip->numFiles > $maxFiles) {
            throw new RuntimeException("The archive has more than $maxFiles files.");
        }

        $archive = new self($zip);
        $archive->scan(self::sanitizeName($fallbackName), $maxBytes);

        return $archive;
    }

    /** @return list<array{name: string, type: string, files: array<string, int>}> */
    public function mods(): array
    {
        return array_values($this->mods);
    }

    public function contents(int $index): string
    {
        $contents = $this->zip->getFromIndex($index);
        if ($contents === false) {
            throw new RuntimeException('Could not read a file from the archive.');
        }

        return $contents;
    }

    public function close(): void
    {
        $this->zip->close();
    }

    public static function sanitizeName(string $name): string
    {
        $name = preg_replace('/\.zip$/i', '', basename(str_replace('\\', '/', $name))) ?? '';
        $name = preg_replace('/[^A-Za-z0-9_\-. ]/', '', $name) ?? '';

        return trim($name, ' .');
    }

    private function scan(string $fallbackName, int $maxBytes): void
    {
        $entries = [];
        $total = 0;

        for ($i = 0; $i < $this->zip->numFiles; $i++) {
            $stat = $this->zip->statIndex($i);
            if ($stat === false) {
                continue;
            }

            $name = str_replace('\\', '/', $stat['name']);
            if (str_ends_with($name, '/')) {
                continue;
            }

            if (str_starts_with($name, '/') || preg_match('#(^|/)\.\.(/|$)#', $name) || preg_match('/^[A-Za-z]:/', $name)) {
                throw new RuntimeException("The archive contains an unsafe path: $name");
            }

            $total += $stat['size'];
            if ($total > $maxBytes) {
                throw new RuntimeException('The archive is too large once extracted.');
            }

            $entries[$name] = $i;
        }

        $roots = [];
        foreach (array_keys($entries) as $name) {
            if (preg_match('#^(.*?)(?:^|/)(scripts/main\.lua|dlls/main\.dll)$#i', $name, $match)) {
                $roots[$match[1]] ??= str_starts_with(strtolower($match[2]), 'dlls') ? 'C++' : 'Lua';
            }
        }

        // A nested match (e.g. a mod bundling another mod's scripts) belongs to its outer mod.
        foreach (array_keys($roots) as $root) {
            foreach (array_keys($roots) as $other) {
                if ($other !== $root && $other !== '' && str_starts_with($root, $other . '/')) {
                    unset($roots[$root]);
                }
            }
        }

        foreach ($roots as $root => $type) {
            $modName = self::sanitizeName($root === '' ? $fallbackName : basename($root));
            if ($modName === '' || in_array(strtolower($modName), ['mods', 'ue4ss', 'shared'], true)) {
                throw new RuntimeException('Could not work out the mod name from the archive.');
            }

            $prefix = $root === '' ? '' : $root . '/';
            $files = [];
            foreach ($entries as $name => $index) {
                if ($prefix === '' || str_starts_with($name, $prefix)) {
                    $relative = substr($name, strlen($prefix));
                    if ($prefix === '' && $this->belongsToOtherRoot($name, $roots)) {
                        continue;
                    }

                    $files[$relative] = $index;
                }
            }

            $this->mods[$modName] = ['name' => $modName, 'type' => $type, 'files' => $files];
        }

        if ($this->mods === []) {
            throw new RuntimeException('No UE4SS mod found. A mod folder must contain Scripts/main.lua or dlls/main.dll.');
        }
    }

    /** @param  array<string, string>  $roots */
    private function belongsToOtherRoot(string $name, array $roots): bool
    {
        foreach (array_keys($roots) as $root) {
            if ($root !== '' && str_starts_with($name, $root . '/')) {
                return true;
            }
        }

        return false;
    }
}
