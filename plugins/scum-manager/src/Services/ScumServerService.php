<?php

namespace MrExclusive\ScumManager\Services;

use App\Enums\ContainerStatus;
use App\Facades\Activity;
use App\Models\Server;
use App\Repositories\Daemon\DaemonFileRepository;
use App\Repositories\Daemon\DaemonServerRepository;
use Illuminate\Contracts\Filesystem\FileNotFoundException;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\Http;
use MrExclusive\ScumManager\Support\AdminCommands;
use MrExclusive\ScumManager\Support\ConsoleCommand;
use MrExclusive\ScumManager\Support\LuaTable;
use MrExclusive\ScumManager\Support\TeleportDestinations;
use MrExclusive\ScumManager\Support\ModArchive;
use MrExclusive\ScumManager\Support\ModList;
use MrExclusive\ScumManager\Support\Ue4ssSettings;
use RuntimeException;

class ScumServerService
{
    public const SETTINGS_FILE = 'ServerSettings.ini';

    public const FEATURE = 'scum_manager';

    /** Player list files SCUM keeps next to ServerSettings.ini. */
    public const PLAYER_LISTS = [
        'AdminUsers.ini',
        'ServerSettingsAdminUsers.ini',
        'WhitelistedUsers.ini',
        'ExclusiveUsers.ini',
        'BannedUsers.ini',
        'SilencedUsers.ini',
    ];

    /** Mods that ship inside the UE4SS download. They can be toggled but not deleted. */
    public const BUILTIN_MODS = [
        'ActorDumperMod', 'BPML_GenericFunctions', 'BPModLoaderMod', 'CheatManagerEnablerMod',
        'ConsoleCommandsMod', 'ConsoleEnablerMod', 'Keybinds', 'LineTraceMod', 'SplitScreenMod',
        'jsbLuaProfilerMod',
    ];

    /** Wings reports these states once the server process has fully stopped. */
    private const STOPPED_STATES = [ContainerStatus::Offline, ContainerStatus::Exited, ContainerStatus::Dead, ContainerStatus::Created];

    private const UE4SS_ZIP = 'scum-manager-ue4ss.zip';

    // ------------------------------------------------------------------ server

    public function isScumServer(Server $server): bool
    {
        $server->loadMissing('egg');

        $features = $server->egg->inherit_features ?? $server->egg->features ?? [];
        $tags = $server->egg->tags ?? [];

        return in_array(self::FEATURE, $features, true)
            || in_array('scum', array_map('strtolower', $tags), true)
            || str_contains($server->startup ?? '', 'SCUMServer.exe');
    }

    /** Fresh power state straight from Wings (the panel caches its own copy for 15s). */
    public function powerState(Server $server): ContainerStatus
    {
        try {
            $details = $this->daemon($server)->getDetails();

            return ContainerStatus::tryFrom((string) Arr::get($details, 'state')) ?? ContainerStatus::Missing;
        } catch (\Throwable $exception) {
            report($exception);

            return ContainerStatus::Missing;
        }
    }

    public function isStopped(Server $server): bool
    {
        return in_array($this->powerState($server), self::STOPPED_STATES, true);
    }

    public static function isStoppedState(string $state): bool
    {
        return in_array(ContainerStatus::tryFrom($state), self::STOPPED_STATES, true);
    }

    public function power(Server $server, string $action): void
    {
        $this->daemon($server)->power($action);
        cache()->forget("servers.$server->uuid.status");
    }

    /** Value of one of the server's startup variables, or null when the egg has no such variable. */
    public function variable(Server $server, string $env): ?string
    {
        $variable = $server->variables()->where('env_variable', $env)->first();

        return $variable === null ? null : (string) ($variable->server_value ?? $variable->default_value);
    }

    // ------------------------------------------------------------------ files

    public function configPath(string $file): string
    {
        return trim(config('scum-manager.config_dir'), '/') . '/' . $file;
    }

    /** File contents, or null when the file does not exist. */
    public function read(Server $server, string $path): ?string
    {
        try {
            return $this->files($server)->getContent($path);
        } catch (FileNotFoundException) {
            return null;
        }
    }

    public function write(Server $server, string $path, string $content): void
    {
        $this->files($server)->putContent($path, $content);

        Activity::event('server:file.write')
            ->property('file', $path)
            ->log();
    }

