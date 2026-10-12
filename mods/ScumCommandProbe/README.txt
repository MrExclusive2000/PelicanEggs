ExclsvProbe (mod folder: ScumCommandProbe, read-only)

Maps what SCUM exposes for the features our mods use or plan to use, grouped by topic:
admin and commands, chat and on-screen notices, money/traders/fame, squads, bases/flags/raids,
mines and traps, world events/airdrops/NPCs, vehicles, loot and zones, stats and skills,
combat and kills, teleport and respawn, weather and time, map markers, logins and logs.

For each topic: classes (with parent class), functions (parameters, network flags), stored
values, events a mod can listen to, enums with their values and structs with their fields.
Also the game's data tables and a census of how many vehicles, flags, traders, mines, etc.
exist in the world right now.

It only reads Unreal's reflection data and counts objects. It does not call or change
anything in the game.

Use:
 1. Install it (ExclsvSCUM > Mods > "Install our mods", or upload this zip).
 2. Restart the server. The first report is written about 2-3 minutes after it is online,
    the census a minute after that.
 3. For the best report, let people play for 45 minutes: the probe scans again then and
    picks up vehicles, airdrops and events that only load once they appear.
 4. Download ue4ss/Mods/ScumCommandProbe/probe-output.txt from the File Manager.
 5. Disable or delete the mod afterwards.

Optional: a probe-settings.lua next to this file (an old probe.lua is ignored) narrows the search to one topic, e.g.
  return { title = "Item probe", keywords = { "item", "inventory" }, nativeOnly = true,
           wholeClasses = { "inventory" }, lateScanMinutes = 0 }
