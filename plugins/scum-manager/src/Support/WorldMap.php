<?php

namespace MrExclusive\ScumManager\Support;

/**
 * SCUM's map grid and a simple live map drawn as SVG.
 *
 * The island is a 5 x 5 grid of 3,048 m sectors starting at -904,800 cm on both axes. Columns
 * 0-4 run along X; rows Z, A, B, C, D run along Y (worked out from the outposts A0, B4, C2 and
 * Z3, the same way PlayerTools does). Positions are in centimetres, as SCUM stores them.
 */
final class WorldMap
{
    public const GRID_MIN = -904800;

    public const SECTOR = 304800;

    public const ROWS = ['Z', 'A', 'B', 'C', 'D'];

    /** Bases closer than this to an outpost are flagged (metres). */
    public const OUTPOST_WARNING_METRES = 750;

    /** Marker colours, readable on light and dark backgrounds. */
    private const COLOURS = [
        'player' => '#16a34a',
        'base' => '#d97706',
        'warning' => '#dc2626',
        'outpost' => '#2563eb',
    ];

    /** "B2", or null outside the map. */
    public static function sector(float $x, float $y): ?string
    {
        $column = (int) floor(($x - self::GRID_MIN) / self::SECTOR);
        $row = (int) floor(($y - self::GRID_MIN) / self::SECTOR);

        return $column >= 0 && $column <= 4 && $row >= 0 && $row <= 4 ? self::ROWS[$row] . $column : null;
    }

    /**
     * The nearest of the given places and its distance in metres.
     *
     * @param  list<array{name: string, x: float|int, y: float|int}>  $places
     * @return array{name: string, metres: int}|null
     */
    public static function nearest(float $x, float $y, array $places): ?array
    {
        $best = null;
        foreach ($places as $place) {
            $metres = (int) round(sqrt(($place['x'] - $x) ** 2 + ($place['y'] - $y) ** 2) / 100);
            if ($best === null || $metres < $best['metres']) {
                $best = ['name' => (string) $place['name'], 'metres' => $metres];
            }
        }

        return $best;
    }

    /**
     * The map as an SVG: sector grid and labels, then markers.
     *
     * @param  list<array{x: float|int, y: float|int, label: string, kind: string}>  $markers  kind: player, base, warning, outpost
     */
    public static function svg(array $markers, int $size = 640): string
    {
        $extent = 5 * self::SECTOR;
        $scale = $size / $extent;
        $px = fn (float $value) => round(($value - self::GRID_MIN) * $scale, 1);
        $cell = $size / 5;

        $out = [sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %1$d %1$d" width="100%%" style="max-width:%1$dpx;display:block;margin:0 auto;font-family:ui-sans-serif,system-ui,sans-serif;" role="img" aria-label="Live map">', $size)];
        $out[] = sprintf('<rect x="0" y="0" width="%1$d" height="%1$d" fill="rgba(127,127,127,0.06)" stroke="rgba(127,127,127,0.5)"/>', $size);
        for ($i = 1; $i < 5; $i++) {
            $at = round($i * $cell, 1);
            $out[] = "<line x1=\"$at\" y1=\"0\" x2=\"$at\" y2=\"$size\" stroke=\"rgba(127,127,127,0.35)\"/>";
            $out[] = "<line x1=\"0\" y1=\"$at\" x2=\"$size\" y2=\"$at\" stroke=\"rgba(127,127,127,0.35)\"/>";
        }
        foreach (self::ROWS as $row => $letter) {
            for ($column = 0; $column < 5; $column++) {
                $out[] = sprintf('<text x="%s" y="%s" font-size="11" fill="rgba(127,127,127,0.8)">%s%d</text>',
                    round($column * $cell + 5, 1), round($row * $cell + 14, 1), $letter, $column);
            }
        }

        // Outposts and bases first, players on top.
        $order = ['outpost' => 0, 'base' => 1, 'warning' => 2, 'player' => 3];
        usort($markers, fn (array $a, array $b) => ($order[$a['kind']] ?? 9) <=> ($order[$b['kind']] ?? 9));
        foreach ($markers as $marker) {
            $x = $px((float) $marker['x']);
            $y = $px((float) $marker['y']);
            if ($x < 0 || $y < 0 || $x > $size || $y > $size) {
                continue;
            }
            $colour = self::COLOURS[$marker['kind']] ?? '#6b7280';
            $title = '<title>' . htmlspecialchars($marker['label'], ENT_QUOTES) . '</title>';
            $out[] = match ($marker['kind']) {
                'outpost' => sprintf('<g>%s<rect x="%s" y="%s" width="12" height="12" fill="%s" opacity="0.85"/><text x="%s" y="%s" font-size="11" font-weight="600" fill="%s">%s</text></g>',
                    $title, $x - 6, $y - 6, $colour, $x + 9, $y + 4, $colour, htmlspecialchars($marker['label'], ENT_QUOTES)),
                'base', 'warning' => sprintf('<g>%s<rect x="%s" y="%s" width="8" height="8" fill="%s" transform="rotate(45 %s %s)"/></g>',
                    $title, $x - 4, $y - 4, $colour, $x, $y),
                default => sprintf('<g>%s<circle cx="%s" cy="%s" r="5" fill="%s" stroke="white" stroke-width="1.5"/><text x="%s" y="%s" font-size="10" fill="%s">%s</text></g>',
                    $title, $x, $y, $colour, $x + 7, $y - 6, $colour, htmlspecialchars($marker['label'], ENT_QUOTES)),
            };
        }
        $out[] = '</svg>';

        return implode('', $out);
    }
}
