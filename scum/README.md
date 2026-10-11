# SCUM

SCUM is a hardcore open world survival game focused on realism: detailed metabolism, weapon maintenance, stamina and inventory management.

The SCUM dedicated server (Steam app `3792580`) only ships a Windows build, so this egg downloads it with steamcmd and runs `SCUMServer.exe` under Wine (`ghcr.io/pelican-eggs/yolks:wine_staging`).

Import `egg-scum.yaml` in the Pelican panel under **Eggs → Import**.

## Server Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM      | 8 GiB   | 16 GiB+     |
| Disk     | 15 GiB  | 25 GiB      |

SCUM's memory use grows the longer it runs. Schedule a daily restart.

## Server Ports

SCUM binds the primary port **and the next two ports**. Players connect to **primary + 2**.

| Port               | Default | Notes                                   |
|--------------------|---------|-----------------------------------------|
| Game (primary)     | 7777    | The server's primary allocation         |
| Raw UDP            | 7778    | Primary + 1, add as an extra allocation |
| Game / Connect     | 7779    | Primary + 2, players connect here       |
| Query              | 27015   | Set with the Query Port variable        |

Every port above needs an allocation on the server, and the **Query Port** variable must equal the query allocation. Don't use 27020-27050 for the query port, because Steam reserves that range.

## How it works

- **Install:** steamcmd downloads app `3792580` with the Windows platform forced, then checks that `SCUM/Binaries/Win64/SCUMServer.exe` exists.
- **Auto update:** with **Auto Update** on, the Wine image runs steamcmd before every start.
- **Startup:** `wine SCUMServer.exe -log -port=… -QueryPort=… -MaxPlayers=…`. The console follows `SCUM/Saved/Logs/SCUM.log` because Wine doesn't print the server's output.
- **Console commands:** lines you type in the Pelican console are appended to `SCUM/Binaries/Win64/ue4ss/Mods/PelicanConsole/commands.txt`, and the console also shows that mod's `console.log`. This needs UE4SS and the [PelicanConsole mod](../mods/PelicanConsole); see [Console commands](#console-commands).
- **Stopping:** the panel sends `^C` (SIGINT). The startup command traps it and passes it to the server process, so the server can shut down cleanly instead of being killed when the stop timeout runs out.
- **Config:** on every start the panel writes the name, description, password and playstyle into `SCUM/Saved/Config/WindowsServer/ServerSettings.ini` (section `[General]`, keys `scum.ServerName` and so on). SCUM creates this file on its first start, so these values take effect from the **second** start.

## Configuration files

All in `SCUM/Saved/Config/WindowsServer/`:

| File                           | Purpose                                         |
|--------------------------------|-------------------------------------------------|
| `ServerSettings.ini`           | Every game and server setting                   |
| `AdminUsers.ini`               | SteamID64s with in-game admin commands          |
| `ServerSettingsAdminUsers.ini` | SteamID64s allowed to use the settings menu     |
| `BannedUsers.ini`              | Banned SteamID64s                               |
| `WhitelistedUsers.ini`         | Whitelisted SteamID64s                          |
| `ExclusiveUsers.ini`           | Only these players may join, when enabled       |

Save data is in `SCUM/Saved/SaveFiles/`. Back up the whole `SCUM/Saved` folder before you update or change settings.

## Settings editor and mods (SCUM Manager plugin)

The [SCUM Manager plugin](../plugins/scum-manager) adds three pages to SCUM servers:
- **SCUM Settings:** a form editor for `ServerSettings.ini`
- **SCUM Player Lists:** admin, whitelist and ban lists
- **SCUM Mods:** installs UE4SS and manages mods

This egg has the `scum_manager` feature, so the pages appear automatically once the plugin is installed.

SCUM has no official mod support yet, so server-side mods run through UE4SS. The **Wine DLL Overrides** variable (`WINEDLLOVERRIDES`, default `mscoree,mshtml=;dwmapi=n,b`) makes Wine load UE4SS's `dwmapi.dll` from the server folder. It does nothing when UE4SS isn't installed.

