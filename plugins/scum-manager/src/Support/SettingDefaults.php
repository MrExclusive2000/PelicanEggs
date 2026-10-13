<?php

namespace MrExclusive\ScumManager\Support;

/**
 * SCUM's own defaults, read from a ServerSettings.ini the game generated from scratch
 * (captured once from the user's server, so they match the installed version exactly).
 */
final class SettingDefaults
{
    /** @return array<string, array<string, string>> section => [key => value] */
    public static function fromIni(string $raw): array
    {
        $defaults = [];
        foreach (IniDocument::parse($raw)->entries() as $entry) {
            $defaults[$entry['section']][$entry['key']] = $entry['value'];
        }

        return $defaults;
    }

    /** Whether a value differs from the default, ignoring formatting (1 vs 1.000000, true vs True). */
    public static function differs(string $value, string $default): bool
    {
        $type = SettingType::infer($default);
        if (SettingType::infer($value) !== $type && !in_array($type, [SettingType::Integer, SettingType::Decimal], true)) {
            return trim($value) !== trim($default);
        }

        return match ($type) {
            SettingType::Toggle => strtolower(trim($value)) !== strtolower(trim($default)),
            SettingType::Integer, SettingType::Decimal => !is_numeric(trim($value)) || abs((float) $value - (float) $default) > 1e-6,
            default => trim($value) !== trim($default),
        };
    }

    /** How the default reads under a field: "Default: 1", "Default: on", "Default: (empty)". */
    public static function label(string $default): string
    {
        $default = trim($default);
        $text = match (true) {
            $default === '' => '(empty)',
            SettingType::infer($default) === SettingType::Toggle => strtolower($default) === 'true' ? 'on' : 'off',
            (bool) preg_match('/^-?\d+\.\d+$/', $default) => rtrim(rtrim($default, '0'), '.'),
            default => $default,
        };

        return 'Default: ' . $text . (in_array($text, ['-1'], true) ? ' (SCUM decides)' : '');
    }
}
