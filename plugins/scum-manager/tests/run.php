<?php

/*
 * Standalone tests for the panel-independent parts of the plugin.
 * Run with: php plugins/scum-manager/tests/run.php
 */

spl_autoload_register(function (string $class) {
    $prefix = 'MrExclusive\\ScumManager\\';
    if (str_starts_with($class, $prefix)) {
        require __DIR__ . '/../src/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
    }
});

use MrExclusive\ScumManager\Support\AdminCommands;
use MrExclusive\ScumManager\Support\ConsoleCommand;
use MrExclusive\ScumManager\Support\IniDocument;
use MrExclusive\ScumManager\Support\LuaTable;
use MrExclusive\ScumManager\Support\ModSettings;
use MrExclusive\ScumManager\Support\ModArchive;
use MrExclusive\ScumManager\Support\ModList;
use MrExclusive\ScumManager\Support\SettingLabel;
use MrExclusive\ScumManager\Support\SettingType;
use MrExclusive\ScumManager\Support\TeleportDestinations;

$failures = 0;
$count = 0;

function check(string $name, mixed $actual, mixed $expected): void
{
    global $failures, $count;
    $count++;
    if ($actual !== $expected) {
        $failures++;
        echo "FAIL: $name\n  expected: " . var_export($expected, true) . "\n  actual:   " . var_export($actual, true) . "\n";
    }
}

function throws(string $name, callable $fn, string $contains): void
{
    global $failures, $count;
    $count++;
    try {
        $fn();
        $failures++;
        echo "FAIL: $name (no exception)\n";
    } catch (Throwable $e) {
        if (!str_contains($e->getMessage(), $contains)) {
            $failures++;
            echo "FAIL: $name\n  message: {$e->getMessage()}\n";
        }
    }
}

// ---------------------------------------------------------------- IniDocument
$ini = "[General]\r\nscum.ServerName = My Server\r\nscum.ServerPlaystyle=PVP\r\n; a comment\r\nscum.MaxPing=-1\r\n\r\n[World]\r\nscum.PuppetHealthMultiplier=1.000000\r\nscum.FlagOvertakeDuration=24:00:00\r\n";
$doc = IniDocument::parse($ini);

check('ini: sections', $doc->sections(), ['General', 'World']);
check('ini: entry count', count($doc->entries()), 5);
check('ini: get spaced value', $doc->get('General', 'scum.ServerName'), 'My Server');
check('ini: get compact value', $doc->get('General', 'scum.ServerPlaystyle'), 'PVP');
check('ini: untouched render is byte-identical', $doc->render(), $ini);

$doc->set('World', 'scum.PuppetHealthMultiplier', '2.500000');
$doc->set('General', 'scum.ServerName', 'Renamed');
check('ini: set keeps spacing, CRLF and everything else',
    $doc->render(),
    "[General]\r\nscum.ServerName = Renamed\r\nscum.ServerPlaystyle=PVP\r\n; a comment\r\nscum.MaxPing=-1\r\n\r\n[World]\r\nscum.PuppetHealthMultiplier=2.500000\r\nscum.FlagOvertakeDuration=24:00:00\r\n");

$doc->set('General', 'scum.NewKey', 'True');
check('ini: new key goes at end of its section, before blank line',
    $doc->render(),
    "[General]\r\nscum.ServerName = Renamed\r\nscum.ServerPlaystyle=PVP\r\n; a comment\r\nscum.MaxPing=-1\r\nscum.NewKey=True\r\n\r\n[World]\r\nscum.PuppetHealthMultiplier=2.500000\r\nscum.FlagOvertakeDuration=24:00:00\r\n");

$doc->set('Damage', 'scum.HumanToHumanDamageMultiplier', '1.000000');
check('ini: new section appended', str_ends_with($doc->render(), "\r\n\r\n[Damage]\r\nscum.HumanToHumanDamageMultiplier=1.000000\r\n"), true);
throws('ini: newline in value rejected', fn () => $doc->set('General', 'scum.ServerName', "x\n[Hack]"), 'Line breaks');

$dup = IniDocument::parse("[General]\nscum.A=1\nscum.A=2\n");
check('ini: duplicate key reports first', $dup->entries(), [['section' => 'General', 'key' => 'scum.A', 'value' => '1']]);

$bom = IniDocument::parse("\xEF\xBB\xBF[General]\nscum.A=1\n");
$bom->set('General', 'scum.A', '5');
check('ini: utf-8 BOM preserved', $bom->render(), "\xEF\xBB\xBF[General]\nscum.A=5\n");

$utf16 = "\xFF\xFE" . mb_convert_encoding("[General]\r\nscum.ServerName=Zürich\r\n", 'UTF-16LE', 'UTF-8');
$u = IniDocument::parse($utf16);
check('ini: utf-16 decoded', $u->get('General', 'scum.ServerName'), 'Zürich');
check('ini: utf-16 encoding detected', $u->encoding(), IniDocument::ENCODING_UTF16LE);
check('ini: utf-16 round trip', $u->render(), $utf16);

$empty = IniDocument::parse('');
$empty->set('General', 'scum.A', '1');
check('ini: empty file', $empty->render(), "[General]\nscum.A=1\n");

$noTrailing = IniDocument::parse("[General]\nscum.A=1");
$noTrailing->set('General', 'scum.A', '2');
check('ini: no trailing newline kept', $noTrailing->render(), "[General]\nscum.A=2");

// ---------------------------------------------------------------- SettingType
check('type: True', SettingType::infer('True'), SettingType::Toggle);
check('type: false', SettingType::infer('false'), SettingType::Toggle);
check('type: -1', SettingType::infer('-1'), SettingType::Integer);
check('type: 800', SettingType::infer('800'), SettingType::Integer);
check('type: float', SettingType::infer('-1.000000'), SettingType::Decimal);
check('type: duration', SettingType::infer('24:00:00'), SettingType::Duration);
check('type: gold', SettingType::infer('2g'), SettingType::Gold);
check('type: text', SettingType::infer('Welcome!'), SettingType::Text);
check('type: empty is text', SettingType::infer(''), SettingType::Text);

