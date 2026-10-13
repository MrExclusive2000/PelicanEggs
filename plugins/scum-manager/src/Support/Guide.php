<?php

namespace MrExclusive\ScumManager\Support;

/**
 * The Help & guide page's content, as data: topics made of paragraphs, numbered steps and
 * term/explanation rows. Kept apart from the page so it can be checked without the panel.
 */
final class Guide
{
    /**
     * @return list<array{id: string, title: string, icon: string, summary: string, blocks: list<array{type: string, title?: string, text?: string, items?: list<string>|array<string, string>}>}>
     */
    public static function topics(): array
    {
        $console = Brand::mod('ExclsvConsole');
        $tools = Brand::mod('ExclsvPlayerTools');
        $antiCheat = Brand::mod('ExclsvAntiCheat');
        $messages = Brand::mod('ExclsvMessages');
        $probe = Brand::mod('ExclsvProbe');

        return [
            [
                'id' => 'start',
                'title' => 'Getting started',
                'icon' => 'tabler-rocket',
                'summary' => 'First-time setup of a SCUM server with ' . Brand::MANAGER . '.',
                'blocks' => [
                    ['type' => 'steps', 'items' => [
                        'Startup page: set the server name, description, password, playstyle and max players. These are written into ServerSettings.ini on every start, so change them there, not on Server settings.',
                        'Start the server once and wait until it is online, so SCUM creates its config files. Then stop it.',
                        'Mods page: press "Install UE4SS". This also installs and switches on our mods (' . implode(', ', [$console, $tools, $messages, $antiCheat]) . ').',
                        'Player lists page (server stopped): add your SteamID64 to Admins.',
                        'Start the server. The Overview page should show UE4SS installed and every mod "Up to date". The console shows "[ExclsvConsole] Ready." once the mods have loaded.',
                        'Mod settings page: switch on the features you want. Most are off until you turn them on; changes apply within 30 seconds, no restart needed.',
                        'Optional: paste a Discord channel webhook into "[Exclsv] Discord webhook URL" on the Startup page for start/stop, anti-cheat and report posts.',
                    ]],
                    ['type' => 'text', 'text' => 'Leave the anti-cheat on "log" for a few days before letting it kick or ban (see Anti-cheat below).'],
                ],
            ],
            [
                'id' => 'pages',
                'title' => 'The pages',
                'icon' => 'tabler-layout-sidebar',
                'summary' => 'What each page in the ' . Brand::NAV_GROUP . ' menu is for.',
                'blocks' => [
                    ['type' => 'rows', 'items' => [
                        'Overview' => 'Server and mod status, who is online and where, anti-cheat flags, player reports, the last crash. "Manage a player" runs the common commands on one player.',
                        'Players' => 'Everyone who has played: stats, money, fame, squad, inventory (from the save), lists they are on and anti-cheat kicks. Run commands or ban from here.',
                        'World' => 'Live map with players, bases and outposts; every base with its owner; save backups and restores.',
                        'Server settings' => 'Every setting in ServerSettings.ini, explained, with SCUM\'s defaults once captured. The server must be stopped to save.',
                        'Console' => 'Pick a command (announce, kick, money, items, teleport, time, weather...) and run it, without being in game. Also adds teleport destinations and King of the Hill zones.',
                        'Mods' => 'Install or update UE4SS and our mods, upload other mods, switch mods on and off.',
                        'Mod settings' => 'Every option of our mods: chat commands, rewards, economy, events, messages, anti-cheat. Export / Import saves or copies them all in one file.',
                        'Player lists' => 'Admins, settings admins, whitelist, exclusive, banned and silenced players. The server must be stopped to save.',
                        'Help & guide' => 'This page.',
                    ]],
                ],
            ],
            [
                'id' => 'everyday',
                'title' => 'Everyday tasks',
                'icon' => 'tabler-checklist',
                'summary' => 'How to do the common jobs.',
                'blocks' => [
                    ['type' => 'rows', 'items' => [
                        'Change a server setting' => 'Server settings: stop the server (button at the top), change the field, Save & start. A backup is made on every save; "Backups" puts one back.',
                        'Put a setting back to default' => 'Capture the defaults once (Server settings → Capture defaults, then follow the steps). Changed settings then show a pencil with a reset button, and "Only changed settings" lists them.',
                        'Make someone an admin' => 'Player lists → Admins (server stopped), or Players → the player → Lists → Admin.',
                        'Kick or ban' => 'Overview → Manage a player, or Players → the player. Ban works while the server runs; unban needs it stopped.',
                        'Give money, fame or items' => 'Overview → Manage a player, or Console. Taking money checks the player\'s balance from the last save first.',
                        'Teleport a player' => 'Overview → Manage a player → Teleport / Bring / Go to, or Console → Teleport.',
                        'Send an announcement' => 'Console → Announce, or type "Announce your message" in the Pelican console. For regular messages use Mod settings → ' . $messages . ' → Announcements.',
                        'Restart warnings' => 'Mod settings → ' . $messages . ' → Restart warnings (times in UTC), plus a Pelican schedule (Schedules) that restarts the server at the same times.',
                        'Add a !tp place or a King of the Hill zone' => 'Stand there in game, then Console → "Add a place where a player stands". Or add the four outposts with one button.',
                        'Back up or restore the save' => 'World → Save backups. A backup is also made on every start; the newest 14 are kept.',
                        'Copy all mod settings to another server' => 'Mod settings → Export settings, then Import settings on the other server.',
                    ]],
                ],
            ],
            [
                'id' => 'updates',
                'title' => 'Updating',
                'icon' => 'tabler-refresh',
                'summary' => 'Keeping the mods, the plugin and SCUM up to date.',
                'blocks' => [
                    ['type' => 'rows', 'items' => [
                        'Our mods' => 'Mods → "Install / update our mods", then restart. Your settings are kept. The Overview page says when an update is waiting. Most fixes only need this.',
                        Brand::MANAGER => 'Only when the Overview says a newer version is available: Admin → Plugins → Import from file with the new scum-manager.zip.',
                        'UE4SS' => 'Mods → Update (server stopped). Your UE4SS settings and mod list are kept.',
                        'Mod folders renamed (1.33.0)' => 'Our mods\' folders are now ExclsvConsole, ExclsvPlayerTools, ExclsvAntiCheat, ExclsvMessages and ExclsvProbe. The first "Install / update our mods" after updating the panel moves the old folders (PelicanConsole, PlayerTools...) across with their settings and player data; stop the server first. Re-import the SCUM egg too.',
                        'After a SCUM update' => 'Update the server as usual, start it and check the Overview. If something stops working, update our mods first. Re-capture the setting defaults after big updates, as new settings appear.',
                    ]],
                ],
            ],
            [
                'id' => 'chat',
                'title' => 'Player chat commands',
                'icon' => 'tabler-message-circle',
                'summary' => 'What players can type in game chat (' . $tools . '). Replies go only to them. Most commands work only once switched on in Mod settings.',
                'blocks' => [
                    ['type' => 'rows', 'items' => [
                        '!help' => 'The list of commands that are switched on.',
                        '!rules, !discord, !info' => 'Server rules, the Discord link, server time, uptime and next restart.',
                        '!online, !seen <name>' => 'Who is on; when a player was last online.',
                        '!stats [name], !top' => 'Kills, deaths, K/D, longest kill and playtime; the leaderboard.',
                        '!vote <option>, !yes, !no' => 'Vote for day, night or sun (or what you set up).',
                        '!tp <place>' => 'Teleport to a place you set up. Stand still for the countdown; the price is charged first.',
                        '!tpto <name>, !tpaccept, !tpdeny' => 'Ask to teleport to a player. They have 60 seconds to type !tpaccept.',
                        '!bounty' => 'Bounties on players with a kill streak.',
                        '!report <name> <what happened>' => 'Reports a player to the admins (Overview, Discord, online admins).',
                        '!manhunt join' => 'Volunteer to be hunted for a reward.',
                        '!shop, !buy <item>' => 'Buy items from the server shop.',
                        '!sell, !sell prices' => 'Sell the item in your hands; list what the server buys.',
                        '!pay <name> <amount>' => 'Send money to another online player.',
                        '!lottery' => 'Buy a ticket for the hourly draw.',
                        '!tasks, !race' => 'Today\'s tasks and their progress; the kill race score.',
                        '!where' => 'Admins only: your coordinates.',
                    ]],
                ],
            ],
            [
                'id' => 'economy',
                'title' => 'Money, rewards and admin commands',
                'icon' => 'tabler-coin',
                'summary' => 'Why some things wait for an admin, and how to let them run without one.',
                'blocks' => [
                    ['type' => 'text', 'text' => 'Rewards, kits, shop purchases, bounty payouts, votes and paid teleports use SCUM\'s own admin commands. SCUM only runs those for an admin who is in game, so by default the mods run them through an online admin, and rewards wait in players.tsv until one is on.'],
                    ['type' => 'rows', 'items' => [
                        'Run them without an admin' => 'Create an empty file no-admin-commands.txt in the ExclsvConsole mod folder (File Manager: SCUM/Binaries/Win64/ue4ss/Mods/ExclsvConsole/). Money, fame, SpawnItem and Teleport then run as the player they are for. No restart needed.',
                        'Turn it off again' => 'Delete that file. A restart also always puts SCUM\'s own admin settings back.',
                        'Check a balance' => 'Console → Balance <player>, or the Players page (from the last save).',
                        'Prices and payouts' => 'Mod settings → ' . $tools . ' → Shop & money and Economy. Everything there is off until switched on, and every purchase checks the player\'s balance first.',
                    ]],
                    ['type' => 'text', 'text' => $antiCheat . ' is told about each command first, so it does not flag the player SCUM logs it under.'],
                ],
            ],
            [
                'id' => 'anticheat',
                'title' => 'Anti-cheat',
                'icon' => 'tabler-shield-check',
                'summary' => $antiCheat . ' works next to BattlEye and catches what cheats leave behind on the server.',
                'blocks' => [
                    ['type' => 'text', 'text' => 'It checks speed, teleports, flying, hovering and leaving the map every second, admin rights from people not in AdminUsers.ini, blocked names, and kills that look like an aimbot (long range, aim snaps, silent aim, kill rate). Aimbot signs only point at who to spectate: they cannot prove anything.'],
                    ['type' => 'steps', 'items' => [
                        'Leave Action on "log" for a few days. Flags appear on the Overview and in Discord.',
                        'If honest players get flagged (a fast vehicle, a long ladder), raise that limit or switch that check off in Mod settings → ' . $antiCheat . '.',
                        'Then switch Action to "kick", or "ban" if you are confident. Admins in AdminUsers.ini are never checked.',
                    ]],
                ],
            ],
            [
                'id' => 'trouble',
                'title' => 'Troubleshooting',
                'icon' => 'tabler-tool',
                'summary' => 'Common problems and what to do.',
                'blocks' => [
                    ['type' => 'rows', 'items' => [
                        '"No admin is online, so SCUM cannot run..."' => 'An admin from AdminUsers.ini must be in game, or turn on the no-admin route (Money, rewards and admin commands above).',
                        'Mods do not load' => 'Check the Mods page: UE4SS installed, WINEDLLOVERRIDES includes dwmapi=n,b (re-import the egg if not), mods switched on. Then restart and look for "[ExclsvConsole] Ready." in the console.',
                        'Server crashed' => 'Overview → Last session shows the crash lines from before the restart and SCUM\'s newest crash report. Update our mods, and send those lines when asking for help.',
                        'Server lags' => 'Update our mods (older versions searched for players too often). The mod logs should say "Finding players through the game\'s player list." If it still lags, look at the Global Stats lines in SCUM.log around the time.',
                        'Settings or lists will not save' => 'Stop the server first: SCUM rewrites these files while it runs. If the save is refused because the file changed, reload the page (someone used the in-game menu).',
                        'A setting change was lost' => 'Name, description, password and playstyle come from the Startup page on every start. Change them there.',
                        'A chat command does nothing' => 'Check it is switched on in Mod settings, then !help in game. Commands only read chat written after the server started.',
                        'Items from rewards never arrive' => 'Item giving is switched on with "Item rewards" in Mod settings and is not yet confirmed on every server: test it on yourself. An item type is only given once SCUM has loaded it.',
                        'Something new is broken after a SCUM update' => 'Update our mods first. ' . $probe . ' (upload it on the Mods page) writes a report of what the game offers, which helps find what changed.',
                    ]],
                ],
            ],
            [
                'id' => 'files',
                'title' => 'Where things are',
                'icon' => 'tabler-folder',
                'summary' => 'Files you may want in the File Manager.',
                'blocks' => [
                    ['type' => 'rows', 'items' => [
                        'SCUM/Saved/Config/WindowsServer/' => 'ServerSettings.ini and the player lists (AdminUsers.ini, BannedUsers.ini...).',
                        'SCUM/Saved/SaveFiles/' => 'The save (SCUM.db) and SCUM\'s logs (Logs/). Backups are in ExclsvBackups/.',
                        'SCUM/Binaries/Win64/ue4ss/' => 'UE4SS, UE4SS.log (and UE4SS.previous.log from before the last restart).',
                        'ue4ss/Mods/ExclsvPlayerTools/' => 'config.lua, players.tsv (stats and unpaid rewards, backed up daily), online.tsv, reports.log.',
                        'ue4ss/Mods/ExclsvAntiCheat/' => 'config.lua, anticheat.log, offenses.txt.',
                        'ue4ss/Mods/ExclsvConsole/' => 'console.log (command results), items.txt, no-admin-commands.txt when switched on.',
                        'ue4ss/Mods/ExclsvMessages/' => 'config.lua, players.log (who joined and left).',
                    ]],
                    ['type' => 'text', 'text' => 'ServerSettings exports and the Discord webhook can contain passwords: keep them private.'],
                ],
            ],
        ];
    }