    /** @return list<array{name: string, directory: bool, size: int, modified: string}> */
    public function listDirectory(Server $server, string $path): array
    {
        try {
            $entries = $this->files($server)->getDirectory($path);
        } catch (\Throwable) {
            return [];
        }

        if (!array_is_list($entries)) {
            return [];
        }

        return array_map(fn (array $entry) => [
            'name' => (string) $entry['name'],
            'directory' => (bool) ($entry['directory'] ?? !($entry['file'] ?? true)),
            'size' => (int) ($entry['size'] ?? 0),
            'modified' => (string) ($entry['modified'] ?? ''),
        ], $entries);
    }

    // ------------------------------------------------------------------ settings

    /**
     * Keys the egg writes into ServerSettings.ini on every start. Editing them in the
     * file would be undone on the next boot, so the editor shows them read-only.
     *
     * @return array<string, array<string, string>> section => [key => description of the source]
     */
    public function eggManagedSettings(Server $server): array
    {
        $server->loadMissing('egg');

        $files = json_decode($server->egg->inherit_config_files ?? '{}', true);
        if (!is_array($files)) {
            return [];
        }

        $managed = [];
        foreach ($files as $file => $config) {
            if (!str_ends_with(str_replace('\\', '/', (string) $file), self::SETTINGS_FILE) || !is_array($config['find'] ?? null)) {
                continue;
            }

            foreach ($config['find'] as $match => $replacement) {
                // Wings splits "Section.Key" on the first dot; brackets only group dots.
                $match = str_replace(['[', ']'], '', (string) $match);
                if (!str_contains($match, '.')) {
                    continue;
                }

                [$section, $key] = explode('.', $match, 2);
                $managed[$section][$key] = is_string($replacement) ? $replacement : json_encode($replacement);
            }
        }

        return $managed;
    }

    /** Copy the current file to a timestamped backup and prune old backups. */
    public function backup(Server $server, string $file, string $contents): string
    {
        $name = $file . '.bak-' . now()->format('Ymd-His');
        $this->write($server, $this->configPath($name), $contents);

        $keep = max(1, (int) config('scum-manager.backups_to_keep', 10));
        $old = array_slice($this->backups($server, $file), $keep);
        if ($old !== []) {
            $this->files($server)->deleteFiles(config('scum-manager.config_dir'), $old);
        }

        return $name;
    }

    /** @return list<string> backup file names, newest first */
    public function backups(Server $server, string $file): array
    {
        $names = array_column(array_filter(
            $this->listDirectory($server, config('scum-manager.config_dir')),
            fn (array $entry) => !$entry['directory'] && str_starts_with($entry['name'], $file . '.bak-'),
        ), 'name');

        rsort($names);

        return array_values($names);
    }

    public function restoreBackup(Server $server, string $file, string $backup): void
    {
        $this->assertBackupName($file, $backup);

        $contents = $this->read($server, $this->configPath($backup));
        if ($contents === null) {
            throw new RuntimeException('That backup no longer exists.');
        }

        $current = $this->read($server, $this->configPath($file));
        if ($current !== null) {
            $this->backup($server, $file, $current);
        }

        $this->write($server, $this->configPath($file), $contents);
    }

    private function assertBackupName(string $file, string $backup): void
    {
        if (!preg_match('/^' . preg_quote($file, '/') . '\.bak-\d{8}-\d{6}$/', $backup)) {
            throw new RuntimeException('Invalid backup name.');
        }
    }

    // ------------------------------------------------------------------ UE4SS

    /**
     * Where UE4SS is installed. Newer (experimental) builds keep everything in a "ue4ss"
     * folder next to dwmapi.dll; the 3.0.x stable build is flat in Win64.
     *
     * @return array{installed: bool, root: string, mods: string, layout: string, proxy: bool}
     */
    public function ue4ss(Server $server): array
    {
        $binaries = trim(config('scum-manager.binaries_dir'), '/');
        $win64 = collect($this->listDirectory($server, $binaries))->keyBy('name');
        $proxy = $win64->has('dwmapi.dll');

        if ($win64->has('ue4ss') && collect($this->listDirectory($server, "$binaries/ue4ss"))->contains('name', 'UE4SS.dll')) {
            return ['installed' => true, 'root' => "$binaries/ue4ss", 'mods' => "$binaries/ue4ss/Mods", 'layout' => 'ue4ss folder', 'proxy' => $proxy];
        }

        if ($win64->has('UE4SS.dll')) {
            return ['installed' => true, 'root' => $binaries, 'mods' => "$binaries/Mods", 'layout' => 'flat', 'proxy' => $proxy];
        }

        $root = config('scum-manager.ue4ss_channel') === 'stable' ? $binaries : "$binaries/ue4ss";

        return ['installed' => false, 'root' => $root, 'mods' => "$root/Mods", 'layout' => 'none', 'proxy' => $proxy];
    }

