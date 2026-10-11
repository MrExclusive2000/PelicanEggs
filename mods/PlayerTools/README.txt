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
  Welcome back   Returning players see their playtime, kills and deaths when they join.
  Playtime       A reward for every hour played and a daily login bonus (100 / 200 cash).
  Kill streaks   "Alice is on a 5 kill streak!" and "Bob ended Alice's 5 kill streak!".
                 Killing the same player again within 30 minutes does not count.
  Bounties       The server puts a bounty on players with a 5+ kill streak; whoever kills
                 them collects it. !bounty lists bounties. Player-placed bounties
                 (!bounty <name> <amount>) are off: the mod cannot check balances yet.
  Teleports      !tp <place>: stand still 10 s, pay, teleport. Admins set places on the
                 settings page; !where (admins only) shows your coordinates.
  Info           !info: server time, uptime, players online, next restart.
  Reports        !report <name> <what happened>: reports.log, the Admin Console page and
                 every online admin.

Settings: config.lua in this folder, or the "SCUM Mod Settings" page of the SCUM Manager
plugin. Changes are picked up within 30 seconds.

Good to know:
 - Chat commands and the kill feed read SCUM's own logs in SCUM/Saved/SaveFiles/Logs
   (chat_*.log and kill_*.log). Only chat written after the server started is read.
 - Votes, starter kits, rewards, bounty payouts and teleports run SCUM admin commands
   (SetTime, ChangeCurrencyBalance, Teleport...) through an online admin's chat command
   channel, exactly as if that admin typed them. So an admin from AdminUsers.ini must be
   online. Rewards, kits and payouts wait until one is; votes, bounties and teleports say
   they cannot be done right now.
 - Starter kit commands are SCUM admin commands without the "#", with {steamId} and {name}
   replaced by the new player. The default gives 500 cash:
       ChangeCurrencyBalance Normal 500 {steamId}
   Only use commands that name the player. SpawnItem has no target: it drops the items in
   front of the admin the command runs as, not the new player.
 - The first time the mod runs, every player who joins counts as new once.
