ExclsvProbe (read-only)

Maps what SCUM exposes for the features our mods use or plan to use, grouped by topic:
admin and commands, chat and on-screen notices, money/traders/fame, squads, bases/flags/raids,
mines and traps, world events/airdrops/NPCs, vehicles, loot and zones, stats and skills,
combat and kills, teleport and respawn, weather and time, map markers, logins and logs.

For each topic: classes (with parent class), functions (parameters, network flags), stored
values, events a mod can listen to, enums with their values and structs with their fields.
Also the game's data tables and, when asked for, a census of how many vehicles, flags,
traders, mines, etc. exist in the world right now.

It only reads Unreal's reflection data and counts objects. It does not call or change
anything in the game.

Use:
 1. Upload this zip on ExclsvSCUM > Mods. Once it is installed, "Install / update our mods"
    keeps it up to date.
 2. Restart the server. The first report is written about 2-3 minutes after it is online,
    The census (object counts) is off: it touches live world objects and an earlier version
    of it could crash the server. Turn it on with   return { census = true }   in
    probe-settings.lua only if asked; each class it counts is named in UE4SS.log first.
 3. Optional, for vehicles, airdrops and events that only load once they appear: create
    probe-settings.lua next to this file with   return { lateScanMinutes = 45 }
    and the probe scans again 45 minutes later. That scan freezes the server for a few
    seconds, so do it when few people are on.
 4. Download ue4ss/Mods/ExclsvProbe/probe-output.txt from the File Manager.
 5. Disable or delete the mod afterwards.

Optional: a probe-settings.lua next to this file (an old probe.lua is ignored) narrows the search to one topic, e.g.
  return { title = "Item probe", keywords = { "item", "inventory" }, nativeOnly = true,
           wholeClasses = { "inventory" } }

In wholeClasses, a word starting with "=" must be the whole class name ("=item" is the Item
class only); other words match any class whose name contains them.
