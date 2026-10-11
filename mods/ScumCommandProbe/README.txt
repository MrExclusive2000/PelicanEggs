ScumCommandProbe (read-only)

Lists SCUM's admin, chat and console related game functions so we can tell whether
console commands from Pelican can be bridged into the game with a Lua mod.

It only reads Unreal's reflection data. It does not call or change anything in the game.

Use:
 1. Upload this zip on the SCUM Mods page (it is enabled automatically).
 2. Restart the server and wait about 3 minutes after it is online.
 3. Download ue4ss/Mods/ScumCommandProbe/probe-output.txt from the File Manager.
 4. Disable or delete the mod afterwards. It scans once per server start.
