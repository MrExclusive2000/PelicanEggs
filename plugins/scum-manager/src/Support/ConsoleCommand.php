<?php

namespace MrExclusive\ScumManager\Support;

use InvalidArgumentException;

/** Commands for the ExclsvConsole mod, which reads them one per line from commands.txt. */
final class ConsoleCommand
{
    public const MAX_LENGTH = 500;

    /** A single trimmed command line, or an exception explaining why it cannot be sent. */
    public static function normalize(string $command): string
    {
        $command = trim($command);

        if ($command === '' || trim($command, '#') === '') {
            throw new InvalidArgumentException('Type a command, for example ListPlayers.');
        }

        if (preg_match('/[\r\n\x00]/', $command)) {
            throw new InvalidArgumentException('Send one command at a time.');
        }

        if (mb_strlen($command) > self::MAX_LENGTH) {
            throw new InvalidArgumentException('Commands can be at most ' . self::MAX_LENGTH . ' characters.');
        }

        return $command;
    }

    /** commands.txt with the command appended on its own line. */
    public static function append(?string $queue, string $command): string
    {
        $queue ??= '';
        if ($queue !== '' && !str_ends_with($queue, "\n")) {
            $queue .= "\n";
        }

        return $queue . $command . "\n";
    }

    /** The last $lines non-empty lines of a log. */
    public static function tail(?string $log, int $lines = 60): string
    {
        $all = array_values(array_filter(
            explode("\n", str_replace("\r\n", "\n", $log ?? '')),
            fn (string $line) => trim($line) !== '',
        ));

        return implode("\n", array_slice($all, -$lines));
    }
}