    /** True when the Wine DLL override UE4SS needs is set on this server. */
    public function hasDwmapiOverride(Server $server): bool
    {
        $overrides = strtolower(str_replace(' ', '', $this->variable($server, 'WINEDLLOVERRIDES') ?? ''));

        return (bool) preg_match('/(^|[;,])dwmapi(,[a-z]+)*=n/', $overrides);
    }

    public function resolveUe4ssUrl(): string
    {
        if (filled($url = config('scum-manager.ue4ss_url'))) {
            return $url;
        }

        $endpoint = config('scum-manager.ue4ss_channel') === 'stable'
            ? 'https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases/latest'
            : 'https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases/tags/experimental-latest';

        $release = Http::acceptJson()->timeout(15)->connectTimeout(5)->throw()->get($endpoint)->json();

        foreach ($release['assets'] ?? [] as $asset) {
            // The runtime is "UE4SS_v<version>.zip"; "zDEV-..." and "z..." assets are developer extras.
            if (preg_match('/^UE4SS_v[\w.\-]+\.zip$/', $asset['name'] ?? '')) {
                return $asset['browser_download_url'];
            }
        }

        throw new RuntimeException('Could not find a UE4SS download in the latest release.');
    }

    /**
     * Download and extract UE4SS into the server, keeping the server's existing mod list
     * and UE4SS settings when updating.
     */
    public function installUe4ss(Server $server): string
    {
        $url = $this->resolveUe4ssUrl();
        $binaries = trim(config('scum-manager.binaries_dir'), '/');
        $current = $this->ue4ss($server);

        $preserved = [];
        if ($current['installed']) {
            foreach (['UE4SS-settings.ini' => $current['root'], 'mods.txt' => $current['mods'], 'mods.json' => $current['mods']] as $file => $dir) {
                $contents = $this->read($server, "$dir/$file");
                if ($contents !== null) {
                    $preserved["$dir/$file"] = $contents;
                }
            }
        }

        // Download in the foreground with a long timeout so the archive is complete before extracting.
        $this->files($server)->getHttpClient()
            ->timeout(600)
            ->post("/api/servers/$server->uuid/files/pull", [
                'url' => $url,
                'root' => $binaries,
                'file_name' => self::UE4SS_ZIP,
                'foreground' => true,
            ]);

        try {
            $this->files($server)->decompressFile($binaries, self::UE4SS_ZIP);
        } finally {
            $this->files($server)->deleteFiles($binaries, [self::UE4SS_ZIP]);
        }

        foreach ($preserved as $path => $contents) {
            $this->files($server)->putContent($path, $contents);
        }

        // A fresh install ships UE4SS's default hooks, which crash SCUM when a player joins.
        if (!isset($preserved[$current['root'] . '/UE4SS-settings.ini'])) {
            $this->applyScumSafeUe4ssSettings($server);
        }

        // The built-in mods are client tools (console, cheat manager, keybinds). Off by default on a server.
        if (!isset($preserved[$current['mods'] . '/mods.txt'])) {
            $this->disableBuiltinMods($server);
        }

        // Our own mods (admin console, anti-cheat, messages, player tools) come with a fresh install.
        if (!$current['installed'] && config('scum-manager.install_bundled_mods', true)) {
            $this->installBundledMods($server);
        }

        Activity::event('server:file.pull')
            ->property('directory', $binaries)
            ->property('url', $url)
            ->log();

        return $url;
    }

    /** Rewrite UE4SS-settings.ini with the hooks SCUM tolerates and no console window. */
    public function applyScumSafeUe4ssSettings(Server $server): void
    {
        $ue4ss = $this->ue4ss($server);
        if (!$ue4ss['installed']) {
            throw new RuntimeException('UE4SS is not installed.');
        }

        $path = $ue4ss['root'] . '/UE4SS-settings.ini';
        $this->write($server, $path, Ue4ssSettings::applyScumDefaults($this->read($server, $path) ?? ''));
    }

    // ------------------------------------------------------------------ mods

