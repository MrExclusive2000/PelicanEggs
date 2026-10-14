<?php

namespace MrExclusive\ScumManager\Support;

/**
 * ExclsvConsole's history.tsv (one line every 5 minutes) drawn as small line graphs:
 *   <unix time> <tab> players <tab> average FPS <tab> lowest FPS <tab> memory MB <tab> CPU %
 * Memory is shown in GB. Empty fields are left out of the graph; gaps longer than 15 minutes (server down) break the line.
 */
final class HistoryChart
{
    public const SERIES = [
        'players' => ['label' => 'Players online', 'unit' => '', 'color' => '#3b82f6'],
        'fps' => ['label' => 'Server FPS (average)', 'unit' => ' FPS', 'color' => '#22c55e'],
        'memory' => ['label' => 'Memory', 'unit' => ' GB', 'color' => '#a855f7'],
        'cpu' => ['label' => 'CPU', 'unit' => '%', 'color' => '#f97316'],
    ];

    /** A gap longer than this between two points is drawn as a break (the server was down). */
    public const GAP_SECONDS = 15 * 60;

    /**
     * @return list<array{time: int, players: ?float, fps: ?float, fpsLow: ?float, memory: ?float, cpu: ?float}>
     */
    public static function parse(?string $tsv, int $from): array
    {
        $rows = [];
        foreach (explode("\n", str_replace("\r\n", "\n", $tsv ?? '')) as $line) {
            $fields = explode("\t", $line);
            if (count($fields) < 4 || !ctype_digit($fields[0]) || (int) $fields[0] < $from) {
                continue;
            }
            $number = fn (int $index) => isset($fields[$index]) && is_numeric(trim($fields[$index])) ? (float) trim($fields[$index]) : null;
            $rows[] = [
                'time' => (int) $fields[0], 'players' => $number(1), 'fps' => $number(2),
                'fpsLow' => $number(3), 'memory' => $number(4) === null ? null : round($number(4) / 1024, 2), 'cpu' => $number(5),
            ];
        }
        usort($rows, fn ($a, $b) => $a['time'] <=> $b['time']);

        return $rows;
    }

    /** @return array{latest: ?float, peak: ?float, average: ?float} */
    public static function summary(array $rows, string $key): array
    {
        $values = array_values(array_filter(array_column($rows, $key), fn ($v) => $v !== null));
        if ($values === []) {
            return ['latest' => null, 'peak' => null, 'average' => null];
        }

        return ['latest' => end($values), 'peak' => max($values), 'average' => array_sum($values) / count($values)];
    }

    /** An SVG line graph of one series between $from and $to (unix times). */
    public static function svg(array $rows, string $key, int $from, int $to): string
    {
        $series = self::SERIES[$key];
        $width = 600;
        $height = 140;
        $left = 40;
        $bottom = 20;
        $plotW = $width - $left - 8;
        $plotH = $height - $bottom - 8;

        $points = array_values(array_filter($rows, fn ($row) => $row[$key] !== null));
        $max = 0.0;
        foreach ($points as $row) {
            $max = max($max, $row[$key]);
        }
        $max = self::niceMax($max);
        $span = max(1, $to - $from);

        $x = fn (int $time) => $left + ($time - $from) / $span * $plotW;
        $y = fn (float $value) => 8 + $plotH - ($value / $max) * $plotH;

        $paths = [];
        $current = [];
        $previous = null;
        foreach ($points as $row) {
            if ($previous !== null && $row['time'] - $previous > self::GAP_SECONDS && $current !== []) {
                $paths[] = $current;
                $current = [];
            }
            $current[] = sprintf('%.1f,%.1f', $x($row['time']), $y($row[$key]));
            $previous = $row['time'];
        }
        if ($current !== []) {
            $paths[] = $current;
        }

        $svg = sprintf('<svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s" style="display:block;max-width:100%%;height:auto;">', $width, $height, self::e($series['label']));
        // Grid and value labels (0, half, max).
        foreach ([0, 0.5, 1] as $fraction) {
            $value = $max * $fraction;
            $lineY = $y($value);
            $svg .= sprintf('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="currentColor" stroke-opacity="0.15" />', $left, $lineY, $width - 8, $lineY);
            $svg .= sprintf('<text x="%d" y="%.1f" font-size="10" text-anchor="end" fill="currentColor" fill-opacity="0.6">%s</text>', $left - 4, $lineY + 3, self::e(self::short($value)));
        }
        // Time labels: start, middle, end.
        foreach ([$from, intdiv($from + $to, 2), $to] as $index => $time) {
            $anchor = ['start', 'middle', 'end'][$index];
            $format = $to - $from > 2 * 86400 ? 'D H:i' : 'H:i';
            $svg .= sprintf('<text x="%.1f" y="%d" font-size="10" text-anchor="%s" fill="currentColor" fill-opacity="0.6">%s</text>', $x($time), $height - 4, $anchor, gmdate($format, $time));
        }
        foreach ($paths as $path) {
            if (count($path) === 1) {
                [$px, $py] = explode(',', $path[0]);
                $svg .= sprintf('<circle cx="%s" cy="%s" r="2" fill="%s" />', $px, $py, $series['color']);
            } else {
                $svg .= sprintf('<polyline points="%s" fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />', implode(' ', $path), $series['color']);
            }
        }
        if ($points === []) {
            $svg .= sprintf('<text x="%d" y="%d" font-size="12" text-anchor="middle" fill="currentColor" fill-opacity="0.6">No data yet</text>', $left + $plotW / 2, 8 + $plotH / 2);
        }

        return $svg . '</svg>';
    }

    /** A round top for the axis: 3 -> 4, 27 -> 30, 1400 -> 1500. */
    public static function niceMax(float $max): float
    {
        if ($max <= 0) {
            return 1.0;
        }
        $magnitude = 10 ** floor(log10($max));
        foreach ([1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10] as $step) {
            if ($step * $magnitude >= $max) {
                return $step * $magnitude;
            }
        }

        return 10 * $magnitude;
    }

    private static function short(float $value): string
    {
        return match (true) {
            $value >= 10000 => sprintf('%.0fk', $value / 1000),
            $value >= 1000 => sprintf('%.1fk', $value / 1000),
            $value == floor($value) => (string) (int) $value,
            default => sprintf('%.1f', $value),
        };
    }

    private static function e(string $text): string
    {
        return htmlspecialchars($text, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }
}
