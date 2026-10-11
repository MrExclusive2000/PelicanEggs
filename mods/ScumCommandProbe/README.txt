ScumCommandProbe (read-only)

Lists SCUM's game functions on a topic, with their parameters. The topic is set in
probe.lua: this version looks for item and inventory functions, to find a way to put
starter kit items straight into a player's inventory. Delete probe.lua for the original
admin/chat/console report.

It only reads Unreal's reflection data. It does not call or change anything in the game.

Use:
 1. Upload this zip on the SCUM Mods page (it is enabled automatically).
 2. Restart the server and wait about 3 minutes after it is online.
 3. Download ue4ss/Mods/ScumCommandProbe/probe-output.txt from the File Manager.
 4. Disable or delete the mod afterwards. It scans once per server start.
