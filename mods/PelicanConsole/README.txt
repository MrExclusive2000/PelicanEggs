PelicanConsole

Runs SCUM admin commands typed into the Pelican console, without an admin in game.

Needs the SCUM egg from this repository (its start command forwards console input to
this mod) and UE4SS installed from the SCUM Mods page.

Use:
 1. Upload this zip on the SCUM Mods page (it is enabled automatically).
 2. Restart the server. The console shows "[PelicanConsole] Ready." once it has loaded.
 3. Once the server is online, type a command in the Pelican console, with or without
    the leading "#", e.g. ListPlayers or Announce Hello.

Output goes to the Pelican console and to console.log in this folder.

The mod calls SCUM's internal MiscStatics.Test_ProcessAdminCommand. Try a harmless
command first. If commands show "Ran:" but have no effect, set COMMAND_PREFIX at the
top of Scripts/main.lua to "" and restart.
