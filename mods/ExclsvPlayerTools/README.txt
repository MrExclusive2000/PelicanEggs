ExclsvPlayerTools

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
  Welcome back   Returning players see their playtime, kills and deaths when they join.
  Playtime       A reward for every hour played and a daily login bonus (100 / 200 cash).
  Kill streaks   "Alice is on a 5 kill streak!" and "Bob ended Alice's 5 kill streak!".
                 Killing the same player again within 30 minutes does not count.
  Bounties       The server puts a bounty on players with a 5+ kill streak; whoever kills
                 them collects it. !bounty lists bounties. Player-placed bounties
                 (!bounty <name> <amount>) are off: the mod cannot check balances yet.
  Teleports      !tp <place>: stand still 10 s, pay, teleport. Admins set places on the
                 settings page; !where (admins only) shows your coordinates.
                 !tpto <name> asks to teleport to another player; they type !tpaccept
                 (or !tpdeny) within 60 s. Same cooldown and stand-still time.
  Info           !info: server time, uptime, players online, next restart.
  Reports        !report <name> <what happened>: reports.log, the Admin Console page and
                 every online admin.
  Feature tips   "This server has: ..." to each player on joining, and a rotating tip to
                 everyone every 20 minutes. Built from the settings, so they only mention
                 what is switched on.
  Death recap    Who killed you, with what, from how far (and their kill streak).
  Hotspots       "Heavy fighting reported in sector B2!" after several kills close together.
                 Sectors are worked out from the four outposts (A0, B4, C2, Z3); if they do
                 not fit SCUM's grid, the nearest teleport destination is used instead.
  !seen <name>   When a player was last online.
  Manhunt        Players volunteer with !manhunt join. Every hour (with 3+ online) one becomes
                 the target for 15 minutes; their sector is announced every 3 minutes. The
                 killer, or the target if they survive, gets the reward (1000 cash).
  King of the    Every 90 minutes one of your zones is announced; whoever stays inside it the
  Hill           longest in 15 minutes wins (1000 cash). Add zones on the settings page or
                 with "Add a place where a player stands" on the Admin Console.

Economy (all off until switched on; they need an admin online or the no-admin route, and every
purchase checks the player's balance first; winnings wait in players.tsv until paid):
  !shop, !buy    Items you list with prices. The money is taken, then the item goes into the
                 inventory; if it cannot be handed over, the money is refunded.
  !sell          Hold an item and type !sell: it is dropped (SCUM's own drop), removed, then
                 you are paid. !sell prices lists what the server buys. Never list containers.
  !pay           !pay <name> <amount> to another online player, with an optional fee.
  !lottery       Tickets for a pot drawn every hour; the house keeps a share. Too few tickets:
                 everyone is refunded. Tickets survive restarts (lottery.tsv).
  !tasks         Daily tasks: minutes played, player kills, a long-range kill. Paid when done.
  Kill race      Every 2 hours: most player kills in 20 minutes wins. !race shows the score.
  Squad bonus    Every hour, a little for every squadmate online with you.
  Kills between squadmates, and suicides, never count for tasks or the race.

Not yet confirmed on a live server (off unless set; try them on yourself first):
 - Item lists for the starter kit, hourly rewards, the daily bonus, manhunt and King of the
   Hill: items go straight into the player's inventory (or at their feet when it is full),
   no admin needed. One switch turns all item giving on or off: itemRewards.enabled
   ("Item rewards" on the settings page). Off by default.
 - teleports.method = "direct": moves the player without an admin.

Settings: config.lua in this folder, or the "SCUM Mod Settings" page of the SCUM Manager
plugin. Changes are picked up within 30 seconds.

Good to know:
 - Chat commands and the kill feed read SCUM's own logs in SCUM/Saved/SaveFiles/Logs
   (chat_*.log and kill_*.log). Only chat written after the server started is read.
 - Votes, starter kits, rewards, bounty payouts and teleports run SCUM admin commands
   (SetTime, ChangeCurrencyBalance, Teleport <player> <x> <y> <z>...) through an online admin's chat command
   channel, exactly as if that admin typed them. Rewards, kits and payouts wait until an admin
   is online; votes, bounties and teleports say they cannot be done right now, unless the
   no-admin route below covers them.
 - Bounties and teleports check the player's balance before charging (checkBalance, on).
 - Without an admin (confirmed on a live server): when the file no-admin-commands.txt exists
   in the ExclsvConsole mod folder, ChangeCurrencyBalance, ChangeFamePoints, SpawnItem,
   Teleport, SetTime and SetWeather run with no admin online, as the player they are for (see
   ExclsvConsole's README). Rewards, bounty payouts, charges and passed votes then happen
   straight away. Delete the file
   to go back to waiting for an admin; a restart always restores SCUM's own settings.
 - Starter kit items: while starterKitItems is empty, starterKitPreset = "basic" gives 2
   water, tuna, beans, 2 apples, 3 bandages, a knife and a small backpack. Items need "Give
   items" on, and an item type is only given once SCUM has loaded it on the server (the log
   names any that were skipped: spawn one with SpawnItem as an admin).
 - Kills between squadmates still count in stats but not for kill streaks or bounties
   (stops bounty farming with friends). Squads are checked every 30 seconds.
 - Replies to a player who is driving or dead arrive as an on-screen notice instead of a
   chat line.
 - online.tsv lists who is online, where, for how long and their ping, rewritten every 15
   seconds. The panel's Overview and Console pages show it.
 - deaths.log lists every death for the panel's Console page: kills by players from SCUM's kill
   log (with weapon and distance), and every other death (suicides, crashes, zombies, falls,
   hunger...) from SCUM.log, about 15 seconds later; SCUM.log does not say what killed them.
   Kept to about 512 KB; older lines go to deaths.old.log.
 - economy.log lists every money movement the mod makes (rewards, shop, sales, payments, lottery,
   tasks, races, bounties, teleports) with what it was for; winnings are logged when earned.
   Kept to about 1 MB; older lines go to economy.old.log. The panel's Economy page shows it.
 - players.tsv is copied once a day to players.backup-<date>.tsv; the last 7 are kept. To
   restore, stop the server and copy a backup over players.tsv.
 - Starter kit commands are SCUM admin commands without the "#", with {steamId} and {name}
   replaced by the new player. The default gives 500 cash:
       ChangeCurrencyBalance Normal 500 {steamId}
   Only use commands that name the player. SpawnItem has no target: it drops the items in
   front of the admin the command runs as, not the new player.
 - The first time the mod runs, every player who joins counts as new once.
