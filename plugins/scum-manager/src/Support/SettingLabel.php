<?php

namespace MrExclusive\ScumManager\Support;

final class SettingLabel
{
    /** "scum.MaxAllowedNPCsInWorld" => "Max Allowed NPCs In World" */
    public static function fromKey(string $key): string
    {
        $name = preg_replace('/^scum\./i', '', $key) ?? $key;
        $name = str_replace(['_', '.'], ' ', $name);
        $name = preg_replace('/(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])|(?<=[a-zA-Z])(?=\d)/', ' ', $name) ?? $name;
        // Re-join plural acronyms the split above tore apart ("NP Cs" => "NPCs").
        $name = preg_replace('/\b([A-Z]+) ([A-Z]s)\b/', '$1$2', $name) ?? $name;

        return trim(preg_replace('/\s+/', ' ', $name) ?? $name);
    }
}
