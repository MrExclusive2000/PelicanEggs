<?php

namespace MrExclusive\ScumManager\Support;

/**
 * SCUM-specific UE4SS-settings.ini adjustments.
 *
 * UE4SS enables about sixteen engine hooks by default. On SCUM 1.3.x the extra hooks
 * crash the server with EXCEPTION_ACCESS_VIOLATION as soon as a player joins, so only
 * the two hooks mods commonly depend on are left on.
 */
final class Ue4ssSettings
{
    /** @var array<string, string> */
    public const SCUM_SAFE_HOOKS = [
        'HookProcessInternal' => '0',
        'HookProcessLocalScriptFunction' => '0',
        'HookInitGameState' => '0',
        'HookLoadMap' => '0',
        'HookCallFunctionByNameWithArguments' => '1',
        'HookBeginPlay' => '0',
        'HookEndPlay' => '0',
        'HookLocalPlayerExec' => '0',
        'HookAActorTick' => '0',
        'HookEngineTick' => '1',
        'HookGameViewportClientTick' => '0',
        'HookUObjectProcessEvent' => '0',
        'HookProcessConsoleExec' => '0',
        'HookUStructLink' => '0',
    ];

    /** @var array<string, string> a dedicated server has no window to show a console in */
    public const HEADLESS_DEBUG = [
        'ConsoleEnabled' => '0',
        'GuiConsoleEnabled' => '0',
        'GuiConsoleVisible' => '0',
    ];

    public static function applyScumDefaults(string $raw): string
    {
        $document = IniDocument::parse($raw);

        foreach (self::SCUM_SAFE_HOOKS as $key => $value) {
            $document->set('Hooks', $key, $value);
        }

        foreach (self::HEADLESS_DEBUG as $key => $value) {
            $document->set('Debug', $key, $value);
        }

        return $document->render();
    }
}
