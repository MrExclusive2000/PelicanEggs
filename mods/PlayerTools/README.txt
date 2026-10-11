PlayerTools

Quality-of-life features for SCUM players:

  Chat commands  Players type these in game chat; the reply goes only to them.
                 !help, !rules, !discord, !online, !stats [name], !top, !vote <option>, !yes, !no
  Kill feed      Announces kills on everyone's screen: "Alice killed Bob with AK47 (250 m)".
  Stats          Kills, deaths, K/D, longest kill and playtime per player (players.tsv).
                 Optional leaderboard announcement every N minutes.
  AFK kicker     Warns, then kicks players who have not moved or looked around for N minutes.
                 Admins can be left alone. Off by default.
  Voting         !vote day / night / sun (configurable). Passed votes run a SCUM admin command.
  New players    Private messages on a player's first join, and an optional starter kit.

Settings: config.lua in this folder, or the "SCUM Mod Settings" page of the SCUM Manager
plugin. Changes are picked up within 30 seconds.

Good to know:
 - Chat commands and the kill feed read SCUM's own logs in SCUM/Saved/SaveFiles/Logs
   (chat_*.log and kill_*.log). Only chat written after the server started is read.
 - Votes and starter kits run SCUM admin commands (SetTime, SpawnItem, ...) through an
   online admin's chat command channel, exactly as if that admin typed them. So an admin
   from AdminUsers.ini must be online: a passed vote with no admin online is announced as
   "cannot be applied right now", and starter kits wait until an admin is online.
 - Starter kit commands are SCUM admin commands without the "#". {location} is replaced
   with where the player stands (X=... Y=... Z=...), {steamId} and {name} with the player.
   Example: SpawnItem Water_05l 1 Location "{location}"
 - The first time the mod runs, every player who joins counts as new once.