## Console commands

SCUM has no RCON and doesn't read admin commands from its console. The [PelicanConsole](../mods/PelicanConsole) UE4SS mod bridges the gap:
1. Install UE4SS from the **SCUM Mods** page, then upload `mods/dist/PelicanConsole.zip` there.
2. Restart the server and wait until it is online.
3. Type an admin command in the Pelican console, with or without the leading `#`, for example `ListPlayers` or `Announce Server restart in 10 minutes`.

The console then shows `[PelicanConsole] Ran: #ListPlayers` and SCUM's own reply, or the reason the command could not run. Commands typed while the server is starting or stopped are dropped.

The mod calls SCUM's `MiscStatics.Test_ProcessAdminCommand`, an internal function SCUM's developers use for testing. Try a harmless command first, and expect a SCUM update to rename or remove it.

## Server mods

Ready-made UE4SS mods in [`mods/dist`](../mods/dist), uploaded on the **SCUM Mods** page:

| Mod | What it does |
|-----|--------------|
| `PelicanConsole.zip` | Runs admin commands typed in the Pelican console (above) |
| `ScumAntiCheat.zip` | Flags or kicks players moving faster than possible or teleporting. It only logs until you set `action = "kick"` in its `config.lua` |
| `ServerMessages.zip` | Welcome message, rotating announcements, join/leave log |

Each mod has a `config.lua` in `SCUM/Binaries/Win64/ue4ss/Mods/<Mod>/`. Restart after editing it. The mods report in the Pelican console when PelicanConsole is installed.

For restart warnings, use a Pelican schedule: a **Send command** task with `Announce Server restarts in 10 minutes`, then a **Restart** power action 10 minutes later.

## Troubleshooting

- **The server runs but doesn't show in the server browser:**
  1. The **primary** allocation must be the lowest of the three consecutive game ports. For example, with 7779/7780/7781 the primary is 7779 and players connect on 7781.
  2. The **Query Port** variable must match the extra query allocation (e.g. 27017). The panel doesn't sync it on its own.
  3. Open every allocation for **UDP** (and TCP) on the host firewall, and forward them on the router if the node is behind NAT.
  4. Check whether Steam can see the server: open `https://api.steampowered.com/ISteamApps/GetServersAtAddress/v1/?addr=<public IP>`. It should list the server, with `gameport` set to the primary port.
  5. Try **Direct Connect** to `<public IP>:<primary + 2>`. If that works, the network is fine and only the browser listing is missing. A new server can take 10-15 minutes to appear, so search for it by name.

- **The panel stays on "Starting":** the server is marked running when the log prints `Config entry: GameID scum` (BattlEye) or the first `LogSCUM: Global Stats:` line. Both appear once the map has finished loading, about two minutes after start. If your build logs neither, edit the egg's startup "done" strings to a line from your `SCUM.log`.
- **The server crashes at start with missing DLL errors:** set **Winetricks** to `vcrun2022` and restart. It installs on every start, so the first boot takes longer.
- **"App '3792580' state is 0x6 after update job":** steamcmd failed the update. Restart again, or delete `steamapps/appmanifest_3792580.acf` and restart.
- **Version mismatch when joining:** the server is behind the client. Make sure Auto Update is on and restart.
- **Typed console commands do nothing:**
  - Updating the egg doesn't change servers that already exist: each server keeps its own copy of the start command. Go to **Admin → Servers → (your server) → Startup**, set **Startup Command** to **Default**, save and restart. The first line of the console after a start (`:/home/container$ wine …`) must contain `CMD_DIR=`.
  - Check that the console shows `[PelicanConsole] Ready.` after a start. If it doesn't, check that UE4SS is installed and the mod is enabled on the Mods page.
  - If you see `Ran: #…` but nothing happens in game, change `COMMAND_PREFIX` near the top of `ue4ss/Mods/PelicanConsole/Scripts/main.lua` from `"#"` to `""` and restart.
