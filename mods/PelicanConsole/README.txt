PelicanConsole

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
 - With no admin online the mod falls back to SCUM's internal
   MiscStatics.Test_ProcessAdminCommand, which SCUM ignores for most commands.
