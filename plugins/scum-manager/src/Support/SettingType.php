<?php

namespace MrExclusive\ScumManager\Support;

/**
 * The value conventions SCUM uses in ServerSettings.ini, inferred from the value the
 * game wrote. Keeping the original format when writing back matters: SCUM writes
 * floats with six decimals and toggles as capitalised True/False.
 */
enum SettingType: string
{
    case Toggle = 'toggle';
    case Integer = 'integer';
    case Decimal = 'decimal';
    case Duration = 'duration';
    case Gold = 'gold';
    case Text = 'text';

    public const DURATION_PATTERN = '/^\d{1,4}:[0-5]\d:[0-5]\d$/';

    public const GOLD_PATTERN = '/^\d+g$/';

    public static function infer(string $value): self
    {
        $value = trim($value);

        return match (true) {
            in_array(strtolower($value), ['true', 'false'], true) => self::Toggle,
            (bool) preg_match('/^-?\d+$/', $value) => self::Integer,
            (bool) preg_match('/^-?\d+\.\d+$/', $value) => self::Decimal,
            (bool) preg_match(self::DURATION_PATTERN, $value) => self::Duration,
            (bool) preg_match(self::GOLD_PATTERN, $value) => self::Gold,
            default => self::Text,
        };
    }

    /** Convert a raw INI value into the state used by the form field. */
    public function toState(string $value): bool|string
    {
        $value = trim($value);

        return match ($this) {
            self::Toggle => strtolower($value) === 'true',
            default => $value,
        };
    }

    /**
     * Convert form state back into an INI value, matching the formatting of the
     * original value (e.g. the number of decimals).
     */
    public function toIni(mixed $state, string $original): string
    {
        return match ($this) {
            self::Toggle => $state ? 'True' : 'False',
            self::Integer => (string) (int) $state,
            self::Decimal => number_format((float) $state, self::decimals($original), '.', ''),
            default => str_replace(["\r", "\n"], ' ', trim((string) $state)),
        };
    }

    /** @return list<string> Laravel validation rules for the form field. */
    public function rules(): array
    {
        return match ($this) {
            self::Toggle => ['boolean'],
            self::Integer => ['required', 'integer'],
            self::Decimal => ['required', 'numeric'],
            self::Duration => ['required', 'regex:' . self::DURATION_PATTERN],
            self::Gold => ['required', 'regex:' . self::GOLD_PATTERN],
            self::Text => ['nullable', 'string', 'max:1024', 'not_regex:/[\r\n]/'],
        };
    }

    private static function decimals(string $original): int
    {
        $dot = strpos($original, '.');

        return $dot === false ? 6 : max(1, strlen(trim($original)) - $dot - 1);
    }
}
