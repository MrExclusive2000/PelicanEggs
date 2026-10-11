# SCUM Manager (Pelican plugin)

Adds five pages to SCUM servers in the Pelican client area:

| Page | What it does |
|------|--------------|
| **SCUM Admin Console** | Pick a command (announce, kick, set time, give money or items, teleport, ban...) and run it through the PelicanConsole mod; adds the outposts (or any spot) as `!tp` destinations; shows the results and player reports |
| **SCUM Settings** | Form editor for `ServerSettings.ini`, with a tab per section and search |
| **SCUM Player Lists** | Admins, settings admins, whitelist, exclusive, banned and silenced players |
| **SCUM Mods** | Installs or updates UE4SS and our mods, uploads mods, and turns them on/off or deletes them |
| **SCUM Mod Settings** | Settings for our mods: player tools (chat commands, kill feed, stats, AFK, voting, starter kit), messages and restart warnings, anti-cheat |

The pages only appear on SCUM servers: eggs with the `scum_manager` feature or `scum` tag, or any server whose startup command runs `SCUMServer.exe`.

## Install

1. In the panel, go to **Admin → Plugins → Import from file** and upload `scum-manager.zip`. You can build it with `plugins/build.sh`, or download it from `plugins/dist/`.
2. Click **Install**. Plugin installs run in the background, so the panel's queue worker must be running.
3. Re-import the updated SCUM egg (`scum/egg-scum.yaml`). It adds the `scum_manager` feature and the `WINEDLLOVERRIDES` variable that mods need.

Optional settings are under **Admin → Plugins → SCUM Manager → Settings**: how many backups to keep, which UE4SS build to install, and the maximum mod upload size.

## SCUM Settings

- **Built from your own file:** the form is built from whatever keys are in your server's `ServerSettings.ini`, so settings added by monthly SCUM updates appear without updating the plugin.
- **Field types follow the value:** `True/False` becomes a toggle, numbers become number fields, `HH:MM:SS` is a duration and `2g` is a gold price. Decimals are written back in SCUM's format (`2.000000`).
- **Only changed lines are rewritten:** comments, ordering, spacing, line endings and encoding (UTF-8 or UTF-16) are kept.
- **Egg-managed keys are read-only:** keys the egg writes on every start (name, description, password and playstyle) are shown but locked. Change them on the Startup page.
- **The server must be stopped to save:** SCUM rewrites the file while it runs, so changes made to a running server would be lost. The page has Stop and **Save & start** buttons.
- **Backup on every save:** a timestamped copy (`ServerSettings.ini.bak-YYYYMMDD-HHMMSS`) is made before each save, and the newest 10 are kept. Restore one from **Backups**.
- **Concurrent edits are refused:** if the file changed after you opened the page (for example, an admin used the in-game settings menu), the save is refused instead of overwriting their change.

## SCUM Player Lists

One SteamID64 per line. Admin lists check that each line is a 17-digit ID; permission suffixes in brackets are allowed. These files also need the server stopped to save, because SCUM updates them, for example when it bans someone.

## SCUM Mods

SCUM has no official mod support yet. Server-side mods run through [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS). Players don't install anything, and BattlEye stays on for them.

