<?php

namespace MrExclusive\ScumManager\Support;

use RuntimeException;

/**
 * Reads and writes the mods' config.lua files: "return { ... }" with strings, numbers,
 * booleans and nested tables. Comments are skipped when reading and not written back.
 */
final class LuaTable
{
    private int $pos = 0;

    private function __construct(private readonly string $source) {}

    /** @return array<mixed> */
    public static function parse(string $source): array
    {
        $parser = new self($source);
        $parser->skip();
        if (!$parser->consumeWord('return')) {
            throw new RuntimeException('config.lua does not start with "return".');
        }
        $value = $parser->value();
        $parser->skip();
        if ($parser->pos < strlen($source)) {
            throw new RuntimeException('Unexpected text after the settings table in config.lua.');
        }
        if (!is_array($value)) {
            throw new RuntimeException('config.lua does not return a table.');
        }

        return $value;
    }

    /** @param array<mixed> $table */
    public static function render(array $table, string $header = ''): string
    {
        $lines = $header === '' ? '' : implode("\n", array_map(fn ($line) => '-- ' . $line, explode("\n", $header))) . "\n";

        return $lines . 'return ' . self::renderValue($table, 0) . "\n";
    }

    private static function renderValue(mixed $value, int $depth): string
    {
        if (is_bool($value)) {
            return $value ? 'true' : 'false';
        }
        if (is_int($value)) {
            return (string) $value;
        }
        if (is_float($value)) {
            return floor($value) === $value && abs($value) < 1e15 ? sprintf('%.1F', $value) : rtrim(rtrim(sprintf('%.6F', $value), '0'), '.');
        }
        if ($value === null) {
            return 'nil';
        }
        if (is_string($value)) {
            return '"' . strtr($value, ['\\' => '\\\\', '"' => '\\"', "\n" => '\\n', "\r" => '\\r', "\t" => '\\t', "\0" => '\\0']) . '"';
        }
        if (!is_array($value)) {
            throw new RuntimeException('Cannot write a ' . get_debug_type($value) . ' to config.lua.');
        }
        if ($value === []) {
            return '{}';
        }

        $indent = str_repeat('    ', $depth + 1);
        $close = str_repeat('    ', $depth);

        if (array_is_list($value)) {
            $scalars = array_filter($value, fn ($item) => !is_array($item));
            if (count($scalars) === count($value) && strlen(implode('', array_map('strval', $value))) < 60) {
                return '{ ' . implode(', ', array_map(fn ($item) => self::renderValue($item, $depth + 1), $value)) . ' }';
            }
            $items = array_map(fn ($item) => $indent . self::renderValue($item, $depth + 1) . ',', $value);
        } else {
            $items = [];
            foreach ($value as $key => $item) {
                $name = is_string($key) && preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $key) ? $key : '[' . self::renderValue($key, $depth + 1) . ']';
                $items[] = $indent . $name . ' = ' . self::renderValue($item, $depth + 1) . ',';
            }
        }