    /** Turn off every mod that ships with UE4SS. None of them do anything useful on a dedicated server. */
    public function disableBuiltinMods(Server $server): void
    {
        $ue4ss = $this->ue4ss($server);
        $list = $this->modList($server, $ue4ss['mods']);

        foreach (array_keys($list->all()) as $name) {
            if (in_array($name, self::BUILTIN_MODS, true)) {
                $list->setEnabled($name, false);
            }
        }

        $this->saveModList($server, $ue4ss['mods'], $list);
    }

    /** @return list<array{name: string, enabled: bool, builtin: bool, type: string}> */
    public function mods(Server $server): array
    {
        $ue4ss = $this->ue4ss($server);
        if (!$ue4ss['installed']) {
            return [];
        }

        $list = $this->modList($server, $ue4ss['mods']);
        $mods = [];

        foreach ($this->listDirectory($server, $ue4ss['mods']) as $entry) {
            if (!$entry['directory'] || strtolower($entry['name']) === 'shared') {
                continue;
            }

            $name = $entry['name'];
            $children = collect($this->listDirectory($server, $ue4ss['mods'] . '/' . $name))->pluck('name')->map(fn ($n) => strtolower($n));

            $mods[] = [
                'name' => $name,
                'enabled' => $list->isEnabled($name) ?? $children->contains('enabled.txt'),
                'builtin' => in_array($name, self::BUILTIN_MODS, true),
                'bundled' => array_key_exists($name, self::bundledMods()),
                'type' => $children->contains('dlls') ? 'C++' : ($children->contains('scripts') ? 'Lua' : 'Other'),
            ];
        }

        usort($mods, fn ($a, $b) => [$a['builtin'], strtolower($a['name'])] <=> [$b['builtin'], strtolower($b['name'])]);

        return $mods;
    }

    public function setModEnabled(Server $server, string $name, bool $enabled): void
    {
        $this->assertModName($name);
        $ue4ss = $this->ue4ss($server);

        $list = $this->modList($server, $ue4ss['mods']);
        $list->setEnabled($name, $enabled);
        $this->saveModList($server, $ue4ss['mods'], $list);

        // enabled.txt switches a mod on regardless of mods.txt, so it has to go when disabling.
        $modDir = $ue4ss['mods'] . '/' . $name;
        $marker = $enabled ? null : collect($this->listDirectory($server, $modDir))->first(fn (array $entry) => strtolower($entry['name']) === 'enabled.txt');
        if ($marker !== null) {
            $this->files($server)->deleteFiles($modDir, [$marker['name']]);
        }
    }

    public function deleteMod(Server $server, string $name): void
    {
        $this->assertModName($name);
        if (in_array($name, self::BUILTIN_MODS, true)) {
            throw new RuntimeException('Built-in UE4SS mods can be disabled but not deleted.');
        }

        $ue4ss = $this->ue4ss($server);
        $this->files($server)->deleteFiles($ue4ss['mods'], [$name]);

        $list = $this->modList($server, $ue4ss['mods']);
        $list->remove($name);
        $this->saveModList($server, $ue4ss['mods'], $list);

        Activity::event('server:file.delete')
            ->property('directory', $ue4ss['mods'])
            ->property('files', [$name])
            ->log();
    }

    /**
     * Upload every mod found in a zip and enable it.
     *
     * @param  bool  $keepSettings  leave an existing config.lua alone (used when updating our own mods)
     * @return list<string> installed mod names
     */
    public function installModArchive(Server $server, string $zipPath, string $originalName, bool $keepSettings = false): array
    {
        $ue4ss = $this->ue4ss($server);
        if (!$ue4ss['installed']) {
            throw new RuntimeException('Install UE4SS before adding mods.');
        }

        $archive = ModArchive::open(
            $zipPath,
            $originalName,
            (int) config('scum-manager.mod_max_extracted_bytes'),
            (int) config('scum-manager.mod_max_files'),
        );

        try {
            $list = $this->modList($server, $ue4ss['mods']);
            $installed = [];

            foreach ($archive->mods() as $mod) {
                foreach ($mod['files'] as $relative => $index) {
                    $path = $ue4ss['mods'] . '/' . $mod['name'] . '/' . $relative;
                    if ($keepSettings && $relative === 'config.lua' && $this->read($server, $path) !== null) {
                        continue;
                    }

                    $this->files($server)->putContent($path, $archive->contents($index));
                }

                $list->setEnabled($mod['name'], true);
                $installed[] = $mod['name'];
            }

            $this->saveModList($server, $ue4ss['mods'], $list);
        } finally {
            $archive->close();
        }

        Activity::event('server:file.uploaded')
            ->property('directory', $ue4ss['mods'])
            ->property('file', $originalName)
            ->log();

        return $installed;
    }