check('toIni: toggle', SettingType::Toggle->toIni(true, 'False'), 'True');
check('toIni: decimals follow original', SettingType::Decimal->toIni('2', '1.000000'), '2.000000');
check('toIni: decimals 2', SettingType::Decimal->toIni('0.5', '1.25'), '0.50');
check('toIni: integer', SettingType::Integer->toIni('12', '10'), '12');
check('toIni: text strips newlines', SettingType::Text->toIni("a\nb", 'x'), 'a b');
check('toState: toggle', SettingType::Toggle->toState('True'), true);

check('label: simple', SettingLabel::fromKey('scum.PuppetHealthMultiplier'), 'Puppet Health Multiplier');
check('label: acronym', SettingLabel::fromKey('scum.MaxAllowedNPCsInWorld'), 'Max Allowed NPCs In World');
check('label: digits', SettingLabel::fromKey('scum.Respawn2Price'), 'Respawn 2 Price');
check('label: underscore', SettingLabel::fromKey('scum.MaxAllowedApexFacilityKeycards_PoliceStation'), 'Max Allowed Apex Facility Keycards Police Station');

// ---------------------------------------------------------------- ModList
$modsTxt = "CheatManagerEnablerMod : 1\r\nConsoleCommandsMod : 1\r\nSplitScreenMod : 0\r\nBPModLoaderMod : 1\r\n\r\n\r\n\r\n\r\n; Built-in keybinds, do not move up!\r\nKeybinds : 1\r\n";
$modsJson = json_encode([
    ['mod_name' => 'CheatManagerEnablerMod', 'mod_enabled' => true],
    ['mod_name' => 'SplitScreenMod', 'mod_enabled' => false],
    ['mod_name' => 'Keybinds', 'mod_enabled' => true],
], JSON_PRETTY_PRINT);

$list = ModList::parse($modsTxt, $modsJson);
check('mods: parse', $list->all(), ['CheatManagerEnablerMod' => true, 'ConsoleCommandsMod' => true, 'SplitScreenMod' => false, 'BPModLoaderMod' => true, 'Keybinds' => true]);
check('mods: isEnabled', $list->isEnabled('SplitScreenMod'), false);
check('mods: unknown', $list->isEnabled('Nope'), null);

$list->setEnabled('SplitScreenMod', true);
$list->setEnabled('MyMod', true);
check('mods: new mod inserted above keybinds block',
    $list->renderTxt(),
    "CheatManagerEnablerMod : 1\r\nConsoleCommandsMod : 1\r\nSplitScreenMod : 1\r\nBPModLoaderMod : 1\r\nMyMod : 1\r\n\r\n\r\n\r\n\r\n; Built-in keybinds, do not move up!\r\nKeybinds : 1\r\n");
$json = json_decode($list->renderJson(), true);
check('mods: json updated', array_column($json, 'mod_enabled', 'mod_name'), ['CheatManagerEnablerMod' => true, 'SplitScreenMod' => true, 'MyMod' => true, 'Keybinds' => true]);
check('mods: json keybinds last', end($json)['mod_name'], 'Keybinds');

$list->remove('MyMod');
check('mods: removed', $list->isListed('MyMod'), false);
check('mods: removed from json', in_array('MyMod', array_column(json_decode($list->renderJson(), true), 'mod_name'), true), false);

$plain = ModList::parse("ModA : 1\n", null);
$plain->setEnabled('ModB', false);
check('mods: no keybinds appends', $plain->renderTxt(), "ModA : 1\nModB : 0\n");
check('mods: no json stays null', $plain->renderJson(), null);

$fresh = ModList::parse(null);
$fresh->setEnabled('ModA', true);
check('mods: missing file', $fresh->renderTxt(), "ModA : 1\n");

// ---------------------------------------------------------------- Ue4ssSettings
// Excerpt of the UE4SS-settings.ini shipped in UE4SS v3.0.1 experimental (CRLF, double spaces kept).
$ue4ssIni = "[Debug]\r\nConsoleEnabled = 0\r\nGuiConsoleEnabled = 1\r\nGuiConsoleVisible = 1\r\n\r\n[Hooks]\r\nHookProcessInternal = 1\r\nHookBeginPlay  = 1\r\nHookCallFunctionByNameWithArguments = 1\r\nHookEngineTick = 1\r\nEngineTickResolveMethod = Scan\r\nHookUObjectProcessEvent = 1\r\n\r\n[CrashDump]\r\nEnableDumping = 1\r\n";
$safe = IniDocument::parse(\MrExclusive\ScumManager\Support\Ue4ssSettings::applyScumDefaults($ue4ssIni));
check('ue4ss: process internal off', $safe->get('Hooks', 'HookProcessInternal'), '0');
check('ue4ss: begin play off (double-spaced key)', $safe->get('Hooks', 'HookBeginPlay'), '0');
check('ue4ss: engine tick kept', $safe->get('Hooks', 'HookEngineTick'), '1');
check('ue4ss: call function kept', $safe->get('Hooks', 'HookCallFunctionByNameWithArguments'), '1');
check('ue4ss: process event off', $safe->get('Hooks', 'HookUObjectProcessEvent'), '0');
check('ue4ss: unrelated key untouched', $safe->get('Hooks', 'EngineTickResolveMethod'), 'Scan');
check('ue4ss: missing hook added', $safe->get('Hooks', 'HookUStructLink'), '0');
check('ue4ss: gui console off', $safe->get('Debug', 'GuiConsoleVisible'), '0');
check('ue4ss: other sections untouched', $safe->get('CrashDump', 'EnableDumping'), '1');
check('ue4ss: keeps CRLF and spacing', str_contains($safe->render(), "HookBeginPlay  = 0\r\n"), true);

// ---------------------------------------------------------------- ModArchive
$tmp = sys_get_temp_dir() . '/scum-manager-tests-' . getmypid();
@mkdir($tmp);

function makeZip(string $path, array $files): string
{
    $zip = new ZipArchive();
    $zip->open($path, ZipArchive::CREATE | ZipArchive::OVERWRITE);
    foreach ($files as $name => $contents) {
        $zip->addFromString($name, $contents);
    }
    $zip->close();

    return $path;
}

