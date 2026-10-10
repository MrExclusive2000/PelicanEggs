# SCUM Manager (Pelican plugin)

Adds three pages to SCUM servers in the Pelican client area:

| Page | What it does |
|------|--------------|
| **SCUM Settings** | Form editor for `ServerSettings.ini`, with a tab per section and search |
| **SCUM Player Lists** | Admins, settings admins, whitelist, exclusive, banned and silenced players |
| **SCUM Mods** | Installs or updates UE4SS, uploads mods, and turns them on/off or deletes them |

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
- **Upload mod:** takes the mod's `.zip` as downloaded. Any folder inside that contains `Scripts/main.lua` (Lua) or `dlls/main.dll` (C++) is installed into `ue4ss/Mods/<name>` and enabled. Paths are checked, so nothing can be written outside the mod folder.
- **Enable/Disable:** updates `mods.txt` and `mods.json` together, and keeps `Keybinds` last, as UE4SS requires.
- **Delete:** removes the mod's folder. UE4SS's own built-in mods can be disabled but not deleted.

Changes apply on the next server start.

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
| Start/stop from the Settings page | `control.start` / `control.stop` |

## Limits

- **Upload size:** mod uploads are also capped by PHP's `upload_max_filesize` and `post_max_size` on the panel.
- **Unknown values:** settings whose value doesn't match a known format are edited as plain text.

## Development

The parts that don't need the panel (INI editing, value types, mod lists and zip inspection) have standalone tests:

```bash
php plugins/scum-manager/tests/run.php
```