    /** @return array<string, string> mod name => zip path, for the mods that ship with this plugin */
    public static function bundledMods(): array
    {
        $mods = [];
        foreach (glob(dirname(__DIR__, 2) . '/resources/mods/*.zip') ?: [] as $zip) {
            $mods[basename($zip, '.zip')] = $zip;
        }
        ksort($mods);

        return $mods;
    }

    /**
     * Install or update the mods that ship with this plugin. Existing settings are kept.
     *
     * @return list<string> installed mod names
     */
    public function installBundledMods(Server $server): array
    {
        $installed = [];
        foreach (self::bundledMods() as $name => $zip) {
            array_push($installed, ...$this->installModArchive($server, $zip, "$name.zip", keepSettings: true));
        }

        return $installed;
    }

    /**
     * Which of the given mods are installed (have a folder in the mods directory).
     *
     * @param  list<string>  $names
     * @return list<string>
     */
    public function installedModsOf(Server $server, array $names): array
    {
        $ue4ss = $this->ue4ss($server);
        if (!$ue4ss['installed']) {
            return [];
        }

        $folders = collect($this->listDirectory($server, $ue4ss['mods']))->where('directory', true)->pluck('name')->all();

        return array_values(array_filter($names, fn (string $name) => in_array($name, $folders, true)));
    }

    /** A mod's config.lua, or null when it has none. */
    public function modConfig(Server $server, string $mod): ?string
    {
        $this->assertModName($mod);

        return $this->read($server, $this->ue4ss($server)['mods'] . "/$mod/config.lua");
    }

    public function writeModConfig(Server $server, string $mod, string $contents): void
    {
        $this->assertModName($mod);

        $this->write($server, $this->ue4ss($server)['mods'] . "/$mod/config.lua", $contents);
    }

    private function modList(Server $server, string $modsDir): ModList
    {
        return ModList::parse($this->read($server, "$modsDir/mods.txt"), $this->read($server, "$modsDir/mods.json"));
    }

    private function saveModList(Server $server, string $modsDir, ModList $list): void
    {
        $this->files($server)->putContent("$modsDir/mods.txt", $list->renderTxt());

        if ($list->hasJson()) {
            $this->files($server)->putContent("$modsDir/mods.json", (string) $list->renderJson());
        }
    }

    private function assertModName(string $name): void
    {
        if ($name === '' || $name !== ModArchive::sanitizeName($name) || in_array(strtolower($name), ['shared', 'mods'], true)) {
            throw new RuntimeException('Invalid mod name.');
        }
    }

    // ------------------------------------------------------------------ helpers

    // ------------------------------------------------------------------ admin console

    /** Folder of the PelicanConsole mod, or null when it is not installed. */
    public function consoleModDir(Server $server): ?string
    {
        $ue4ss = $this->ue4ss($server);
        if (!$ue4ss['installed']) {
            return null;
        }

        $exists = collect($this->listDirectory($server, $ue4ss['mods']))
            ->contains(fn (array $entry) => $entry['directory'] && $entry['name'] === 'PelicanConsole');

        return $exists ? $ue4ss['mods'] . '/PelicanConsole' : null;
    }

    /**
     * Queue a command for the PelicanConsole mod. Returns true when the mod picked it up
     * within $waitSeconds (it checks once a second while the server runs).
     */
    public function sendConsoleCommand(Server $server, string $command, int $waitSeconds = 4): bool
    {
        $dir = $this->consoleModDir($server);
        if ($dir === null) {
            throw new RuntimeException('The PelicanConsole mod is not installed. Upload PelicanConsole.zip on the SCUM Mods page and restart the server.');
        }

        $command = ConsoleCommand::normalize($command);
        $path = "$dir/commands.txt";
        $this->write($server, $path, ConsoleCommand::append($this->read($server, $path), $command));

        for ($i = 0; $i < $waitSeconds * 2; $i++) {
            usleep(500_000);
            if ($this->read($server, $path) === null) {
                return true;
            }
        }

        return false;
    }

