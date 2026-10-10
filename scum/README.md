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

Every port above needs an allocation on the server. Don't use 27020-27050 for the query port, because Steam reserves that range.

## How it works

- **Install:** steamcmd downloads app `3792580` with the Windows platform forced, then checks that `SCUM/Binaries/Win64/SCUMServer.exe` exists.
- **Auto update:** with **Auto Update** on, the Wine image runs steamcmd before every start.
- **Startup:** `wine SCUMServer.exe -log -port=… -QueryPort=… -MaxPlayers=…`. The console follows `SCUM/Saved/Logs/SCUM.log` because Wine doesn't print the server's output.
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

## Troubleshooting

- **The panel stays on "Starting":** the server is marked running when the log prints `Config entry: GameID scum` (BattlEye) or `Engine is initialized.`. If your build logs neither, edit the egg's startup "done" strings to a line from your `SCUM.log`.
- **The server crashes at start with missing DLL errors:** set **Winetricks** to `vcrun2022` and restart. It installs on every start, so the first boot takes longer.
- **"App '3792580' state is 0x6 after update job":** steamcmd failed the update. Restart again, or delete `steamapps/appmanifest_3792580.acf` and restart.
- **Version mismatch when joining:** the server is behind the client. Make sure Auto Update is on and restart.