$a = ModArchive::open(makeZip("$tmp/a.zip", ['ue4ss/Mods/CoolMod/Scripts/main.lua' => 'print(1)', 'ue4ss/Mods/CoolMod/config.txt' => 'x', 'readme.txt' => 'hi']), 'a.zip', 1_000_000, 100);
check('archive: nested ue4ss layout', array_column($a->mods(), 'name'), ['CoolMod']);
check('archive: relative files', array_keys($a->mods()[0]['files']), ['Scripts/main.lua', 'config.txt']);
check('archive: type', $a->mods()[0]['type'], 'Lua');
check('archive: contents', $a->contents($a->mods()[0]['files']['Scripts/main.lua']), 'print(1)');
$a->close();

$b = ModArchive::open(makeZip("$tmp/RootMod-1.2.zip", ['Scripts/main.lua' => 'x', 'enabled.txt' => '']), 'RootMod-1.2.zip', 1_000_000, 100);
check('archive: root layout uses file name', array_column($b->mods(), 'name'), ['RootMod-1.2']);
$b->close();

$c = ModArchive::open(makeZip("$tmp/c.zip", ['One/Scripts/main.lua' => 'x', 'Two/dlls/main.dll' => 'y']), 'c.zip', 1_000_000, 100);
check('archive: two mods', array_column($c->mods(), 'type', 'name'), ['One' => 'Lua', 'Two' => 'C++']);
$c->close();

throws('archive: zip slip', fn () => ModArchive::open(makeZip("$tmp/d.zip", ['../../evil/Scripts/main.lua' => 'x']), 'd.zip', 1_000_000, 100), 'unsafe path');
throws('archive: no mod', fn () => ModArchive::open(makeZip("$tmp/e.zip", ['readme.txt' => 'x']), 'e.zip', 1_000_000, 100), 'No UE4SS mod');
throws('archive: too big', fn () => ModArchive::open(makeZip("$tmp/f.zip", ['M/Scripts/main.lua' => str_repeat('x', 2000)]), 'f.zip', 1000, 100), 'too large');
throws('archive: too many files', fn () => ModArchive::open(makeZip("$tmp/g.zip", ['M/Scripts/main.lua' => 'x', 'M/a' => 'a', 'M/b' => 'b']), 'g.zip', 1000, 2), 'more than 2');
throws('archive: not a zip', function () use ($tmp) {
    file_put_contents("$tmp/h.zip", 'not a zip');
    ModArchive::open("$tmp/h.zip", 'h.zip', 1000, 10);
}, 'not a valid zip');
check('archive: sanitize name', ModArchive::sanitizeName('..\\My Mod<script>.zip'), 'My Modscript');

array_map('unlink', glob("$tmp/*"));
rmdir($tmp);

// ---------------------------------------------------------------- ConsoleCommand
check('console: trims', ConsoleCommand::normalize("  Announce Hello \t"), 'Announce Hello');
check('console: keeps a leading #', ConsoleCommand::normalize('#ListPlayers'), '#ListPlayers');
throws('console: empty', fn () => ConsoleCommand::normalize('   '), 'Type a command');
throws('console: only #', fn () => ConsoleCommand::normalize('##'), 'Type a command');
throws('console: two lines', fn () => ConsoleCommand::normalize("ListPlayers\nShutdownServer"), 'one command');
throws('console: too long', fn () => ConsoleCommand::normalize(str_repeat('a', 501)), 'at most 500');
check('console: append to nothing', ConsoleCommand::append(null, 'ListPlayers'), "ListPlayers\n");
check('console: append after unterminated line', ConsoleCommand::append('Announce Hi', 'ListPlayers'), "Announce Hi\nListPlayers\n");
check('console: append after line', ConsoleCommand::append("Announce Hi\n", 'ListPlayers'), "Announce Hi\nListPlayers\n");
check('console: tail keeps the last lines', ConsoleCommand::tail("a\r\nb\n\nc\nd\n", 2), "c\nd");
check('console: tail of missing log', ConsoleCommand::tail(null), '');

// ---------------------------------------------------------------- LuaTable
$lua = <<<'LUA'
-- comment
--[[ block
comment ]]
return {
    name = "a \"quoted\" \\ value\n", other = 'single', long = [[raw
text]],
    n = -12, f = 1.5, e = 1e3, yes = true, no = false, gone = nil,
    list = { "x", 'y'; 3 },   -- trailing comment
    nested = { deep = { 1, 2 }, ["odd key"] = 4, [10] = "ten" },
    tuples = { { "bow", 150 }, { "1911", 150 } },
}
LUA;
$parsed = LuaTable::parse($lua);
check('lua: escaped string', $parsed['name'], "a \"quoted\" \\ value\n");
check('lua: single quotes', $parsed['other'], 'single');
check('lua: long string', $parsed['long'], 'raw' . "\n" . 'text');
check('lua: numbers', [$parsed['n'], $parsed['f'], $parsed['e']], [-12, 1.5, 1000.0]);
check('lua: booleans and nil', [$parsed['yes'], $parsed['no'], $parsed['gone']], [true, false, null]);
check('lua: list with ; separator', $parsed['list'], ['x', 'y', 3]);
check('lua: nested and bracket keys', $parsed['nested'], ['deep' => [1, 2], 'odd key' => 4, 10 => 'ten']);
check('lua: list of tuples', $parsed['tuples'], [['bow', 150], ['1911', 150]]);
check('lua: render round trip', LuaTable::parse(LuaTable::render($parsed, "header\nline two")), $parsed);
check('lua: header as comments', str_starts_with(LuaTable::render(['a' => 1], "x\ny"), "-- x\n-- y\nreturn {"), true);
check('lua: floats stay floats', LuaTable::render(['a' => 2.0, 'b' => 0.25, 'c' => 3]), "return {\n    a = 2.0,\n    b = 0.25,\n    c = 3,\n}\n");
throws('lua: no return', fn () => LuaTable::parse('{ a = 1 }'), 'does not start with "return"');
throws('lua: broken table', fn () => LuaTable::parse("return {\n a = 1\n b = 2 }"), 'line 3: Expected "," or "}"');
throws('lua: unfinished string', fn () => LuaTable::parse('return { a = "x }'), 'Unfinished string');
throws('lua: not a table', fn () => LuaTable::parse('return 5'), 'does not return a table');