        return "{\n" . implode("\n", $items) . "\n" . $close . '}';
    }

    // ------------------------------------------------------------------ parser

    private function value(): mixed
    {
        $this->skip();
        $char = $this->source[$this->pos] ?? '';

        if ($char === '{') {
            return $this->table();
        }
        if ($char === '"' || $char === "'") {
            return $this->string();
        }
        if ($char === '[' && preg_match('/\G\[=*\[/', $this->source, $m, 0, $this->pos)) {
            return $this->longString();
        }
        if (preg_match('/\G-?(?:0x[0-9a-fA-F]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)/', $this->source, $m, 0, $this->pos)) {
            $this->pos += strlen($m[0]);
            if (str_contains(strtolower($m[0]), '0x')) {
                return (int) hexdec(str_replace(['-', '0x', '0X'], '', $m[0])) * (str_starts_with($m[0], '-') ? -1 : 1);
            }

            return preg_match('/[.eE]/', $m[0]) ? (float) $m[0] : (int) $m[0];
        }
        foreach (['true' => true, 'false' => false, 'nil' => null] as $word => $result) {
            if ($this->consumeWord($word)) {
                return $result;
            }
        }

        throw $this->error('Unexpected "' . substr($this->source, $this->pos, 10) . '"');
    }

    /** @return array<mixed> */
    private function table(): array
    {
        $this->pos++; // {
        $result = [];
        $next = 1;

        while (true) {
            $this->skip();
            if (($this->source[$this->pos] ?? '') === '}') {
                $this->pos++;

                return $result;
            }

            if (($this->source[$this->pos] ?? '') === '[' && !preg_match('/\G\[=*\[/', $this->source, $m, 0, $this->pos)) {
                $this->pos++;
                $key = $this->value();
                $this->skip();
                $this->expect(']');
                $this->skip();
                $this->expect('=');
                $result[$key] = $this->value();
            } elseif (preg_match('/\G([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)/', $this->source, $m, 0, $this->pos)) {
                $this->pos += strlen($m[0]);
                $result[$m[1]] = $this->value();
            } else {
                $result[$next - 1] = $this->value();
                $next++;
            }

            $this->skip();
            $char = $this->source[$this->pos] ?? '';
            if ($char === ',' || $char === ';') {
                $this->pos++;
            } elseif ($char !== '}') {
                throw $this->error('Expected "," or "}"');
            }
        }
    }

    private function string(): string
    {
        $quote = $this->source[$this->pos++];
        $result = '';
        $escapes = ['n' => "\n", 't' => "\t", 'r' => "\r", '\\' => '\\', '"' => '"', "'" => "'", '0' => "\0", "\n" => "\n"];

        while ($this->pos < strlen($this->source)) {
            $char = $this->source[$this->pos++];
            if ($char === $quote) {
                return $result;
            }
            if ($char === "\n") {
                break;
            }
            if ($char === '\\') {
                $next = $this->source[$this->pos++] ?? '';
                if (ctype_digit($next) && preg_match('/\G\d{1,2}/', $this->source, $m, 0, $this->pos)) {
                    $this->pos += strlen($m[0]);
                    $result .= chr((int) ($next . $m[0]));
                } else {
                    $result .= $escapes[$next] ?? $next;
                }
            } else {
                $result .= $char;
            }
        }

        throw $this->error('Unfinished string');
    }

    private function longString(): string
    {
        preg_match('/\G\[(=*)\[\n?/', $this->source, $m, 0, $this->pos);
        $end = strpos($this->source, ']' . $m[1] . ']', $this->pos + strlen($m[0]));
        if ($end === false) {
            throw $this->error('Unfinished string');
        }
        $result = substr($this->source, $this->pos + strlen($m[0]), $end - $this->pos - strlen($m[0]));
        $this->pos = $end + strlen($m[1]) + 2;

        return $result;
    }

    /** Skip whitespace and comments. */
    private function skip(): void
    {
        while (true) {
            if (preg_match('/\G\s+/', $this->source, $m, 0, $this->pos)) {
                $this->pos += strlen($m[0]);
            }
            if (preg_match('/\G--\[(=*)\[/', $this->source, $m, 0, $this->pos)) {
                $end = strpos($this->source, ']' . $m[1] . ']', $this->pos);
                $this->pos = $end === false ? strlen($this->source) : $end + strlen($m[1]) + 2;
            } elseif (substr($this->source, $this->pos, 2) === '--') {
                $end = strpos($this->source, "\n", $this->pos);
                $this->pos = $end === false ? strlen($this->source) : $end + 1;
            } else {
                return;
            }
        }
    }

    private function consumeWord(string $word): bool
    {
        if (preg_match('/\G' . $word . '(?![A-Za-z0-9_])/', $this->source, $m, 0, $this->pos)) {
            $this->pos += strlen($word);

            return true;
        }

        return false;
    }

    private function expect(string $char): void
    {
        if (($this->source[$this->pos] ?? '') !== $char) {
            throw $this->error("Expected \"$char\"");
        }
        $this->pos++;
    }

    private function error(string $message): RuntimeException
    {
        $line = substr_count(substr($this->source, 0, $this->pos), "\n") + 1;

        return new RuntimeException("config.lua line $line: $message.");
    }
}
