ExclsvMessages

 - Welcome message: shown privately to each player a few seconds after their character spawns.
 - Rotating announcements: your messages (rules, Discord link, ...) broadcast one at a time,
   every config.intervalMinutes.
 - Join/leave log: who came and went, with times, in players.log in this folder and the
   Pelican console.

Announcements use SCUM's "Announce" admin command through the same route as the ExclsvConsole
mod, so get ExclsvConsole working first.

Use:
 1. Edit config.lua (or upload first and edit it in the File Manager under
    SCUM/Binaries/Win64/ue4ss/Mods/ExclsvMessages/config.lua).
 2. Upload this zip on the SCUM Mods page and restart the server.

Restart warnings don't need a mod: add a Pelican schedule that sends the console command
"Announce Server restarts in 10 minutes", then later a power restart.

Uploading the zip again replaces config.lua with the default one. Copy your settings first.