// ---------------------------------------------------------------- ModSettings
foreach (array_keys(ModSettings::MODS) as $mod) {
    $config = LuaTable::parse(file_get_contents(__DIR__ . "/../../../mods/$mod/config.lua"));
    $flat = [];
    $walk = function (array $table, string $prefix) use (&$walk, &$flat) {
        foreach ($table as $key => $value) {
            $flat[] = $prefix . $key;
            if (is_array($value) && !array_is_list($value)) {
                $walk($value, $prefix . $key . '.');
            }
        }
    };
    $walk($config, '');
    $missing = array_values(array_diff(array_keys(ModSettings::fields($mod)), $flat));
    check("settings: every $mod field is in its config.lua", $missing, []);

    $state = ModSettings::toState($mod, $config);
    check("settings: $mod unchanged form changes nothing", ModSettings::apply($mod, $config, $state), $config);
}

$config = LuaTable::parse(file_get_contents(__DIR__ . '/../../../mods/PlayerTools/config.lua'));
$state = ModSettings::toState('PlayerTools', $config);
check('settings: lines become text', $state['PlayerTools__chatCommands__rules'], "No cheating or exploiting.\nRespect other players.");
check('settings: vote options become rows', $state['PlayerTools__voting__options'][0], ['name' => 'day', 'label' => 'make it daytime', 'command' => 'SetTime 10']);
$state['PlayerTools__afk__enabled'] = true;
$state['PlayerTools__afk__minutes'] = '25';
$state['PlayerTools__chatCommands__rules'] = "  Rule one \r\n\r\nRule two\n";
$state['PlayerTools__voting__options'] = [['name' => 'rain', 'label' => 'make it rain', 'command' => 'SetWeather 1'], ['name' => '', 'label' => '', 'command' => '']];
$state['PlayerTools__newPlayers__starterKitCommands'] = 'SpawnItem Water_05l 1 Location "{location}"';
$state['PlayerTools__unknown'] = 'ignored';
$updated = ModSettings::apply('PlayerTools', $config + ['custom' => 'kept'], $state);
check('settings: toggle', $updated['afk']['enabled'], true);
check('settings: number', $updated['afk']['minutes'], 25);
check('settings: lines trimmed, blanks dropped', $updated['chatCommands']['rules'], ['Rule one', 'Rule two']);
check('settings: empty rows dropped', $updated['voting']['options'], [['name' => 'rain', 'label' => 'make it rain', 'command' => 'SetWeather 1']]);
check('settings: quotes survive', LuaTable::parse(LuaTable::render($updated))['newPlayers']['starterKitCommands'], ['SpawnItem Water_05l 1 Location "{location}"']);
check('settings: unknown config keys kept', $updated['custom'], 'kept');

$config = LuaTable::parse(file_get_contents(__DIR__ . '/../../../mods/ScumAntiCheat/config.lua'));
$state = ModSettings::toState('ScumAntiCheat', $config);
check('settings: tuples become rows', $state['ScumAntiCheat__weaponMaxDistance'][0], ['c0' => 'bow', 'c1' => '150']);
$state['ScumAntiCheat__weaponMaxDistance'] = [['c0' => 'mosin', 'c1' => '600'], ['c0' => '1911', 'c1' => '150']];
$state['ScumAntiCheat__checks__aimSnap'] = false;
$updated = ModSettings::apply('ScumAntiCheat', $config, $state);
check('settings: rows become tuples, numbers only where numeric', $updated['weaponMaxDistance'], [['mosin', 600], ['1911', 150]]);
check('settings: nested toggle', [$updated['checks']['aimSnap'], $updated['checks']['speed']], [false, true]);

$state = ModSettings::toState('ServerMessages', LuaTable::parse(file_get_contents(__DIR__ . '/../../../mods/ServerMessages/config.lua')));
check('settings: number list as text', $state['ServerMessages__restartWarnings'], '30, 15, 5, 1');
$state['ServerMessages__restartWarnings'] = '10, 2';
$state['ServerMessages__restartTimes'] = "06:00\n18:00";
$updated = ModSettings::apply('ServerMessages', [], $state);
check('settings: number list', $updated['restartWarnings'], [10, 2]);
check('settings: missing config gets every field', $updated['restartTimes'], ['06:00', '18:00']);

// ---------------------------------------------------------------- AdminCommands
$options = AdminCommands::options();
check('commands: grouped', array_keys($options), ['Works any time', 'Works any time (experimental)', 'Needs an admin in game', 'Other']);
check('commands: experimental group', array_keys($options['Works any time (experimental)']), ['whereis', 'balance', 'teleportplayer', 'giveitem']);
check('commands: give item', AdminCommands::build('giveitem', ['giveitem__name' => 'Mr Exclusive', 'giveitem__item' => 'Water_05l', 'giveitem__amount' => '2']), 'GiveItem Mr Exclusive Water_05l 2');
check('commands: teleport player', AdminCommands::build('teleportplayer', ['teleportplayer__name' => 'Bob', 'teleportplayer__x' => '-100', 'teleportplayer__y' => '5', 'teleportplayer__z' => '300']), 'TeleportPlayer Bob -100 5 300');
check('commands: any-time ones are the ones the mod handles itself', array_keys($options['Works any time']), ['announce', 'listplayers', 'kick']);
check('commands: announce', AdminCommands::build('announce', ['announce__message' => '  Restart in 5 min ']), 'Announce Restart in 5 min');
check('commands: no fields', AdminCommands::build('listplayers', []), 'ListPlayers');
check('commands: kick by name with spaces', AdminCommands::build('kick', ['kick__name' => 'Mr Exclusive']), 'Kick Mr Exclusive');
check('commands: money', AdminCommands::build('money', ['money__steamId' => '76561198081802669', 'money__amount' => '-250']), 'ChangeCurrencyBalance Normal -250 76561198081802669');
check('commands: select value', AdminCommands::build('setweather', ['setweather__weather' => '0.5']), 'SetWeather 0.5');
check('commands: other commands\' fields ignored', AdminCommands::build('settime', ['settime__hour' => '12', 'announce__message' => 'x']), 'SetTime 12');
check('commands: custom', AdminCommands::build('custom', ['custom__command' => '#SpawnVehicle BPC_Dirtbike']), '#SpawnVehicle BPC_Dirtbike');
throws('commands: hour range', fn () => AdminCommands::build('settime', ['settime__hour' => '24']), 'from 0 to 23');
throws('commands: not a number', fn () => AdminCommands::build('settime', ['settime__hour' => '1e3']), 'whole number');
throws('commands: bad SteamID', fn () => AdminCommands::build('ban', ['ban__steamId' => '123']), 'SteamID64');
throws('commands: unknown weather', fn () => AdminCommands::build('setweather', ['setweather__weather' => '7']), 'Pick a Weather');
throws('commands: item without spaces', fn () => AdminCommands::build('spawnitem', ['spawnitem__item' => 'A B', 'spawnitem__amount' => '1']), 'cannot contain spaces');
throws('commands: missing field', fn () => AdminCommands::build('money', ['money__steamId' => '76561198081802669']), 'Amount is required');
throws('commands: one line only', fn () => AdminCommands::build('announce', ['announce__message' => "a\nShutdownServer"]), 'one line');
throws('commands: unknown command', fn () => AdminCommands::build('nope', []), 'Pick a command');
check('commands: known players from players.tsv', AdminCommands::knownPlayers("76561198000000002\tbob\t0\n76561198000000001\tAlice\t3\nbad line\n"),
    ['76561198000000001' => 'Alice (76561198000000001)', '76561198000000002' => 'bob (76561198000000002)']);