    /** One topic as HTML; every piece of text is escaped. */
    public static function html(array $topic): string
    {
        $html = '';

        foreach ($topic['blocks'] as $block) {
            if (($block['title'] ?? '') !== '') {
                $html .= '<p style="font-weight: 600; margin: .75rem 0 .25rem;">' . self::e($block['title']) . '</p>';
            }

            $html .= match ($block['type']) {
                'text' => '<p style="margin: .5rem 0; line-height: 1.5;">' . self::e($block['text']) . '</p>',
                'steps' => '<ol style="list-style: decimal; padding-left: 1.5rem; margin: .5rem 0; line-height: 1.5;">'
                    . implode('', array_map(fn (string $step) => '<li style="margin: .25rem 0;">' . self::e($step) . '</li>', $block['items']))
                    . '</ol>',
                'rows' => '<dl style="margin: .5rem 0; line-height: 1.5;">'
                    . implode('', array_map(
                        fn (string $term, string $text) => '<dt style="font-weight: 600; margin-top: .6rem;">' . self::e($term) . '</dt>'
                            . '<dd style="margin: .1rem 0 0 0; opacity: .85;">' . self::e($text) . '</dd>',
                        array_keys($block['items']),
                        $block['items'],
                    ))
                    . '</dl>',
                default => '',
            };
        }

        return $html;
    }

    /** Links to every topic, for the top of the page. */
    public static function contents(): string
    {
        $links = array_map(
            fn (array $topic) => '<a href="#guide-' . self::e($topic['id']) . '" style="text-decoration: underline; text-underline-offset: 2px;">' . self::e($topic['title']) . '</a>',
            self::topics(),
        );

        return '<p style="line-height: 2;">' . implode(' &nbsp;·&nbsp; ', $links) . '</p>';
    }

    private static function e(string $text): string
    {
        return htmlspecialchars($text, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }
}
