ExclsvConsole (mod folder: PelicanConsole)

Runs SCUM admin commands sent from the SCUM Manager Admin Console page or the Pelican
console.

Needs UE4SS installed from the SCUM Mods page.

Use:
 1. Upload this zip on the SCUM Mods page (it is enabled automatically).
 2. Restart the server. console.log shows "[PelicanConsole] Ready." once it has loaded.
 3. Once the server is online, send a command from the SCUM Admin Console page (SCUM
    Manager plugin) or the Pelican console, with or without the leading "#".

Output goes to console.log in this folder, shown on the Admin Console page.

How commands run:
 - Announce <message>, ListPlayers and Kick <name> are handled by the mod itself and work
   with no admin in game.
 - Every other command runs through an online admin's chat command channel, as if that
   admin typed it in chat (replies appear in their chat). An admin from AdminUsers.ini
   must be online.
 - With no admin online, SCUM does not run admin commands; the console says so. Money, fame,
   SpawnItem and Teleport commands can still run with the no-admin route below.

Commands without an admin (confirmed on a live server; off until you turn it on):
 - Turn on: create an empty file no-admin-commands.txt in this folder (File Manager:
   SCUM/Binaries/Win64/ue4ss/Mods/PelicanConsole/). No restart needed.
 - Turn off: delete that file. No restart needed. A restart also always puts SCUM's own
   admin levels back, because they are only changed in memory.
 - What it does: for ChangeCurrencyBalance, ChangeFamePoints, SpawnItem and Teleport only,
   it lowers that one command's required admin level, runs it through an online player's own
   command channel and puts the level back at once, on the game thread, so no player can
   use the command in between. It reads the level back afterwards; if that ever fails it
   switches itself off and tells you to restart.
 - Check it on your server:
     Balance <your name>
     AsPlayer <your name> ChangeCurrencyBalance Normal 1 <your SteamID>
     Balance <your name>          (money should be 1 higher)
 - ExclsvAntiCheat (if installed) is told about each command first, so it does not kick the
   player SCUM logs it under.
 - AsPlayer <player> <command> picks who runs it. SpawnItem and Teleport act on whoever runs
   them, so AsPlayer is how to aim them at a player. Other commands with no admin online use
   the first online player.
 - At least one player must be online.

Commands handled by the mod (no admin needed):
 - WhereIs <player>                      a player's coordinates
 - Balance <player>                      money, gold and fame
 - FindOutposts                          the trader outposts on this map (from the bankers)
 - FindItem <text>                       loaded item class names containing the text
 - ListItems                             refresh items.txt now
Not yet confirmed on a live server (try them on yourself first):
 - TeleportPlayer <player> <x> <y> <z>   move a player
 - GiveItem <player> <item> [amount]     put an item in a player's inventory

Item list: SCUM loads item types on demand, so a scan only sees the ones in memory. items.txt
keeps every item type seen (with its path), is refreshed every 30 minutes, and grows as
players meet more items. GiveItem loads an item that is not in memory from its recorded path.