check('commands: no players file', AdminCommands::knownPlayers(null), []);
check('commands: item catalog with paths', AdminCommands::itemCatalog("BP_Water_05l_C\t/Game/ConZ_Files/Items/W/BP_Water_05l.BP_Water_05l_C\nBP_Apple_C\t\n"), ['BP_Apple_C' => 'Apple (BP_Apple_C)', 'BP_Water_05l_C' => 'Water 05l (BP_Water_05l_C)']);
check('commands: item catalog', AdminCommands::itemCatalog("BP_Water_05l_C\r\nBP_Apple_C\nbad name!\n\n"), ['BP_Apple_C' => 'Apple (BP_Apple_C)', 'BP_Water_05l_C' => 'Water 05l (BP_Water_05l_C)']);
check('commands: no item list yet', AdminCommands::itemCatalog(null), []);
$bundledItems = AdminCommands::bundledItems();
check('items: bundled list is complete', count($bundledItems) > 1400, true);
check('items: water bottle', $bundledItems['Water_05l'] ?? null, 'Water Bottle (Water_05l)');
check('items: bundled list parsing', AdminCommands::bundledItems('{"items":{"B_1":"Bee","bad id!":"x","A_1":"Ant"}}'), ['A_1' => 'Ant (A_1)', 'B_1' => 'Bee (B_1)']);
check('commands: spawn item with an ID', AdminCommands::build('spawnitem', ['spawnitem__item' => 'Water_05l', 'spawnitem__amount' => '2']), 'SpawnItem Water_05l 2');
$catalog = AdminCommands::itemCatalog("BP_Water_05l_C\nBP_Water_1l_C\nBP_Apple_C\nBP_Canned_Water_C\n");
check('items: search every word', MrExclusive\ScumManager\Support\ItemSelect::search($catalog, 'water 05'), ['BP_Water_05l_C' => 'Water 05l (BP_Water_05l_C)']);
check('items: search is case-insensitive', array_keys(MrExclusive\ScumManager\Support\ItemSelect::search($catalog, 'WATER')), ['BP_Canned_Water_C', 'BP_Water_05l_C', 'BP_Water_1l_C']);

$state = ModSettings::toState('PlayerTools', ['teleports' => ['locations' => [['name' => 'trader', 'x' => 1, 'y' => -2, 'z' => 3, 'price' => 50]]]]);
check('settings: teleport rows', $state['PlayerTools__teleports__locations'], [['name' => 'trader', 'x' => '1', 'y' => '-2', 'z' => '3', 'price' => '50']]);
check('settings: teleport numbers saved as numbers', ModSettings::apply('PlayerTools', [], $state)['teleports']['locations'], [['name' => 'trader', 'x' => 1, 'y' => -2, 'z' => 3, 'price' => 50]]);

// The page's defaults for a missing setting must match what the mod does without it.
$shipped = LuaTable::parse(file_get_contents(__DIR__ . '/../../../mods/PlayerTools/config.lua'));
$fromDefaults = ModSettings::apply('PlayerTools', [], ModSettings::toState('PlayerTools', []));
foreach (['welcomeBack', 'playtimeRewards', 'killStreaks', 'bounties', 'teleports', 'info', 'reports', 'featureTips', 'deathRecap', 'hotspots', 'manhunt', 'koth', 'itemRewards'] as $section) {
    // Same keys and values; the order of keys does not matter to Lua.
    check("settings: page defaults match shipped PlayerTools $section", $fromDefaults[$section] == $shipped[$section], true);
}

$state = ModSettings::toState('PlayerTools', []);
$state['PlayerTools__newPlayers__starterKitItems'] = [['item' => ' Water_05l ', 'amount' => '2'], ['item' => '', 'amount' => '']];
check('settings: starter kit items', ModSettings::apply('PlayerTools', [], $state)['newPlayers']['starterKitItems'], [['item' => 'Water_05l', 'amount' => 2]]);

