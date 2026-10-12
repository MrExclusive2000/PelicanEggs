<?php

namespace MrExclusive\ScumManager\Support;

use InvalidArgumentException;

/**
 * mods/dist/manifest.json: which of our mod zips are published, with each zip's sha256 (checked
 * after downloading) and a build id that changes only when the mod's files change.
 *
 *   { "format": "exclsv-mods", "manager": "1.14.0",
 *     "mods": { "PlayerTools": { "file": "PlayerTools.zip", "build": "e383f4863a33", "sha256": "...", "bytes": 32171 } } }
 *
 * Only our own mods (Brand::MODS) are accepted, and only plain zip names next to the manifest.
 */
final class ModManifest
{
    public const FORMAT = 'exclsv-mods';

    public const MAX_BYTES = 64 * 1024;

    /** Each installed mod gets this file with the build it came from. */
    public const BUILD_FILE = 'exclsv-build.txt';

    /**
     * @return array{manager: ?string, mods: array<string, array{file: string, build: string, sha256: string, bytes: int}>}
     */
    public static function parse(string $json): array
    {
        if (strlen($json) > self::MAX_BYTES) {
            throw new InvalidArgumentException('The mod manifest is too large.');
        }

        try {
            $data = json_decode($json, true, 16, JSON_THROW_ON_ERROR);
        } catch (\JsonException $exception) {
            throw new InvalidArgumentException('The mod manifest is not valid JSON: ' . $exception->getMessage());
        }

        if (!is_array($data) || ($data['format'] ?? null) !== self::FORMAT || !is_array($data['mods'] ?? null)) {
            throw new InvalidArgumentException('This is not an Exclsv mod manifest.');
        }

        $mods = [];
        foreach ($data['mods'] as $name => $entry) {
            if (!array_key_exists($name, Brand::MODS)) {
                continue; // not one of ours: never installed from here
            }
            if (!is_array($entry)
                || ($entry['file'] ?? null) !== "$name.zip"
                || !is_string($entry['sha256'] ?? null) || !preg_match('/^[0-9a-f]{64}$/', $entry['sha256'])
                || !is_string($entry['build'] ?? null) || !preg_match('/^[0-9a-f]{6,64}$/', $entry['build'])
                || !is_int($entry['bytes'] ?? null) || $entry['bytes'] <= 0) {
                throw new InvalidArgumentException("The manifest entry for $name is malformed.");
            }
            $mods[$name] = [
                'file' => $entry['file'],
                'build' => $entry['build'],
                'sha256' => $entry['sha256'],
                'bytes' => $entry['bytes'],
            ];
        }

        $manager = $data['manager'] ?? null;

        return [
            'manager' => is_string($manager) && preg_match('/^\d+(\.\d+){0,3}$/', $manager) ? $manager : null,
            'mods' => $mods,
        ];
    }

    /** URL of a file next to the manifest. Only https sources are used. */
    public static function url(string $base, string $file): string
    {
        $base = rtrim(trim($base), '/');
        if (!str_starts_with(strtolower($base), 'https://')) {
            throw new InvalidArgumentException('The mod source must be an https:// URL.');
        }

        return $base . '/' . rawurlencode($file);
    }

    /** Throws unless the downloaded zip is exactly the one the manifest describes. */
    public static function verify(string $contents, array $entry, string $name): void
    {
        if (strlen($contents) !== $entry['bytes'] || !hash_equals($entry['sha256'], hash('sha256', $contents))) {
            throw new InvalidArgumentException("The download of $name does not match the manifest (incomplete or changed); it was not installed.");
        }
    }

    /** "1.14.0" is newer than "1.13.2". */
    public static function isNewer(?string $latest, string $current): bool
    {
        return $latest !== null && version_compare($latest, $current, '>');
    }
}