    /**
     * Run a PelicanConsole command and return what it wrote to console.log, waiting up to
     * $waitSeconds for a line matching $until.
     */
    public function runConsoleCommandAndRead(Server $server, string $command, string $until, int $waitSeconds = 8): string
    {
        $dir = $this->consoleModDir($server) ?? throw new RuntimeException('The PelicanConsole mod is not installed.');
        $before = strlen($this->read($server, "$dir/console.log") ?? '');

        if (!$this->sendConsoleCommand($server, $command)) {
            throw new RuntimeException('SCUM did not pick up the command. Is the server running with PelicanConsole enabled?');
        }

        $new = '';
        for ($i = 0; $i < $waitSeconds * 2; $i++) {
            $log = $this->read($server, "$dir/console.log") ?? '';
            $new = strlen($log) >= $before ? substr($log, $before) : $log;
            if (preg_match($until, $new)) {
                break;
            }
            usleep(500_000);
        }

        return $new;
    }

    /**
     * Add teleport destinations to PlayerTools' config.lua.
     *
     * @param  list<array{name: string, x: int, y: int, z: int}>  $destinations
     */
    public function addTeleportDestinations(Server $server, array $destinations, int $price): void
    {
        $this->updatePlayerTools($server, fn (array $config) => TeleportDestinations::add($config, $destinations, $price));
    }

    /** @param array{name: string, x: int, y: int, z: int} $zone */
    public function addKothZone(Server $server, array $zone, int $radius): void
    {
        $this->updatePlayerTools($server, fn (array $config) => TeleportDestinations::addZone($config, $zone, $radius));
    }

    /** @param \Closure(array<mixed>): array<mixed> $change */
    private function updatePlayerTools(Server $server, \Closure $change): void
    {
        if ($this->installedModsOf($server, ['PlayerTools']) === []) {
            throw new RuntimeException('The PlayerTools mod is not installed.');
        }

        $raw = $this->modConfig($server, 'PlayerTools');
        $config = $raw === null ? [] : LuaTable::parse($raw);
        $this->writeModConfig($server, 'PlayerTools', LuaTable::render(
            $change($config),
            "PlayerTools settings, written by SCUM Manager (SCUM Mod Settings page).\nYou can edit this file by hand; comments are not kept when the page saves it.",
        ));
    }

    /** @return array<string, string> SteamID => "Name (SteamID)" for players PlayerTools has seen */
    public function knownPlayers(Server $server): array
    {
        $ue4ss = $this->ue4ss($server);

        return $ue4ss['installed'] ? AdminCommands::knownPlayers($this->read($server, $ue4ss['mods'] . '/PlayerTools/players.tsv')) : [];
    }

    /**
     * Items for the dropdowns: the full list bundled with the plugin, or (if that file is
     * missing) the item types PelicanConsole has seen on this server.
     *
     * @return array<string, string> item => label
     */
    public function itemCatalog(Server $server): array
    {
        $bundled = AdminCommands::bundledItems();
        if ($bundled !== []) {
            return $bundled;
        }

        $ue4ss = $this->ue4ss($server);
        if (!$ue4ss['installed']) {
            return [];
        }

        return cache()->remember("scum-manager.items.$server->uuid", 120, fn () => AdminCommands::itemCatalog(
            $this->read($server, $ue4ss['mods'] . '/PelicanConsole/items.txt'),
        ));
    }

    /** The newest player reports from PlayerTools' reports.log, newest first. */
    public function playerReports(Server $server, int $lines = 30): string
    {
        $path = $this->reportsLogPath($server);

        return $path === null ? '' : $this->newestFirst($this->tailOf($server, $path, $lines));
    }

    /** Where PlayerTools writes player reports, or null without UE4SS. */
    public function reportsLogPath(Server $server): ?string
    {
        $ue4ss = $this->ue4ss($server);

        return $ue4ss['installed'] ? $ue4ss['mods'] . '/PlayerTools/reports.log' : null;
    }

    /** The last lines of a file on the server ('' when it does not exist). */
    public function tailOf(Server $server, string $path, int $lines): string
    {
        return ConsoleCommand::tail($this->read($server, $path), $lines);
    }

    public function newestFirst(string $log): string
    {
        return $log === '' ? '' : implode("\n", array_reverse(explode("\n", $log)));
    }

    /** The end of PelicanConsole's console.log (command results and mod messages). */
    public function consoleOutput(Server $server, int $lines = 60): string
    {
        $dir = $this->consoleModDir($server);

        return $dir === null ? '' : ConsoleCommand::tail($this->read($server, "$dir/console.log"), $lines);
    }

    private function files(Server $server): DaemonFileRepository
    {
        return app(DaemonFileRepository::class)->setServer($server);
    }

    private function daemon(Server $server): DaemonServerRepository
    {
        return app(DaemonServerRepository::class)->setServer($server);
    }
}