// ---------------------------------------------------------------- TeleportDestinations
$output = "14:00:00 [PelicanConsole] 4 outpost(s) found, named by sector:\n14:00:00 [PelicanConsole] Outpost a0 at 250 900000 1020\n14:00:00 [PelicanConsole] Outpost b4 at -400250 600000 1020\n";
check('teleports: outposts parsed', TeleportDestinations::parseOutposts($output), [['name' => 'a0', 'x' => 250, 'y' => 900000, 'z' => 1020], ['name' => 'b4', 'x' => -400250, 'y' => 600000, 'z' => 1020]]);
check('teleports: where is', TeleportDestinations::parseWhereIs("x [PelicanConsole] Mr Exclusive is at -1 2 3\n", 'mr exclusive'), ['x' => -1, 'y' => 2, 'z' => 3]);
check('teleports: where is, unknown', TeleportDestinations::parseWhereIs('No online player matches', 'Bob'), null);
$config = ['teleports' => ['enabled' => true, 'locations' => [['name' => 'b4', 'x' => 0, 'y' => 0, 'z' => 0, 'price' => 1], ['name' => 'home', 'x' => 5, 'y' => 5, 'z' => 5, 'price' => 0]]]];
$updated = TeleportDestinations::add($config, TeleportDestinations::parseOutposts($output), 500);
check('teleports: same name replaced, others kept and added', array_column($updated['teleports']['locations'], 'name'), ['b4', 'home', 'a0']);
check('teleports: price and position', $updated['teleports']['locations'][0], ['name' => 'b4', 'x' => -400250, 'y' => 600000, 'z' => 1020, 'price' => 500]);
check('teleports: other settings kept', $updated['teleports']['enabled'], true);
check('teleports: works on an empty config', TeleportDestinations::add([], [['name' => 'Trader', 'x' => 1, 'y' => 2, 'z' => 3]], 0)['teleports']['locations'], [['name' => 'trader', 'x' => 1, 'y' => 2, 'z' => 3, 'price' => 0]]);
$zoned = TeleportDestinations::addZone(['koth' => ['enabled' => true, 'zones' => [['name' => 'hill', 'x' => 0, 'y' => 0, 'z' => 0, 'radius' => 50]]]], ['name' => 'Hill', 'x' => 1, 'y' => 2, 'z' => 3], 120);
check('zones: same name replaced', $zoned['koth']['zones'], [['name' => 'hill', 'x' => 1, 'y' => 2, 'z' => 3, 'radius' => 120]]);
check('zones: other koth settings kept', $zoned['koth']['enabled'], true);
throws('teleports: one-word names', fn () => TeleportDestinations::name('my base'), 'one word');
check('teleports: written config loads back', LuaTable::parse(LuaTable::render($updated))['teleports']['locations'][2]['name'], 'a0');

// ---------------------------------------------------------------- bundled mods
$bundled = MrExclusive\ScumManager\Services\ScumServerService::bundledMods();
check('bundled: our four mods ship with the plugin', array_keys($bundled), ['PelicanConsole', 'PlayerTools', 'ScumAntiCheat', 'ServerMessages']);
foreach ($bundled as $name => $zip) {
    $archive = ModArchive::open($zip, "$name.zip", 50 * 1024 * 1024, 100);
    $mods = $archive->mods();
    check("bundled: $name zip holds one mod", array_column($mods, 'name'), [$name]);
    check("bundled: $name has main.lua", isset($mods[0]['files']['Scripts/main.lua']), true);
    check("bundled: $name has no tests", array_values(array_filter(array_keys($mods[0]['files']), fn ($f) => str_starts_with($f, 'tests/'))), []);
    $archive->close();
}

// ---------------------------------------------------------------- settings export / import
use MrExclusive\ScumManager\Support\SettingsBundle;
$shipped = [];
foreach (['PlayerTools', 'ScumAntiCheat', 'ServerMessages'] as $mod) {
    $shipped[$mod] = LuaTable::parse(file_get_contents(__DIR__ . "/../../../mods/$mod/config.lua"));
}
$ini = "[General]\nScumServer.ServerName=Test\n[World]\nScumServer.MaxAllowedBirds=10\n";
$exported = SettingsBundle::make($shipped, $ini, 'ExclsvUK', '2026-10-12T22:00:00Z');
$decoded = json_decode($exported, true);
check('bundle: format marked', $decoded['format'], 'exclsv-settings');
check('bundle: mods under their display names', array_keys($decoded['mods']), ['ExclsvPlayerTools', 'ExclsvAntiCheat', 'ExclsvMessages']);
$imported = SettingsBundle::parse($exported);
check('bundle: mods come back under their folder names', array_keys($imported['mods']), ['PlayerTools', 'ScumAntiCheat', 'ServerMessages']);
foreach ($shipped as $mod => $config) {
    check("bundle: $mod round trip unchanged", LuaTable::parse(LuaTable::render($imported['mods'][$mod])), $config);
}
check('bundle: server settings kept as text', $imported['serverSettings'], $ini);
// Hand-edited: one mod by folder name, no server settings.
$edited = SettingsBundle::parse('{"format":"exclsv-settings","version":1,"mods":{"PlayerTools":{"teleports":{"toPlayerPrice":250}}}}');
check('bundle: folder names accepted, missing parts left alone', [array_keys($edited['mods']), $edited['serverSettings']], [['PlayerTools'], null]);
throws('bundle: other JSON refused', fn () => SettingsBundle::parse('{"hello":1}'), 'not an Exclsv settings export');
throws('bundle: broken JSON refused', fn () => SettingsBundle::parse('{"format":'), 'not valid JSON');
throws('bundle: unknown mod refused', fn () => SettingsBundle::parse('{"format":"exclsv-settings","version":1,"mods":{"SomeoneElsesMod":{}}}'), 'Unknown mod');
throws('bundle: newer version refused', fn () => SettingsBundle::parse('{"format":"exclsv-settings","version":99,"mods":{}}'), 'newer version');
throws('bundle: server settings must be an ini', fn () => SettingsBundle::parse('{"format":"exclsv-settings","version":1,"serverSettings":"rm -rf"}'), 'does not look like ServerSettings.ini');
throws('bundle: empty file refused', fn () => SettingsBundle::parse('{"format":"exclsv-settings","version":1,"mods":{}}'), 'contains no mods');
throws('bundle: huge file refused', fn () => SettingsBundle::parse(str_repeat(' ', SettingsBundle::MAX_BYTES + 1)), 'too large');

// ---------------------------------------------------------------- settings page layout
foreach (array_keys(ModSettings::MODS) as $mod) {
    $placed = array_merge(...array_values(ModSettings::groups($mod)));
    $titles = array_keys(ModSettings::MODS[$mod]['sections']);
    sort($placed);
    sort($titles);
    check("layout: $mod sub-tabs hold every section once", $placed, $titles);
}
check('layout: no PlayerTools section left in "Other"', array_key_exists('Other', ModSettings::groups('PlayerTools')), false);
check('layout: no anti-cheat section left in "Other"', array_key_exists('Other', ModSettings::groups('ScumAntiCheat')), false);
check('layout: section switch found', ModSettings::sectionSwitch(['fields' => ['a.price' => ['number', 'x', 1], 'a.enabled' => ['toggle', 'x', true]]]), 'a.enabled');
check('layout: no switch, no collapse', ModSettings::sectionSwitch(['fields' => ['a.price' => ['number', 'x', 1]]]), null);

