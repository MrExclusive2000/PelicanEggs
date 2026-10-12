ExclsvAntiCheat (mod folder: ScumAntiCheat)

Server-side anti-cheat for SCUM. BattlEye still handles the client side (aimbots, wallhacks,
injected code), which no server mod can see. This catches what cheats leave behind on the server.

Every second, for each player:
  - speed        faster than config.maxFootSpeed on foot / config.maxVehicleSpeed in a vehicle
  - teleport     a jump config.teleportDistance metres further than the speed limit allows between two checks
  - flying       in flying movement mode for config.flyingSeconds (fly hack)
  - hovering     in the air without coming down for config.hoverSeconds (hover / airwalk)
  - map bounds   outside the island, or below config.mapBounds.minZ (noclip, under-map)
These add strikes. config.strikesToAct strikes within config.strikeWindowSeconds trigger the action.

Instant checks (no strikes needed):
  - unauthorized admin  admin rights in game, but the SteamID is not in AdminUsers.ini
  - admin log           an admin command in SCUM's admin_*.log from a SteamID that is not
                        in AdminUsers.ini (admin rights from a cheat)
  - names               names containing config.blockedNames ("admin", "moderator", ...)

Also:
  - watchlist   the console says when a SteamID from config.watchlist joins
  - game logs   SCUM's own violations_*.log and admin_*.log entries are shown in the console;
                with strikeOnGameViolations = true each violation also counts as a strike

Aimbot signs (report "SUSPECT" lines only, unless strikeOnKillFlags = true):
  - long-range kills   past config.maxKillDistance, or a weapon's limit in weaponMaxDistance
                       (pistols, bows); melee kills from further than maxMeleeDistance
  - god-mode kills     the killer had immortality (normally admin-only)
  - desync kills       the killer's own position was far from where the server had them
  - kill rate          config.killRateKills kills within config.killRateMinutes
  - aim snaps          the view jumping 150+ degrees in a tenth of a second right before a
                       kill; reported once it happens on 3 kills (and at least half of them)
  - magic bullets      firearm kills (5 m and further) while the killer's aim stayed more
                       than config.magicBulletDegrees away from the victim the whole time
                       before (silent aim); reported after config.magicBulletPattern kills
Wallhack tracking (EXPERIMENTAL, off until checks.wallTracking = true; "SPECTATE" lines only,
never strikes): once a second, for each player aiming at another player 5-200 m away, the
game is asked (Controller.LineOfSightTo) whether they can see them. Aim that stays on a hidden
player who is moving for config.wallTrackSeconds in a row is flagged. If the game cannot be
asked on this server, the check switches itself off and says why.

These read SCUM's kill_*.log and sample each player's aim 10 times a second. Aimbots run on
the cheater's PC, so this cannot prove anything: it points at who to spectate.

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
