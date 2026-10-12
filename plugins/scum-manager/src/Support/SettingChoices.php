<?php

namespace MrExclusive\ScumManager\Support;

/**
 * Settings whose numbers stand for named choices, shown as a dropdown instead of a number box.
 * Values come from SCUM's own enums (read from the game with the ExclsvProbe mod).
 */
final class SettingChoices
{
    /** @var array<string, array<string, string>> ini key => [value => label] */
    private const CHOICES = [
        // ERaidProtectionType
        'scum.RaidProtectionType' => [
            '0' => 'Off: bases can be raided any time',
            '1' => 'Offline protection: bases are protected while their owners are offline',
            '2' => 'Flag-specific: each flag owner picks protected hours',
            '3' => 'Global raid times: raids only in the server\'s raid windows',
        ],
    ];

    /** @return array<string, string>|null */
    public static function for(string $key): ?array
    {
        return self::CHOICES[$key] ?? null;
    }
}