// ---------------------------------------------------------------- mod updates from GitHub
use MrExclusive\ScumManager\Support\ModManifest;
$published = ModManifest::parse(file_get_contents(__DIR__ . '/../../../mods/dist/manifest.json'));
check('manifest: every shipped mod published', array_keys($published['mods']), ['PelicanConsole', 'PlayerTools', 'ScumAntiCheat', 'ScumCommandProbe', 'ServerMessages']);
foreach ($published['mods'] as $name => $entry) {
    $zip = file_get_contents(__DIR__ . "/../../../mods/dist/$name.zip");
    check("manifest: $name zip matches its sha256", (function () use ($zip, $entry, $name) { ModManifest::verify($zip, $entry, $name); return true; })(), true);
}
check('manifest: lists the manager version', $published['manager'], json_decode(file_get_contents(__DIR__ . '/../plugin.json'), true)['version']);
$entry = $published['mods']['PlayerTools'];
throws('manifest: truncated download refused', fn () => ModManifest::verify(substr(file_get_contents(__DIR__ . '/../../../mods/dist/PlayerTools.zip'), 0, -1), $entry, 'PlayerTools'), 'does not match');
throws('manifest: changed download refused', fn () => ModManifest::verify(str_repeat('x', $entry['bytes']), $entry, 'PlayerTools'), 'does not match');
$foreign = ModManifest::parse('{"format":"exclsv-mods","mods":{"SomeoneElsesMod":{"file":"SomeoneElsesMod.zip","build":"abcdef","sha256":"' . str_repeat('a', 64) . '","bytes":1}}}');
check('manifest: mods that are not ours are ignored', $foreign['mods'], []);
throws('manifest: path tricks refused', fn () => ModManifest::parse('{"format":"exclsv-mods","mods":{"PlayerTools":{"file":"../../evil.zip","build":"abcdef","sha256":"' . str_repeat('a', 64) . '","bytes":1}}}'), 'malformed');
throws('manifest: other JSON refused', fn () => ModManifest::parse('{"mods":{}}'), 'not an Exclsv mod manifest');
check('manifest: url built next to the manifest', ModManifest::url('https://raw.githubusercontent.com/MrExclusive2000/PelicanEggs/HEAD/mods/dist/', 'PlayerTools.zip'), 'https://raw.githubusercontent.com/MrExclusive2000/PelicanEggs/HEAD/mods/dist/PlayerTools.zip');
throws('manifest: plain http refused', fn () => ModManifest::url('http://example.com/mods', 'PlayerTools.zip'), 'https://');
check('manifest: newer manager detected', [ModManifest::isNewer('1.14.0', '1.13.9'), ModManifest::isNewer('1.13.0', '1.13.0'), ModManifest::isNewer(null, '1.0')], [true, false, false]);

// ---------------------------------------------------------------- overview page
use MrExclusive\ScumManager\Support\Overview;
$acLog = implode("\n", [
    '20:00:01 [ExclsvAntiCheat] Active. action=kick, 3 strikes in 600 s. Checks: speed.',
    '20:01:00 [ExclsvAntiCheat] Packet (7656...): moved 900 m in 1 s [strike 1/3]',
    '20:01:05 [ExclsvAntiCheat] Possible vehicle glitch, not counted as a strike: Bob: speed',
    '20:01:06 [ExclsvAntiCheat] Check failed: oops',
    '20:02:00 [ExclsvAntiCheat] Kicked Packet: 3 strikes.',
    '20:03:00 [ExclsvAntiCheat] SPECTATE Eve: aim followed Bob behind cover for 6 s at 80 m. Possible wallhack.',
    '20:04:00 [ExclsvAntiCheat] Settings reloaded (action=kick).',
]);
check('overview: flags newest first, noise left out', Overview::antiCheatEvents($acLog), [
    '20:03:00 [ExclsvAntiCheat] SPECTATE Eve: aim followed Bob behind cover for 6 s at 80 m. Possible wallhack.',
    '20:02:00 [ExclsvAntiCheat] Kicked Packet: 3 strikes.',
    '20:01:05 [ExclsvAntiCheat] Possible vehicle glitch, not counted as a strike: Bob: speed',
    '20:01:00 [ExclsvAntiCheat] Packet (7656...): moved 900 m in 1 s [strike 1/3]',
]);
check('overview: flag limit', count(Overview::antiCheatEvents($acLog, 2)), 2);
check('overview: crash lines found', Overview::crashLines("[Lua] ok\nUnhandled Exception: EXCEPTION_ACCESS_VIOLATION reading address 0x0000000C\n[Lua] fine"), ['Unhandled Exception: EXCEPTION_ACCESS_VIOLATION reading address 0x0000000C']);
check('overview: clean log has no crash lines', Overview::crashLines("[Lua] [ExclsvPlayerTools] Paid the daily bonus to Bob."), []);
check('overview: newest crash folder', Overview::newestCrash([
    ['name' => 'UECC-old', 'directory' => true, 'size' => 0, 'modified' => '2026-10-10T10:00:00+00:00'],
    ['name' => 'UECC-new', 'directory' => true, 'size' => 0, 'modified' => '2026-10-12T10:00:00+00:00'],
    ['name' => 'readme.txt', 'directory' => false, 'size' => 1, 'modified' => '2026-10-13T10:00:00+00:00'],
]), ['name' => 'UECC-new', 'modified' => '2026-10-12T10:00:00+00:00', 'count' => 2]);
check('overview: no crash folders', Overview::newestCrash([]), null);
check('overview: mod states', [
    Overview::modStatus(false, false, null, 'abc123')[0],
    Overview::modStatus(true, false, 'abc123', 'abc123')[0],
    Overview::modStatus(true, true, 'abc123', 'abc123')[0],
    Overview::modStatus(true, true, 'abc123', 'def456')[0],
    Overview::modStatus(true, true, null, 'def456')[0],
], ['Not installed', 'Disabled', 'Up to date', 'Update available', 'Installed']);

