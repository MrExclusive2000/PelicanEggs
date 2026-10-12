"""python3 tools/tests/test_probe_summary.py"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from probe_summary import summarise  # noqa: E402

REPORT = """ExclsvProbe report
Generated: 2026-10-13 10:00:00 UTC (first scan, world loaded)
Classes scanned: 900, matching functions: 4, matching classes: 2

== Summary ==
Squads: 1 classes, 2 functions, 0 properties, 1 events, 1 enums, 1 structs

######## Money, traders and fame ########

== Functions ==
/Script/ConZ.ConZPlayerState:Server_AddCurrency (Amount: IntProperty)
    flags=0x00220CC0 Net,NetReliable,Native,BlueprintEvent,NetServer
/Script/ConZ.ConZPlayerController:Client_ShowCurrencyChange (Amount: IntProperty)
    flags=0x01020CC0 Net,NetReliable,Native,BlueprintEvent,NetClient

== Properties ==
/Script/ConZ.ConZPlayerState.CurrencyBalance: IntProperty

######## Squads ########

== Classes ==
/Script/ConZ.SquadManager  (parent: /Script/Engine.Actor)

== Functions ==
/Script/ConZ.SquadManager:GetSquadMembers (SquadId: IntProperty, ReturnValue: ArrayProperty)
    flags=0x04020401 Native,BlueprintCallable

== Events (delegates) ==
/Script/ConZ.SquadManager.OnSquadChanged: MulticastInlineDelegateProperty

== Enums ==
/Script/ConZ.ESquadMemberRank: ESquadMemberRank::Member=0, ESquadMemberRank::Leader=1

== Structs ==
/Script/ConZ.SquadMemberInfo (UserId: StrProperty, Rank: ByteProperty)

######## Other ########

== Census (live objects right now; a count of 1 can be the class template) ==
    42  /Script/ConZ.VehicleBase  [Vehicles]
     3  /Script/ConZ.SquadManager  [Squads]
"""

failures = 0
count = 0


def check(name, condition):
    global failures, count
    count += 1
    if not condition:
        failures += 1
        print("FAIL:", name)


out = summarise(REPORT)
money = out.split("## Money without an admin online")[1].split("\n## ")[0]
check("money candidates found", "Server_AddCurrency" in money and "CurrencyBalance" in money)
check("server function ranks above stored value", money.index("Server_AddCurrency") < money.index("CurrencyBalance"))
check("client-only function last and marked", money.rstrip().endswith("(client only)") and "Client_ShowCurrencyChange" in money.splitlines()[-1])
squads = out.split("## Squads")[1].split("\n## ")[0]
check("squad event first", squads.split("\n- ")[1].startswith("event: `/Script/ConZ.SquadManager.OnSquadChanged"))
check("squad enum and struct listed", "ESquadMemberRank" in squads and "SquadMemberInfo" in squads)
check("feature with nothing says so", "## Map markers: 0 candidates\nMark King of the Hill" in out and "Nothing in the report fits." in out)
check("census copied", "42  /Script/ConZ.VehicleBase  [Vehicles]" in out)
check("flags shown", "[0x00220CC0 Net,NetReliable,Native,BlueprintEvent,NetServer]" in out)
check("class lines are not counted as members", "SquadManager  (parent" not in out)

print(f"\n{count} checks, {failures} failed")
sys.exit(1 if failures else 0)
