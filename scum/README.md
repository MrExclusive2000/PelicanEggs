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

Save data is in `SCUM/Saved/SaveFiles/`. Every start copies `SCUM.db` to `SaveFiles/ExclsvBackups/` (newest 14 kept), and the ExclsvSCUM World page restores them. Back up the whole `SCUM/Saved` folder before big updates as well.

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
3. Send a command from the **SCUM Admin Console** page of the SCUM Manager plugin, or type it in the Pelican console, with or without the leading `#`. For example: `ListPlayers` or `Announce Server restart in 10 minutes`.

How commands run:
- **`Announce <message>`** shows the message on every player's screen, and **`ListPlayers`** lists who is online in the console. **`Kick <name>`** kicks an online player by name. These work with no admin in game.
- **Every other command** (SetTime, SetWeather, Ban, Teleport...) runs through an online admin's chat command channel, exactly as if that admin typed it in chat, and SCUM's reply appears in their chat. So an admin from `AdminUsers.ini` must be online.
- With no admin online, the mod tries SCUM's internal `MiscStatics.Test_ProcessAdminCommand`, which SCUM ignores for most commands on a dedicated server. The console says so.

Commands typed while the server is starting or stopped are dropped.

## Server mods

Our own UE4SS mods ship with the SCUM Manager plugin and are installed together with UE4SS (or with **Install / update our mods** on the **ExclsvSCUM > Mods** page, which pulls the latest builds from GitHub and keeps their settings). They are also in [`mods/dist`](../mods/dist) for manual upload.

| Mod | What it does |
|-----|--------------|
| `PelicanConsole` | Runs admin commands from the SCUM Admin Console page or the Pelican console (above) |
| `PlayerTools` | Chat commands (`!help`, `!rules`, `!discord`, `!online`, `!stats`, `!top`, `!vote`, `!info`, `!bounty`, `!tp`, `!tpto`, `!report`, `!seen`, `!manhunt`), kill feed, stats and leaderboard, kill streaks, streak bounties, AFK kicker, votes for time and weather, new-player welcome and starter kit, welcome back, playtime rewards and a daily bonus, paid teleports, player reports, death recap, combat hotspots, `!seen`, Manhunt and King of the Hill events, and feature tips |
| `ServerMessages` | Welcome message, rotating announcements, join/leave log, restart countdown warnings |
| `ScumAntiCheat` | Server-side anti-cheat: speed, teleport, fly and hover hacks, out-of-map/under-map, admin rights not in AdminUsers.ini, staff impersonation names, aimbot signs from the kill log and aim snaps (reported as suspects), a watchlist, and SCUM's own violation and admin logs in the console. It can kick or ban (via BannedUsers.ini), but only logs until you change its action |

Change their settings on the **SCUM Mod Settings** page, or in `config.lua` in `SCUM/Binaries/Win64/ue4ss/Mods/<Mod>/`. The mods pick up changes within 30 seconds. They report in the Pelican console and on the Admin Console page.

Votes, starter kits, rewards, bounty payouts and teleports run SCUM admin commands (SetTime, ChangeCurrencyBalance, Teleport...) as an online admin, so an admin from `AdminUsers.ini` must be online for them to take effect. Restart warnings only announce: add a Pelican schedule (**Schedules**) with a **Restart** power action at the same times.

## Discord feed

Paste a channel webhook into **[Exclsv] Discord webhook URL** on the Startup page (Discord: channel settings → Integrations → Webhooks → New webhook → Copy webhook URL) and restart. The server then posts:

- **status:** starting, online and stopped
- **flags:** anti-cheat strikes, kicks, bans and spectate flags
- **reports:** `!report` messages from players

**[Exclsv] Discord feed** picks which, e.g. `flags,reports`. Messages are batched every few seconds to stay within Discord's limits, and `@everyone` or other mentions in player text never ping anyone. The relay (`discord-relay.sh` in the PelicanConsole mod) runs next to the game, only reads the mods' log files and stops with the server. Treat the webhook URL like a password: anyone who has it can post to the channel.

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
