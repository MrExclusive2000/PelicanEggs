ExclsvPlayerTools (mod folder: PlayerTools)

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

Experimental (found by the probe, not yet confirmed on a live server; off unless set):
 - Item lists for the starter kit, hourly rewards, the daily bonus, manhunt and King of the
   Hill: items go straight into the player's inventory (or at their feet when it is full),
   no admin needed. One switch turns all item giving on or off: itemRewards.enabled
   ("Item rewards" on the settings page). Off by default.
 - teleports.method = "direct": moves the player without an admin.
 - checkBalance (bounties, teleports): reads the player's money first and refuses what they
   cannot pay. Turn it on for bounties before allowing player bounties.

Settings: config.lua in this folder, or the "SCUM Mod Settings" page of the SCUM Manager
plugin. Changes are picked up within 30 seconds.

Good to know:
 - Chat commands and the kill feed read SCUM's own logs in SCUM/Saved/SaveFiles/Logs
   (chat_*.log and kill_*.log). Only chat written after the server started is read.
 - Votes, starter kits, rewards, bounty payouts and teleports run SCUM admin commands
   (SetTime, ChangeCurrencyBalance, Teleport <player> <x> <y> <z>...) through an online admin's chat command
   channel, exactly as if that admin typed them. So an admin from AdminUsers.ini must be
   online. Rewards, kits and payouts wait until one is; votes, bounties and teleports say
   they cannot be done right now. With noAdminFallback on (EXPERIMENTAL, off by default: it
   reads balances, which may have crashed a server), PlayerTools checks once
   per run whether SCUM accepts these commands without an admin (1 coin added to a player
   and taken back) and uses that route if it works. The log says which way it went.
 - Starter kit items: while starterKitItems is empty, starterKitPreset = "basic" gives 2
   water, tuna, beans, 2 apples, 3 bandages, a knife and a small backpack. Items need "Give
   items" on, and an item type is only given once SCUM has loaded it on the server (the log
   names any that were skipped: spawn one with SpawnItem as an admin).
 - online.tsv lists who is online, where and for how long, rewritten every 15 seconds. The
   panel's ExclsvSCUM Overview page shows it.
 - players.tsv is copied once a day to players.backup-<date>.tsv; the last 7 are kept. To
   restore, stop the server and copy a backup over players.tsv.
 - Starter kit commands are SCUM admin commands without the "#", with {steamId} and {name}
   replaced by the new player. The default gives 500 cash:
       ChangeCurrencyBalance Normal 500 {steamId}
   Only use commands that name the player. SpawnItem has no target: it drops the items in
   front of the admin the command runs as, not the new player.
 - The first time the mod runs, every player who joins counts as new once.