- **Install UE4SS:** downloads the latest UE4SS build from GitHub into `SCUM/Binaries/Win64` and extracts it. The default is the *experimental* build, which SCUM mod authors use. **Update** keeps your `mods.txt`, `mods.json` and `UE4SS-settings.ini`. The server must be stopped.
- **SCUM-safe settings:** UE4SS turns on about sixteen engine hooks by default, and on SCUM 1.3 these crash the server as soon as a player joins. A fresh install therefore turns off every hook except `HookCallFunctionByNameWithArguments` and `HookEngineTick`, and disables the UE4SS console window. The **SCUM-safe UE4SS settings** button re-applies this to an existing install. If a mod's instructions say it needs another hook, turn that hook back on in `ue4ss/UE4SS-settings.ini`.
- **Our mods:** PelicanConsole, PlayerTools, ServerMessages and ScumAntiCheat ship inside the plugin (`resources/mods`) and are installed and enabled together with a fresh UE4SS install. **Install our mods** installs or updates them on an existing install; each mod's `config.lua` is kept. Set `SCUM_MANAGER_INSTALL_BUNDLED_MODS=false` in the panel's `.env` to skip them on fresh installs.
- **Upload mod:** takes the mod's `.zip` as downloaded. Any folder inside that contains `Scripts/main.lua` (Lua) or `dlls/main.dll` (C++) is installed into `ue4ss/Mods/<name>` and enabled. Paths are checked, so nothing can be written outside the mod folder.
- **Enable/Disable:** updates `mods.txt` and `mods.json` together, and keeps `Keybinds` last, as UE4SS requires.
- **Delete:** removes the mod's folder. UE4SS's own built-in mods can be disabled but not deleted.
- **Built-in mods off:** UE4SS ships client tools: the console, a cheat manager that hooks every player spawn, keybinds, and the Blueprint mod loader. A fresh install turns them all off, and **Disable built-in mods** does the same for an existing install. Re-enable `BPModLoaderMod` and `BPML_GenericFunctions` only if a mod says it needs them.

Changes apply on the next server start.

### Console commands

To run admin commands, upload the [PelicanConsole](../../mods/PelicanConsole) mod (`mods/dist/PelicanConsole.zip`) on this page and restart. Then use the **SCUM Admin Console** page: pick a command from the list (grouped into "works any time" and "needs an admin in game"), fill in the player or value, and run it. The page writes the command straight into the mod's `commands.txt`, tells you whether SCUM picked it up, and shows the mod's `console.log`. The SCUM egg also forwards commands typed in the Pelican console to the same mod. See the [egg README](../../scum/README.md#console-commands).

## SCUM Mod Settings

A tab per installed mod of ours, with every option of its `config.lua`. Saving rewrites `config.lua` (comments are not kept; options the page doesn't know are), and the mods pick up the change within 30 seconds, without a restart. If the file changed after you opened the page, the save is refused for that mod. See the [egg README](../../scum/README.md#server-mods) for what each mod does.

### Wine

UE4SS loads through a `dwmapi.dll` file next to `SCUMServer.exe`. Wine prefers its own built-in `dwmapi`, so the server needs `WINEDLLOVERRIDES` to include `dwmapi=n,b`. The updated egg sets this by default, and the Mods page shows whether it is set.

If a mod loads and then crashes the server, check `SCUM/Binaries/Win64/ue4ss/UE4SS.log`. Some mod authors ship a SCUM-specific `UE4SS-settings.ini`; put it in the `ue4ss` folder.

## Permissions

The pages use Pelican's existing subuser permissions:

| Action | Permission |
|--------|------------|
| View settings and lists | `file.read-content` |
| Save settings and lists, toggle mods | `file.update` |
| See the Mods page | `file.read` |
| Upload mods | `file.create` |
| Install UE4SS | `file.create` + `file.archive` |
| Delete mods | `file.delete` |
| Send admin commands | `control.console` + `file.update` |
| View / save mod settings | `file.read-content` / `file.update` |
| Start/stop from the Settings page | `control.start` / `control.stop` |

## Limits

- **Upload size:** mod uploads are also capped by PHP's `upload_max_filesize` and `post_max_size` on the panel.
- **Unknown values:** settings whose value doesn't match a known format are edited as plain text.

## Development

The parts that don't need the panel (INI editing, value types, mod lists and zip inspection) have standalone tests:

```bash
php plugins/scum-manager/tests/run.php
for t in mods/*/tests/run.lua; do lua5.4 "$t"; done
```

`plugins/build.sh` rebuilds the mod zips, copies them into `resources/mods` and builds `plugins/dist/scum-manager.zip`.
