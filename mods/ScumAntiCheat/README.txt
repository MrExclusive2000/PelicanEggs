ScumAntiCheat

Server-side anti-cheat for SCUM. BattlEye still handles the client side (aimbots, wallhacks,
injected code), which no server mod can see. This catches what cheats leave behind on the server.

Every second, for each player:
  - speed        faster than config.maxFootSpeed on foot / config.maxVehicleSpeed in a vehicle
  - teleport     a jump of config.teleportDistance metres or more between two checks
  - flying       in flying movement mode for config.flyingSeconds (fly hack)
  - hovering     in the air without coming down for config.hoverSeconds (hover / airwalk)
  - map bounds   outside the island, or below config.mapBounds.minZ (noclip, under-map)
These add strikes. config.strikesToAct strikes within config.strikeWindowSeconds trigger the action.

Instant checks (no strikes needed):
  - unauthorized admin  admin rights in game, but the SteamID is not in AdminUsers.ini
  - names               names containing config.blockedNames ("admin", "moderator", ...)

Also:
  - watchlist   the console says when a SteamID from config.watchlist joins
  - game logs   SCUM's own violations_*.log and admin_*.log entries are shown in the console;
                with strikeOnGameViolations = true each violation also counts as a strike

Actions (config.action):
  "log"   report only (default - run like this for a few days first)
  "kick"  kick; with banAfterKicks, players kicked that many times are banned
  "ban"   add the SteamID to BannedUsers.ini and kick

Not checked: admins listed in AdminUsers.ini, players the game is teleporting (admin teleports,
respawns), falling or parachuting players, config.ignoreNames and config.ignoreSteamIds.
SteamIDs come from the login lines in SCUM.log.

Use:
 1. Upload this zip on the SCUM Mods page (it is enabled automatically).
 2. Restart the server. The Pelican console shows "[ScumAntiCheat] Active. ..." when the
    PelicanConsole mod is installed; otherwise check ue4ss/UE4SS.log.
 3. Leave action = "log" for a few days and read anticheat.log in this folder. If honest
    players get flagged (a fast vehicle, a long ladder), raise the matching limit or turn
    that check off in config.checks.
 4. Then set action = "kick" in config.lua and restart.

Files in this folder: anticheat.log (reports), offenses.txt (kick counts per SteamID).

Uploading the zip again replaces config.lua with the default one. Copy your settings first.
