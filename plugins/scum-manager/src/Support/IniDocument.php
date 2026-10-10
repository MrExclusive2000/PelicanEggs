<?php

namespace MrExclusive\ScumManager\Support;

use InvalidArgumentException;

/**
 * Line-preserving reader/writer for Unreal Engine style INI files.
 *
 * Only the value part of lines that are changed gets rewritten. Comments, ordering,
 * spacing around "=", line endings and the file encoding are kept as they were, so a
 * save never reformats the rest of the file.
 */
final class IniDocument
{
    public const ENCODING_UTF8 = 'utf-8';

    public const ENCODING_UTF8_BOM = 'utf-8-bom';

    public const ENCODING_UTF16LE = 'utf-16le';

    public const ENCODING_UTF16BE = 'utf-16be';

    private const SECTION_PATTERN = '/^\s*\[([^\]]+)\]\s*$/';

    private const ENTRY_PATTERN = '/^(\s*)([^=;#\s][^=]*?)(\s*=\s*)(.*)$/';

    /** @param  string[]  $lines */
    private function __construct(
        private array $lines,
        private readonly string $encoding,
        private readonly string $eol,
        private readonly bool $trailingNewline,
    ) {}

    public static function parse(string $raw): self
    {
        [$text, $encoding] = self::decode($raw);

        $eol = str_contains($text, "\r\n") ? "\r\n" : "\n";
        $trailingNewline = $text === '' || str_ends_with($text, "\n");

        $lines = preg_split('/\r\n|\n|\r/', $text) ?: [];
        if ($trailingNewline && $text !== '') {
            array_pop($lines);
        }

        return new self($text === '' ? [] : $lines, $encoding, $eol, $trailingNewline);
    }

    public function encoding(): string
    {
        return $this->encoding;
    }

    /**
     * Every key/value pair in file order. A key that appears twice in the same section
     * is only reported once (the first one wins, which is what Unreal reads).
     *
     * @return list<array{section: string, key: string, value: string}>
     */
    public function entries(): array
    {
        $entries = [];
        $seen = [];

        foreach ($this->walk() as [$section, $key, $value]) {
            $id = $section . "\0" . $key;
            if ($section === '' || isset($seen[$id])) {
                continue;
            }

            $seen[$id] = true;
            $entries[] = ['section' => $section, 'key' => $key, 'value' => $value];
        }

        return $entries;
    }

    /** @return list<string> */
    public function sections(): array
    {
        $sections = [];
        foreach ($this->lines as $line) {
            if (preg_match(self::SECTION_PATTERN, $line, $match)) {
                $sections[] = trim($match[1]);
            }
        }

        return array_values(array_unique($sections));
    }

    public function get(string $section, string $key): ?string
    {
        foreach ($this->walk() as [$entrySection, $entryKey, $value]) {
            if ($entrySection === $section && $entryKey === $key) {
                return $value;
            }
        }

        return null;
    }

    /**
     * Set a value. An existing line keeps its key and spacing; a missing key is added
     * at the end of its section, and a missing section is added at the end of the file.
     */
    public function set(string $section, string $key, string $value): void
    {
        if (preg_match('/[\r\n]/', $value) || preg_match('/[\r\n]/', $key)) {
            throw new InvalidArgumentException("Line breaks are not allowed in INI keys or values ($key).");
        }

        $current = '';
        $lastLineOfSection = null;

        foreach ($this->lines as $index => $line) {
            if (preg_match(self::SECTION_PATTERN, $line, $match)) {
                $current = trim($match[1]);
                if ($current === $section) {
                    $lastLineOfSection = $index;
                }

                continue;
            }

            if ($current !== $section) {
                continue;
            }

            if (trim($line) !== '') {
                $lastLineOfSection = $index;
            }

            if (preg_match(self::ENTRY_PATTERN, $line, $match) && trim($match[2]) === $key) {
                $this->lines[$index] = $match[1] . $match[2] . $match[3] . $value;

                return;
            }
        }

        if ($lastLineOfSection === null) {
            if ($this->lines !== [] && trim(end($this->lines)) !== '') {
                $this->lines[] = '';
            }

            $this->lines[] = "[$section]";
            $this->lines[] = "$key=$value";

            return;
        }

        array_splice($this->lines, $lastLineOfSection + 1, 0, ["$key=$value"]);
    }

    public function render(): string
    {
        $text = implode($this->eol, $this->lines);
        if ($this->trailingNewline && $this->lines !== []) {
            $text .= $this->eol;
        }

        return match ($this->encoding) {
            self::ENCODING_UTF8_BOM => "\xEF\xBB\xBF" . $text,
            self::ENCODING_UTF16LE => "\xFF\xFE" . mb_convert_encoding($text, 'UTF-16LE', 'UTF-8'),
            self::ENCODING_UTF16BE => "\xFE\xFF" . mb_convert_encoding($text, 'UTF-16BE', 'UTF-8'),
            default => $text,
        };
    }

    /** @return \Generator<int, array{0: string, 1: string, 2: string}> */
    private function walk(): \Generator
    {
        $section = '';

        foreach ($this->lines as $line) {
            if (preg_match(self::SECTION_PATTERN, $line, $match)) {
                $section = trim($match[1]);

                continue;
            }

            if (preg_match(self::ENTRY_PATTERN, $line, $match)) {
                yield [$section, trim($match[2]), $match[4]];
            }
        }
    }

    /** @return array{0: string, 1: string} */
    private static function decode(string $raw): array
    {
        if (str_starts_with($raw, "\xEF\xBB\xBF")) {
            return [substr($raw, 3), self::ENCODING_UTF8_BOM];
        }

        if (str_starts_with($raw, "\xFF\xFE")) {
            return [mb_convert_encoding(substr($raw, 2), 'UTF-8', 'UTF-16LE'), self::ENCODING_UTF16LE];
        }

        if (str_starts_with($raw, "\xFE\xFF")) {
            return [mb_convert_encoding(substr($raw, 2), 'UTF-8', 'UTF-16BE'), self::ENCODING_UTF16BE];
        }

        return [$raw, self::ENCODING_UTF8];
    }
}
