ScumAntiCheat

Server-side movement checks for SCUM. Once a second it compares every player's position
with the last one and flags:
  - speed:    faster than config.maxFootSpeed on foot or config.maxVehicleSpeed in a vehicle
  - teleport: a jump of config.teleportDistance metres or more between two checks

Not checked: admins (AdminUsers.ini), players the game itself is teleporting (admin teleports,
respawns), falling or parachuting players, and names in config.ignoreNames.

BattlEye still handles the client side (aimbots, wallhacks, injected code). A server mod can't
see those, so this only catches cheats that move the character on the server.

Use:
 1. Upload this zip on the SCUM Mods page (it is enabled automatically).
 2. Restart the server. The Pelican console shows "[ScumAntiCheat] Active. ..." when the
    PelicanConsole mod is installed; otherwise check ue4ss/UE4SS.log.
 3. Leave action = "log" for a few days and read anticheat.log in this folder. If honest
    players get flagged (a fast vehicle, an odd spawn), raise the matching limit.
 4. Then set action = "kick" in config.lua and restart.

Reports go to anticheat.log in this folder, ue4ss/UE4SS.log, and the Pelican console.

Uploading the zip again replaces config.lua with the default one. Copy your settings first.
