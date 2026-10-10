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

use MrExclusive\ScumManager\Support\IniDocument;
use MrExclusive\ScumManager\Support\ModArchive;
use MrExclusive\ScumManager\Support\ModList;
use MrExclusive\ScumManager\Support\SettingLabel;
use MrExclusive\ScumManager\Support\SettingType;

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

echo "\n$count checks, $failures failed\n";
exit($failures === 0 ? 0 : 1);