// ---------------------------------------------------------------- online players
use MrExclusive\ScumManager\Support\OnlinePlayers;
$tsv = "# updated 1000\n76561198000000001\tAlice\t123400\t-56700\t8900\tin sector B2\t0\t0\t4000\n"
    . "76561198000000002\tbob\t500000\t600000\t1000\t\t1\t1\t75\n"
    . "\tNewbie\t\t\t\t\t0\t0\t5\n"
    . "garbage line\n";
$online = OnlinePlayers::parse($tsv, 1030);
check('online: three players, sorted by name', array_column($online['players'], 'name'), ['Alice', 'bob', 'Newbie']);
check('online: fields read', $online['players'][1], ['steamId' => '76561198000000002', 'name' => 'bob', 'x' => 500000, 'y' => 600000, 'z' => 1000, 'place' => '', 'vehicle' => true, 'admin' => true, 'seconds' => 75]);
check('online: fresh within a minute', [$online['fresh'], $online['updated']], [true, 1000]);
check('online: stale list shows nobody', OnlinePlayers::parse($tsv, 1000 + OnlinePlayers::FRESH_SECONDS + 1)['players'], []);
check('online: missing file', OnlinePlayers::parse(null, 1000), ['updated' => null, 'fresh' => false, 'players' => []]);
check('online: where', [OnlinePlayers::where($online['players'][0]), OnlinePlayers::where($online['players'][1]), OnlinePlayers::where($online['players'][2])],
    ['in sector B2 (X=123400 Y=-56700 Z=8900)', 'X=500000 Y=600000 Z=1000', 'unknown (not spawned)']);
check('online: durations', [OnlinePlayers::duration(40), OnlinePlayers::duration(720), OnlinePlayers::duration(7500)], ['40 s', '12 min', '2 h 05 min']);
check('online: player actions build commands', [
    AdminCommands::build('giveitem', ['giveitem__name' => 'Alice', 'giveitem__item' => 'Water_05l', 'giveitem__amount' => '2']),
    AdminCommands::build('money', ['money__steamId' => '76561198000000001', 'money__amount' => '-500']),
    AdminCommands::build('teleportplayer', ['teleportplayer__name' => 'Alice', 'teleportplayer__x' => '1', 'teleportplayer__y' => '2', 'teleportplayer__z' => '3']),
], ['GiveItem Alice Water_05l 2', 'ChangeCurrencyBalance Normal -500 76561198000000001', 'TeleportPlayer Alice 1 2 3']);

// ---------------------------------------------------------------- setting choices
use MrExclusive\ScumManager\Support\SettingChoices;
check('choices: raid protection labelled from SCUM\'s enum', array_keys(SettingChoices::for('scum.RaidProtectionType')), [0, 1, 2, 3]);
check('choices: other keys stay plain', SettingChoices::for('scum.MaxPlayers'), null);

// ---------------------------------------------------------------- player directory
use MrExclusive\ScumManager\Support\PlayerDirectory;
$tsv = "76561198000000001\tAlice\t12\t3\t7200\t340\tgiven\t1000\t7200\t2026-10-12\t5\t500\t0\t2000\t\n"
    . "76561198000000002\tBob\t1\t9\t600\t20\t\t900\t600\t\t1\t0\t0\t1500\t\n";
$onlineNow = OnlinePlayers::parse("# updated 3000\n76561198000000002\tBob\t100\t200\t300\tin sector B2\t1\t0\t60\n", 3010)['players'];
$dir = PlayerDirectory::build($tsv, $onlineNow, [
    'AdminUsers.ini' => "76561198000000001[SetGodMode]\r\n",
    'BannedUsers.ini' => "76561198000000003\r\n",
    'WhitelistedUsers.ini' => null,
], "76561198000000002 2\n76561198000000003 3\n");
check('directory: everyone from every file, online first', array_column(array_values($dir), 'steamId'), ['76561198000000002', '76561198000000001', '76561198000000003']);
check('directory: stats from players.tsv', [$dir['76561198000000001']['kills'], $dir['76561198000000001']['deaths'], $dir['76561198000000001']['playtime'], $dir['76561198000000001']['bounty'], $dir['76561198000000001']['lastSeen']], [12, 3, 7200, 500, 2000]);
check('directory: online player and where', [$dir['76561198000000002']['online'], $dir['76561198000000002']['where'], $dir['76561198000000002']['vehicle']], [true, 'in sector B2 (X=100 Y=200 Z=300)', true]);
check('directory: admin with permissions suffix', $dir['76561198000000001']['flags']['admin'], true);
check('directory: banned player only known from the list', [$dir['76561198000000003']['name'], $dir['76561198000000003']['flags']['banned'], $dir['76561198000000003']['kicks']], ['', true, 3]);
check('directory: anti-cheat kicks', $dir['76561198000000002']['kicks'], 2);
check('directory: search by name or id', [array_column(array_values(PlayerDirectory::search($dir, 'ali')), 'steamId'), array_column(array_values(PlayerDirectory::search($dir, '0003')), 'steamId')], [['76561198000000001'], ['76561198000000003']]);
check('lists: add keeps other lines and line endings', PlayerDirectory::setMembership("76561198000000001[SetGodMode]\r\n", '76561198000000002', true), "76561198000000001[SetGodMode]\r\n76561198000000002\r\n");
check('lists: add twice is a no-op', PlayerDirectory::setMembership("76561198000000002\n", '76561198000000002', true), "76561198000000002\n");
check('lists: remove keeps the rest', PlayerDirectory::setMembership("76561198000000001[SetGodMode]\n76561198000000002\n", '76561198000000001', false), "76561198000000002\n");
check('lists: remove the last one empties the file', PlayerDirectory::setMembership("76561198000000002\r\n", '76561198000000002', false), '');
check('lists: add to a new file uses Windows line endings', PlayerDirectory::setMembership(null, '76561198000000002', true), "76561198000000002\r\n");
throws('lists: only SteamIDs', fn () => PlayerDirectory::setMembership('', '123', true), 'SteamID64');

echo "\n$count checks, $failures failed\n";
exit($failures === 0 ? 0 : 1);
