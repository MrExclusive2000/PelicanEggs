# What the ExclsvProbe found (SCUM, October 2026)

From a probe run on 2026-10-12 (15,146 classes). Read-only reflection data; only what changes
what our mods can do is listed.

## Used now

- **`Prisoner:GetSquad()`** (native, read-only): PlayerTools uses it to tell squadmates apart, so
  squad kills do not count for streaks and bounties.
- **`ConZPlayerController:SendHUDMessageToClient(Message, AudioEvent)`** (client RPC on the
  player's controller): on-screen notice to one player. PlayerTools uses it when the player has
  no character (driving or dead), where `Prisoner:SendMessageToClient` cannot reach them.
- **`ERaidProtectionType`**: 0 None, 1 OfflineRaidProtection, 2 FlagSpecificRaidProtection,
  3 GlobalRaidProtection. The Server settings page shows `scum.RaidProtectionType` as a dropdown.

## Fixed because of it

- **`ECurrencyType`** is 0 None, 1 Normal (cash), 2 Gold. PlayerTools read balances with 0 and
  PelicanConsole's Balance command showed 0 as money and 1 as gold. Both now read 1 for cash and
  2 for gold. This affected the balance check before paid teleports and bounties, and the
  automatic "does SCUM run commands without an admin" test, which compares balances.
- Every SCUM function the mods call (KickPlayer, SendMessageToClient, SendHUDMessageToAll,
  IsUserAdmin, GetCurrencyBalanceText, GetFamePointsRounded, Chat_Server_ProcessAdminCommand,
  Test_ProcessAdminCommand, GetSquad) exists with the parameters we pass.

## Not possible (no safe route in the game)

- **Money without an admin:** the only setter is `ConZPlayerController:SetCurrencyBalanceRep`,
  which sets the replicated copy (what the player's screen shows), not the bank balance. Money
  still goes through `ChangeCurrencyBalance` run as an admin, or `MiscStatics:Test_ProcessAdminCommand`
  if a test shows SCUM accepts it.
- **Reading inventories:** nothing in the scanned topics; a dedicated inventory probe
  (`probe-settings.lua` with item/inventory keywords) would be needed first.
- **Kill and death events:** no delegate or hookable event for player deaths; the kill log stays
  the source.

## Worth a closer look later

- `ConZPlayerController:ShowKillFeedNotificationOnClient(Prefix, CharacterName, Suffix, Ping)`:
  SCUM's own kill-feed pop-up, sent to one player. Could replace kill-feed chat lines.
- `GameModeBase:K2_PostLogin / K2_OnLogout` (Blueprint events): join and leave hooks.
- `Prisoner:IsMemberOfMySquad(Prisoner)`, `ConZGameState:GetSquadForPrisoner`: squad-aware checks.
- `GlobalRaidProtectionManager` multicasts: raid start and end announcements already exist in game.
