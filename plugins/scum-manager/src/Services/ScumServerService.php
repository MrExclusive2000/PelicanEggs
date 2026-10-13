<?php

namespace MrExclusive\ScumManager\Services;

use App\Enums\ContainerStatus;
use App\Facades\Activity;
use App\Models\Server;
use App\Repositories\Daemon\DaemonFileRepository;
use App\Repositories\Daemon\DaemonServerRepository;
use Illuminate\Contracts\Filesystem\FileNotFoundException;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use MrExclusive\ScumManager\Support\AdminCommands;
use MrExclusive\ScumManager\Support\ConsoleCommand;
use MrExclusive\ScumManager\Support\LuaTable;
use MrExclusive\ScumManager\Support\TeleportDestinations;
use MrExclusive\ScumManager\Support\ModArchive;
use MrExclusive\ScumManager\Support\ModList;
use MrExclusive\ScumManager\Support\ModManifest;
use MrExclusive\ScumManager\Support\OnlinePlayers;
use MrExclusive\ScumManager\Support\PlayerDirectory;
use MrExclusive\ScumManager\Support\SaveDatabase;
use Throwable;
use MrExclusive\ScumManager\Support\Ue4ssSettings;
use RuntimeException;
use MrExclusive\ScumManager\Support\Brand;

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
            $this->installLatestMods($server);
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

    /** Exception code: an update from the source failed after some of the mod's files were written. */
    private const PARTLY_INSTALLED = 2;

    /** Where the latest mod zips and manifest.json are published, or null to use the bundled copies only. */
    public function modSource(): ?string
    {
        $source = config('scum-manager.mods_source');

        return filled($source) ? rtrim(trim($source), '/') : null;
    }

    /**
     * The published manifest (cached for five minutes unless $fresh).
     *
     * @return array{manager: ?string, mods: array<string, array{file: string, build: string, sha256: string, bytes: int}>}
     */
    public function latestModManifest(bool $fresh = false): array
    {
        $source = $this->modSource() ?? throw new RuntimeException('No mod source is set.');
        $key = 'scum-manager:mod-manifest:' . sha1($source);

        if (!$fresh && is_array($cached = Cache::get($key))) {
            if (isset($cached['error'])) {
                // A recent attempt failed: do not make every page load wait on GitHub again.
                throw new RuntimeException($cached['error']);
            }

            return $cached;
        }

        try {
            $manifest = ModManifest::parse(
                Http::timeout(15)->connectTimeout(5)->throw()->get(ModManifest::url($source, 'manifest.json'))->body()
            );
        } catch (Throwable $exception) {
            Cache::put($key, ['error' => $exception->getMessage()], 120);

            throw $exception;
        }

        Cache::put($key, $manifest, 300);

        return $manifest;
    }

    /** @return array<string, array{file: string, build: string, sha256: string, bytes: int}> builds of the bundled zips */
    public static function bundledBuilds(): array
    {
        $path = dirname(__DIR__, 2) . '/resources/mods/manifest.json';
        try {
            return is_file($path) ? ModManifest::parse((string) file_get_contents($path))['mods'] : [];
        } catch (Throwable) {
            return [];
        }
    }

    /** This plugin's version, from plugin.json. */
    public static function managerVersion(): string
    {
        $plugin = json_decode((string) @file_get_contents(dirname(__DIR__, 2) . '/plugin.json'), true);

        return is_array($plugin) && is_string($plugin['version'] ?? null) ? $plugin['version'] : '0';
    }

    /** The build an installed mod came from, or null when unknown (installed by hand or before builds were recorded). */
    public function installedBuild(Server $server, string $mod): ?string
    {
        $this->assertModName($mod);
        try {
            $build = $this->read($server, $this->ue4ss($server)['mods'] . "/$mod/" . ModManifest::BUILD_FILE);
        } catch (Throwable) {
            return null; // files briefly out of reach: shown as unknown
        }

        return $build === null ? null : (trim($build) ?: null);
    }

    private function writeBuild(Server $server, string $mod, string $build): void
    {
        $this->files($server)->putContent($this->ue4ss($server)['mods'] . "/$mod/" . ModManifest::BUILD_FILE, $build . "\n");
    }

    /**
     * Install or update our mods from the published source (GitHub), falling back to the copies
     * bundled with the plugin. Settings (config.lua) are kept. The probe is only updated where
     * it is already installed.
     *
     * @return array{installed: list<string>, fromSource: list<string>, notes: list<string>, manager: ?string}
     */
    public function installLatestMods(Server $server): array
    {
        $wanted = array_keys(self::bundledMods());
        $present = $this->installedModsOf($server, array_keys(Brand::MODS));
        foreach ($present as $mod) {
            if (!in_array($mod, $wanted, true)) {
                $wanted[] = $mod;
            }
        }

        $notes = [];
        $latest = null;
        if ($this->modSource() !== null) {
            try {
                $latest = $this->latestModManifest(fresh: true);
            } catch (Throwable $exception) {
                report($exception);
                $notes[] = 'The latest versions could not be fetched (' . $exception->getMessage() . '). Try again in a few minutes.';
            }
        }

        $bundled = self::bundledMods();
        $bundledBuilds = self::bundledBuilds();
        $installed = [];
        $fromSource = [];

        foreach ($wanted as $name) {
            $entry = $latest['mods'][$name] ?? null;
            if ($entry !== null) {
                try {
                    $this->installFromSource($server, $name, $entry);
                    $installed[] = $name;
                    $fromSource[] = $name;
                    continue;
                } catch (Throwable $exception) {
                    report($exception);
                    $notes[] = Brand::mod($name) . ': ' . $exception->getMessage();
                    if ($exception->getCode() === self::PARTLY_INSTALLED) {
                        continue; // neither kept nor replaced by an older copy: the note asks for a retry
                    }
                }
            }

            // The bundled copy can be older than one installed from the source earlier, so with a
            // source set it only fills in mods that are missing.
            $isPresent = in_array($name, $present, true);
            if (!isset($bundled[$name]) || ($isPresent && $this->modSource() !== null)) {
                if ($isPresent) {
                    $notes[] = Brand::mod($name) . ': the installed version was kept.';
                }
                continue;
            }
            array_push($installed, ...$this->installModArchive($server, $bundled[$name], "$name.zip", keepSettings: true));
            if (isset($bundledBuilds[$name])) {
                $this->writeBuild($server, $name, $bundledBuilds[$name]['build']);
            }
        }

        return [
            'installed' => array_values(array_unique($installed)),
            'fromSource' => $fromSource,
            'notes' => $notes,
            'manager' => ModManifest::isNewer($latest['manager'] ?? null, self::managerVersion()) ? $latest['manager'] : null,
        ];
    }

    /** @param array{file: string, build: string, sha256: string, bytes: int} $entry */
    private function installFromSource(Server $server, string $name, array $entry): void
    {
        if ($entry['bytes'] > (int) config('scum-manager.mod_upload_max_kb') * 1024) {
            throw new RuntimeException('The published zip is larger than the upload limit.');
        }

        $contents = Http::timeout(120)->connectTimeout(5)->throw()->get(ModManifest::url($this->modSource(), $entry['file']))->body();
        ModManifest::verify($contents, $entry, $name);

        $zip = tempnam(sys_get_temp_dir(), 'exclsv-mod-');
        try {
            file_put_contents($zip, $contents);
            $this->installModArchive($server, $zip, $entry['file'], keepSettings: true);
        } catch (Throwable $exception) {
            throw new RuntimeException('was only partly updated (' . $exception->getMessage() . '). Press "Install / update our mods" again before restarting.', self::PARTLY_INSTALLED, $exception);
        } finally {
            @unlink($zip);
        }

        $this->writeBuild($server, $name, $entry['build']);
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

    /** Keep a mod's current config.lua next to it before an import replaces it; returns the file name. */
    public function backupModConfig(Server $server, string $mod, string $contents): string
    {
        $this->assertModName($mod);
        $name = 'config.before-import-' . now()->format('Ymd-His') . '.lua';
        $this->write($server, $this->ue4ss($server)['mods'] . "/$mod/$name", $contents);

        return $name;
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
            throw new RuntimeException('The ' . Brand::mod('PelicanConsole') . ' mod is not installed. Install it on the ' . Brand::PAGE_MODS . ' page ("Install our mods") and restart the server.');
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
        $dir = $this->consoleModDir($server) ?? throw new RuntimeException('The ' . Brand::mod('PelicanConsole') . ' mod is not installed.');
        $before = strlen($this->read($server, "$dir/console.log") ?? '');

        if (!$this->sendConsoleCommand($server, $command)) {
            throw new RuntimeException('SCUM did not pick up the command. Is the server running with ' . Brand::mod('PelicanConsole') . ' enabled?');
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
            throw new RuntimeException('The ' . Brand::mod('PlayerTools') . ' mod is not installed.');
        }

        $raw = $this->modConfig($server, 'PlayerTools');
        $config = $raw === null ? [] : LuaTable::parse($raw);
        $this->writeModConfig($server, 'PlayerTools', LuaTable::render(
            $change($config),
            Brand::mod('PlayerTools') . " settings, written by " . Brand::MANAGER . " (" . Brand::PAGE_MOD_SETTINGS . " page).\nYou can edit this file by hand; comments are not kept when the page saves it.",
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

    /** Who is online and where, from PlayerTools' online.tsv (empty when it is not current). */
    public function onlinePlayers(Server $server): array
    {
        $ue4ss = $this->ue4ss($server);

        return OnlinePlayers::parse($ue4ss['installed'] ? $this->read($server, $ue4ss['mods'] . '/PlayerTools/online.tsv') : null, time());
    }

    /** Where SCUM keeps its save database (relative to the server root). */
    public const SAVE_DIR = 'SCUM/Saved/SaveFiles';

    /**
     * Copy SCUM's save database (SCUM.db, plus SCUM.db-wal with the newest changes when it
     * exists) into a private temporary folder on the panel. Returns the copy's path; remove it
     * with removeSaveDatabaseCopy(). The live file is only read.
     */
    public function copySaveDatabase(Server $server): string
    {
        $max = (int) config('scum-manager.save_db_max_mb', 2048) * 1024 * 1024;
        $dir = sys_get_temp_dir() . '/exclsv-db-' . bin2hex(random_bytes(8));
        if (!mkdir($dir, 0700)) {
            throw new RuntimeException('Could not create a temporary folder for the save database.');
        }

        try {
            foreach (['SCUM.db' => true, 'SCUM.db-wal' => false] as $file => $required) {
                $target = "$dir/$file";
                $response = $this->files($server)->getHttpClient()
                    ->timeout(900)
                    ->withOptions([
                        'sink' => $target,
                        'on_headers' => function ($response) use ($max, $file) {
                            if ((int) $response->getHeaderLine('Content-Length') > $max) {
                                throw new RuntimeException("$file is larger than the " . intdiv($max, 1024 * 1024) . ' MB limit (SCUM_MANAGER_SAVE_DB_MAX_MB).');
                            }
                        },
                    ])
                    ->get("/api/servers/$server->uuid/files/contents", ['file' => self::SAVE_DIR . "/$file"]);

                if ($response->status() === 404 && !$required) {
                    @unlink($target);
                    continue;
                }
                if (!$response->successful()) {
                    throw new RuntimeException($response->status() === 404
                        ? 'SCUM.db was not found in ' . self::SAVE_DIR . '. Has the server been started at least once?'
                        : "Could not read $file (HTTP {$response->status()}).");
                }
            }
        } catch (\Throwable $exception) {
            $this->removeSaveDatabaseCopy("$dir/SCUM.db");

            throw $exception instanceof RuntimeException ? $exception : new RuntimeException('Could not copy SCUM.db: ' . $exception->getMessage(), 0, $exception);
        }

        return "$dir/SCUM.db";
    }

    /**
     * Balances, fame, squads, stats and inventories from SCUM's save database, read from a copy
     * and cached for five minutes (a failed read is remembered for two).
     *
     * @return array{players: array<string, array>, inventories: array<string, list<array>>, readAt: ?int, error: ?string}
     */
    public function saveData(Server $server, bool $fresh = false): array
    {
        $key = "scum-manager:save-data:$server->uuid";
        if (!$fresh && is_array($cached = Cache::get($key))) {
            return $cached;
        }

        $copy = null;
        try {
            $copy = $this->copySaveDatabase($server);
            $save = new SaveDatabase($copy);
            $players = $save->players();
            $inventories = [];
            foreach (array_slice($players, 0, 500, true) as $steamId => $player) {
                if ($player['prisonerId'] !== null) {
                    $inventories[(string) $steamId] = $save->inventory($player['prisonerId']);
                }
            }
            $data = ['players' => $players, 'inventories' => $inventories, 'bases' => $save->bases(), 'readAt' => time(), 'error' => null];
            Cache::put($key, $data, 300);
            Cache::forever("$key:last", $data);
        } catch (Throwable $exception) {
            report($exception);
            $data = ['players' => [], 'inventories' => [], 'bases' => [], 'readAt' => null, 'error' => $exception->getMessage()];
            Cache::put($key, $data, 120);
        } finally {
            if ($copy !== null) {
                $this->removeSaveDatabaseCopy($copy);
            }
        }

        return $data;
    }

    /**
     * The last save snapshot without reading the save: for page renders and polls, which must not
     * wait for a database copy. saveData() (on page open or Reload) refreshes it.
     *
     * @return array{players: array<string, array>, inventories: array<string, list<array>>, bases: list<array>, readAt: ?int, error: ?string}
     */
    public function saveSnapshot(Server $server): array
    {
        $key = "scum-manager:save-data:$server->uuid";
        $fresh = Cache::get($key);
        if (is_array($fresh) && $fresh['error'] === null) {
            return $fresh;
        }
        $last = Cache::get("$key:last");
        if (is_array($last)) {
            return $last;
        }

        return ['players' => [], 'inventories' => [], 'bases' => [], 'readAt' => null,
            'error' => is_array($fresh) ? $fresh['error'] : 'Not read yet: open the page again or press Reload save data.'];
    }

    public const SAVE_BACKUP_DIR = 'ExclsvBackups';

    /**
     * Save backups (SaveFiles/ExclsvBackups), newest first. The egg makes one on every start;
     * "Back up now" adds one while running.
     *
     * @return list<array{name: string, size: int, modified: string, wal: bool}>
     */
    public function saveBackups(Server $server): array
    {
        $entries = $this->listDirectory($server, self::SAVE_DIR . '/' . self::SAVE_BACKUP_DIR);
        $names = array_column($entries, 'name');
        $backups = [];
        foreach ($entries as $entry) {
            if (!$entry['directory'] && preg_match('/^SCUM-[\w-]+\.db$/', $entry['name'])) {
                $backups[] = ['name' => $entry['name'], 'size' => $entry['size'], 'modified' => $entry['modified'], 'wal' => in_array($entry['name'] . '-wal', $names, true)];
            }
        }
        usort($backups, fn (array $a, array $b) => strtotime($b['modified'] ?: '0') <=> strtotime($a['modified'] ?: '0'));

        return $backups;
    }

    /** Copy the live save into the backups folder now. Returns the backup's name. */
    public function backupSaveNow(Server $server): string
    {
        $dir = self::SAVE_DIR;
        $names = array_column($this->listDirectory($server, $dir), 'name');
        if (!in_array('SCUM.db', $names, true)) {
            throw new RuntimeException('There is no SCUM.db yet: start the server once first.');
        }
        if (!in_array(self::SAVE_BACKUP_DIR, $names, true)) {
            $this->files($server)->createDirectory(self::SAVE_BACKUP_DIR, $dir);
        }

        $name = 'SCUM-' . gmdate('Y-m-d-Hi') . '-manual.db';
        $this->files($server)->renameFiles($dir, [['from' => $this->copyInPlace($server, $dir, 'SCUM.db'), 'to' => self::SAVE_BACKUP_DIR . "/$name"]]);
        if (in_array('SCUM.db-wal', $names, true)) {
            $this->files($server)->renameFiles($dir, [['from' => $this->copyInPlace($server, $dir, 'SCUM.db-wal'), 'to' => self::SAVE_BACKUP_DIR . "/$name-wal"]]);
        }
        Activity::event('server:file.copy')->property('file', "$dir/SCUM.db")->property('to', self::SAVE_BACKUP_DIR . "/$name")->log();

        return $name;
    }

    /**
     * Put a backup back as the live save. The server must be stopped. The current save is kept
     * as SCUM-before-restore-<time>.db in the backups folder.
     */
    public function restoreSave(Server $server, string $backup): void
    {
        if (!$this->isStopped($server)) {
            throw new RuntimeException('Stop the server first: SCUM keeps the save open while it runs.');
        }
        $dir = self::SAVE_DIR;
        $backups = self::SAVE_BACKUP_DIR;
        $available = array_column($this->saveBackups($server), null, 'name');
        if (!preg_match('/^SCUM-[\w-]+\.db$/', $backup) || !isset($available[$backup])) {
            throw new RuntimeException('That backup does not exist.');
        }

        // 1. Copies of the backup, made first so a failure leaves the live save untouched.
        $copy = $this->copyInPlace($server, "$dir/$backups", $backup);
        $walCopy = $available[$backup]['wal'] ? $this->copyInPlace($server, "$dir/$backups", "$backup-wal") : null;

        // 2. The current save (and its journal) moves aside.
        $live = array_column($this->listDirectory($server, $dir), 'name');
        $aside = 'SCUM-before-restore-' . gmdate('Y-m-d-His') . '.db';
        $moved = [];
        foreach (['SCUM.db' => $aside, 'SCUM.db-wal' => "$aside-wal", 'SCUM.db-shm' => null] as $file => $target) {
            if (!in_array($file, $live, true)) {
                continue;
            }
            if ($target === null) {
                $this->files($server)->deleteFiles($dir, [$file]); // shared-memory index, rebuilt by SQLite
                continue;
            }
            $this->files($server)->renameFiles($dir, [['from' => $file, 'to' => "$backups/$target"]]);
            $moved[$file] = "$backups/$target";
        }

        // 3. The copy becomes the live save; on failure the original goes back.
        try {
            $this->files($server)->renameFiles($dir, [['from' => "$backups/$copy", 'to' => 'SCUM.db']]);
            if ($walCopy !== null) {
                $this->files($server)->renameFiles($dir, [['from' => "$backups/$walCopy", 'to' => 'SCUM.db-wal']]);
            }
        } catch (Throwable $exception) {
            foreach ($moved as $file => $target) {
                try {
                    $this->files($server)->renameFiles($dir, [['from' => $target, 'to' => $file]]);
                } catch (Throwable) {
                    // reported below
                }
            }

            throw new RuntimeException("Restoring failed ({$exception->getMessage()}). The previous save was put back; if SCUM.db is missing, rename $backups/$aside back to SCUM.db.", 0, $exception);
        }

        Cache::forget("scum-manager:save-data:$server->uuid");
        Activity::event('server:file.restore')->property('file', "$dir/SCUM.db")->property('from', "$backups/$backup")->log();
    }

    /** Copy a file next to itself (Wings picks the name) and return the copy's name. */
    private function copyInPlace(Server $server, string $dir, string $file): string
    {
        $before = array_column($this->listDirectory($server, $dir), 'name');
        $this->files($server)->copyFile("$dir/$file");
        // Wings names copies "<name> copy..."; SQLite may add journal files meanwhile, so only those count.
        $new = array_values(array_filter(
            array_diff(array_column($this->listDirectory($server, $dir), 'name'), $before),
            fn (string $name) => str_contains(strtolower($name), 'copy'),
        ));
        if (count($new) !== 1) {
            throw new RuntimeException("Copying $file did not produce exactly one new file.");
        }

        return $new[0];
    }

    /**
     * The outposts on this server, from PlayerTools' teleport destinations named after their
     * sectors (A0, B4, C2, Z3, as "Add outposts as teleports" creates them); all destinations
     * when none are named that way.
     *
     * @return list<array{name: string, x: float, y: float}>
     */
    public function outposts(Server $server): array
    {
        try {
            $config = LuaTable::parse($this->modConfig($server, 'PlayerTools') ?? 'return {}');
        } catch (Throwable) {
            return [];
        }
        $places = [];
        foreach ((array) ($config['teleports']['locations'] ?? []) as $place) {
            if (is_array($place) && is_numeric($place['x'] ?? null) && is_numeric($place['y'] ?? null)) {
                $places[] = ['name' => strtoupper((string) ($place['name'] ?? '?')), 'x' => (float) $place['x'], 'y' => (float) $place['y']];
            }
        }
        $outposts = array_values(array_filter($places, fn (array $p) => in_array($p['name'], ['A0', 'B4', 'C2', 'Z3'], true)));

        return $outposts !== [] ? $outposts : $places;
    }

    /** Folder in the server's files for panel-side extras such as the map picture. */
    public const EXTRAS_DIR = 'ExclsvSCUM';

    private const MAP_TYPES = ['webp' => 'image/webp', 'png' => 'image/png', 'jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg'];

    /** Map pictures are scaled down to this many pixels square. */
    private const MAP_PIXELS = 1024;

    /** Largest picture kept as it is when the panel cannot scale pictures. */
    private const MAP_MAX_BYTES = 700 * 1024;

    /** Store a picture of SCUM's map (shown under the World page grid). */
    public function saveMapPicture(Server $server, string $contents, string $extension): void
    {
        $extension = strtolower($extension);
        if (!isset(self::MAP_TYPES[$extension])) {
            throw new RuntimeException('Use a .webp, .png or .jpg picture.');
        }
        $info = @getimagesizefromstring($contents);
        if ($info === false) {
            throw new RuntimeException('That file is not a picture.');
        }
        // The page carries the picture inline, so keep it small: 1024 px is plenty for the map.
        if (function_exists('imagecreatefromstring') && ($image = @imagecreatefromstring($contents)) !== false) {
            $scaled = imagescale($image, min(self::MAP_PIXELS, imagesx($image)), min(self::MAP_PIXELS, imagesy($image)));
            ob_start();
            imagejpeg($scaled ?: $image, null, 82);
            $contents = (string) ob_get_clean();
            $extension = 'jpg';
        } elseif (strlen($contents) > self::MAP_MAX_BYTES) {
            throw new RuntimeException('This panel cannot shrink pictures (no GD), so use one under ' . intdiv(self::MAP_MAX_BYTES, 1024) . ' KB, e.g. 1024 x 1024 px.');
        }
        if (!in_array(self::EXTRAS_DIR, array_column($this->listDirectory($server, '/'), 'name'), true)) {
            $this->files($server)->createDirectory(self::EXTRAS_DIR, '/');
        }
        $this->removeMapPicture($server);
        $this->files($server)->putContent(self::EXTRAS_DIR . "/map.$extension", $contents);
        Cache::forget("scum-manager:map-picture:$server->uuid");
    }

    public function removeMapPicture(Server $server): void
    {
        $existing = array_column($this->listDirectory($server, self::EXTRAS_DIR), 'name');
        $old = array_values(array_filter($existing, fn (string $name) => preg_match('/^map\.(webp|png|jpe?g)$/', $name)));
        if ($old !== []) {
            $this->files($server)->deleteFiles(self::EXTRAS_DIR, $old);
        }
        Cache::forget("scum-manager:map-picture:$server->uuid");
    }

    /** The map picture as a data: URI for the World page, or null when none is stored (cached for an hour). */
    public function mapPicture(Server $server): ?string
    {
        return Cache::remember("scum-manager:map-picture:$server->uuid", 3600, function () use ($server) {
            foreach (array_column($this->listDirectory($server, self::EXTRAS_DIR), 'name') as $name) {
                if (preg_match('/^map\.(webp|png|jpe?g)$/', $name, $match)) {
                    $contents = $this->read($server, self::EXTRAS_DIR . "/$name");

                    return $contents === null ? null : 'data:' . self::MAP_TYPES[$match[1]] . ';base64,' . base64_encode($contents);
                }
            }

            return null;
        });
    }

    public function removeSaveDatabaseCopy(string $path): void
    {
        $dir = dirname($path);
        if (!str_starts_with(basename($dir), 'exclsv-db-')) {
            return; // only ever remove our own temporary folders
        }
        foreach (glob("$dir/*") ?: [] as $file) {
            @unlink($file);
        }
        @rmdir($dir);
    }

    /** Everything known about every player, from all files that mention them (see PlayerDirectory). */
    public function playerDirectory(Server $server): array
    {
        $ue4ss = $this->ue4ss($server);
        $mods = $ue4ss['installed'] ? $ue4ss['mods'] : null;

        $lists = [];
        foreach (array_keys(PlayerDirectory::LISTS) as $file) {
            $lists[$file] = $this->read($server, $this->configPath($file));
        }

        return PlayerDirectory::build(
            $mods === null ? null : $this->read($server, "$mods/PlayerTools/players.tsv"),
            $this->onlinePlayers($server)['players'],
            $lists,
            $mods === null ? null : $this->read($server, "$mods/ScumAntiCheat/offenses.txt"),
            $this->saveSnapshot($server)['players'],
        );
    }

    /** Add a player to, or remove them from, one of SCUM's player lists (e.g. BannedUsers.ini). */
    public function setPlayerListMembership(Server $server, string $file, string $steamId, bool $member): void
    {
        if (!array_key_exists($file, PlayerDirectory::LISTS)) {
            throw new RuntimeException('Unknown player list.');
        }
        $path = $this->configPath($file);
        $this->write($server, $path, PlayerDirectory::setMembership($this->read($server, $path), $steamId, $member));
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
