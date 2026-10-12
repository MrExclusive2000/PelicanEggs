<?php

namespace MrExclusive\ScumManager\Support;

use InvalidArgumentException;

/**
 * One file with all of our settings, for exporting, editing elsewhere and importing again:
 * every Exclsv mod's config (as data) and, optionally, ServerSettings.ini (as text).
 *
 *   {
 *     "format": "exclsv-settings", "version": 1, "exported": "...", "server": "...",
 *     "mods": { "ExclsvPlayerTools": { ...config.lua as JSON... }, ... },
 *     "serverSettings": "[General]\n..."            (optional)
 *   }
 *
 * Mods are written under their display names; folder names are accepted too.
 */
final class SettingsBundle
{
    public const FORMAT = 'exclsv-settings';

    public const VERSION = 1;

    /** Larger files are refused before they are parsed. */
    public const MAX_BYTES = 2 * 1024 * 1024;

    /**
     * @param  array<string, array>  $modConfigs  mod folder => config table
     */
    public static function make(array $modConfigs, ?string $serverSettings, string $serverName, string $exportedAt): string
    {
        $mods = [];
        foreach ($modConfigs as $folder => $config) {
            $mods[Brand::mod($folder)] = self::emptyAsObject($config);
        }

        $bundle = [
            'format' => self::FORMAT,
            'version' => self::VERSION,
            'exported' => $exportedAt,
            'server' => $serverName,
            'note' => 'Edit freely and import it again on the ' . Brand::PAGE_MOD_SETTINGS . ' page. Leave out a mod or serverSettings to keep it as it is.',
            'mods' => $mods ?: new \stdClass(),
        ];
        if ($serverSettings !== null) {
            $bundle['serverSettings'] = $serverSettings;
        }

        return json_encode($bundle, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR) . "\n";
    }

    /**
     * @return array{mods: array<string, array>, serverSettings: ?string}  mods keyed by folder name
     */
    public static function parse(string $json): array
    {
        if (strlen($json) > self::MAX_BYTES) {
            throw new InvalidArgumentException('The file is too large to be a settings export.');
        }

        try {
            $data = json_decode($json, true, 64, JSON_THROW_ON_ERROR);
        } catch (\JsonException $exception) {
            throw new InvalidArgumentException('The file is not valid JSON: ' . $exception->getMessage());
        }

        if (!is_array($data) || ($data['format'] ?? null) !== self::FORMAT) {
            throw new InvalidArgumentException('This is not an Exclsv settings export (format "' . self::FORMAT . '" missing).');
        }
        if (!is_int($data['version'] ?? null) || $data['version'] > self::VERSION) {
            throw new InvalidArgumentException('This settings file is from a newer version. Update ' . Brand::MANAGER . ' first.');
        }

        $folders = [];
        foreach (array_keys(ModSettings::MODS) as $folder) {
            $folders[strtolower($folder)] = $folder;
            $folders[strtolower(Brand::mod($folder))] = $folder;
        }

        $mods = [];
        foreach (($data['mods'] ?? []) as $name => $config) {
            $folder = $folders[strtolower((string) $name)] ?? null;
            if ($folder === null) {
                throw new InvalidArgumentException("Unknown mod \"$name\" in the settings file.");
            }
            if (!is_array($config)) {
                throw new InvalidArgumentException("The settings of \"$name\" must be an object.");
            }
            $mods[$folder] = $config;
        }

        $serverSettings = $data['serverSettings'] ?? null;
        if ($serverSettings !== null) {
            if (!is_string($serverSettings) || trim($serverSettings) === '') {
                throw new InvalidArgumentException('serverSettings must be the text of ServerSettings.ini.');
            }
            // Must still read as an ini file with sections.
            if (!preg_match('/^\s*\[[^\]\r\n]+\]/m', $serverSettings)) {
                throw new InvalidArgumentException('serverSettings does not look like ServerSettings.ini (no [Section] lines).');
            }
        }

        if ($mods === [] && $serverSettings === null) {
            throw new InvalidArgumentException('The settings file contains no mods and no serverSettings.');
        }

        return ['mods' => $mods, 'serverSettings' => $serverSettings];
    }

    /** Keeps empty tables as {} so the JSON reads as settings, not as an empty list. */
    private static function emptyAsObject(array $config): array|\stdClass
    {
        if ($config === []) {
            return new \stdClass();
        }

        foreach ($config as $key => $value) {
            if (is_array($value) && $value === [] && is_string($key)) {
                // An empty list such as locations = {} stays a list.
                continue;
            }
            if (is_array($value)) {
                $config[$key] = array_is_list($value) ? $value : self::emptyAsObject($value);
            }
        }

        return $config;
    }
}
