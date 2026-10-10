<?php

namespace MrExclusive\ScumManager\Support;

/**
 * Edits UE4SS's mod load lists. UE4SS keeps the same information in two files,
 * Mods/mods.txt ("Name : 1" lines) and, in newer builds, Mods/mods.json. Both are
 * updated together so they never disagree. UE4SS requires "Keybinds" to stay last.
 */
final class ModList
{
    private const LINE_PATTERN = '/^\s*([^:;\s][^:]*?)\s*:\s*([01])\s*$/';

    private const LAST_MOD = 'Keybinds';

    /** @param  string[]  $lines */
    private function __construct(
        private array $lines,
        private readonly string $eol,
        private ?array $json,
    ) {}

    public static function parse(?string $modsTxt, ?string $modsJson = null): self
    {
        $modsTxt ??= '';
        $eol = str_contains($modsTxt, "\r\n") ? "\r\n" : "\n";
        $lines = $modsTxt === '' ? [] : (preg_split('/\r\n|\n|\r/', rtrim($modsTxt, "\r\n")) ?: []);

        $json = null;
        if ($modsJson !== null && trim($modsJson) !== '') {
            $decoded = json_decode($modsJson, true);
            $json = is_array($decoded) ? array_values(array_filter($decoded, 'is_array')) : null;
        }

        return new self($lines, $eol, $json);
    }

    /** @return array<string, bool> mod name => enabled, as listed in mods.txt */
    public function all(): array
    {
        $mods = [];
        foreach ($this->lines as $line) {
            if (preg_match(self::LINE_PATTERN, $line, $match)) {
                $mods[trim($match[1])] = $match[2] === '1';
            }
        }

        if ($mods === [] && $this->json !== null) {
            foreach ($this->json as $entry) {
                if (isset($entry['mod_name'])) {
                    $mods[(string) $entry['mod_name']] = (bool) ($entry['mod_enabled'] ?? false);
                }
            }
        }

        return $mods;
    }

    public function isListed(string $name): bool
    {
        return array_key_exists($name, $this->all());
    }

    public function isEnabled(string $name): ?bool
    {
        return $this->all()[$name] ?? null;
    }

    public function setEnabled(string $name, bool $enabled): void
    {
        $value = $enabled ? '1' : '0';
        $found = false;

        foreach ($this->lines as $index => $line) {
            if (preg_match(self::LINE_PATTERN, $line, $match) && trim($match[1]) === $name) {
                $this->lines[$index] = "$name : $value";
                $found = true;
            }
        }

        if (!$found) {
            $this->insertLine("$name : $value");
        }

        if ($this->json !== null) {
            $found = false;
            foreach ($this->json as $index => $entry) {
                if (($entry['mod_name'] ?? null) === $name) {
                    $this->json[$index]['mod_enabled'] = $enabled;
                    $found = true;
                }
            }

            if (!$found) {
                $this->insertJson(['mod_name' => $name, 'mod_enabled' => $enabled]);
            }
        }
    }

    public function remove(string $name): void
    {
        $this->lines = array_values(array_filter(
            $this->lines,
            fn (string $line) => !(preg_match(self::LINE_PATTERN, $line, $match) && trim($match[1]) === $name),
        ));

        if ($this->json !== null) {
            $this->json = array_values(array_filter($this->json, fn (array $entry) => ($entry['mod_name'] ?? null) !== $name));
        }
    }

    public function renderTxt(): string
    {
        return implode($this->eol, $this->lines) . $this->eol;
    }

    public function hasJson(): bool
    {
        return $this->json !== null;
    }

    public function renderJson(): ?string
    {
        if ($this->json === null) {
            return null;
        }

        return json_encode($this->json, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";
    }

    private function insertLine(string $line): void
    {
        // Keep "Keybinds" (and the comment block UE4SS puts above it) at the bottom.
        $insertAt = count($this->lines);
        foreach ($this->lines as $index => $existing) {
            if (preg_match(self::LINE_PATTERN, $existing, $match) && trim($match[1]) === self::LAST_MOD) {
                $insertAt = $index;
                while ($insertAt > 0 && (trim($this->lines[$insertAt - 1]) === '' || str_starts_with(ltrim($this->lines[$insertAt - 1]), ';'))) {
                    $insertAt--;
                }

                break;
            }
        }

        // Skip back over trailing blank lines so the new entry joins the list.
        while ($insertAt > 0 && $insertAt === count($this->lines) && trim($this->lines[$insertAt - 1]) === '') {
            $insertAt--;
        }

        array_splice($this->lines, $insertAt, 0, [$line]);
    }

    /** @param  array{mod_name: string, mod_enabled: bool}  $entry */
    private function insertJson(array $entry): void
    {
        $insertAt = count($this->json ?? []);
        foreach ($this->json ?? [] as $index => $existing) {
            if (($existing['mod_name'] ?? null) === self::LAST_MOD) {
                $insertAt = $index;

                break;
            }
        }

        array_splice($this->json, $insertAt, 0, [$entry]);
    }
}
