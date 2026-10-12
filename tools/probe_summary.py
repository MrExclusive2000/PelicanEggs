#!/usr/bin/env python3
"""Summarise an ExclsvProbe report (probe-output.txt) per planned feature.

    python3 tools/probe_summary.py probe-output.txt > probe-summary.md

For each feature it lists the functions, stored values, events, enums and structs whose
names fit, best candidates first: server-side native functions and hookable events rank above
Blueprint helpers, and client-only functions (Client_*, NetClient) are listed last because a
server mod cannot use them to change anything. It only reads the text report.
"""

import re
import sys
from collections import defaultdict

# feature -> (what we need it for, name patterns)
FEATURES = {
    "Money without an admin online": (
        "Pay rewards, bounties and teleports when no admin is in game.",
        [r"currency", r"balance", r"money", r"(add|give|set|change).*(cash|gold|fame)"],
    ),
    "Admin rights check": (
        "Run one whitelisted command for a player without making them admin.",
        [r"admin", r"isadmin", r"rights", r"privilege", r"processadmincommand"],
    ),
    "On-screen notices": (
        "Pop-up messages instead of chat lines (events, warnings, rewards).",
        [r"notif", r"popup", r"toast", r"screenmessage", r"showmessage", r"hud.*message"],
    ),
    "Map markers": (
        "Mark King of the Hill zones, airdrops or events on players' maps.",
        [r"marker", r"waypoint", r"mapicon", r"minimap"],
    ),
    "Raid window": (
        "Allow base damage only at set times.",
        [r"raid", r"baseelement.*damage", r"damage.*(baseelement|building)", r"flag.*(damage|protect)", r"canbedamaged"],
    ),
    "Squads": (
        "Squad size limits, squad chat commands, squad-aware anti-cheat.",
        [r"squad"],
    ),
    "Mine and trap protection": (
        "Stop mines and traps near traders, safe zones or spawn points.",
        [r"\bmine\b|landmine|claymore", r"trap", r"tripwire", r"explosive.*(place|arm)"],
    ),
    "Vehicle rental and limits": (
        "Spawn a rented vehicle, find a player's vehicles, count vehicles per player.",
        [r"vehicle.*(spawn|owner|destroy|lock)", r"(spawn|owner|destroy|lock).*vehicle", r"fuel"],
    ),
    "Loot zones": (
        "Change or boost loot in an area.",
        [r"loot", r"spawner", r"itemspawn"],
    ),
    "Kills and deaths": (
        "React to kills instead of reading the kill log late.",
        [r"killed", r"killer", r"death", r"ondied", r"die\b"],
    ),
    "Player join and leave": (
        "Welcome, starter kits and backups at the right moment.",
        [r"login", r"logout", r"postlogin", r"onplayerjoin", r"disconnect"],
    ),
    "Traders": (
        "Trader prices, a shop command, trader safe zones.",
        [r"trader", r"trade", r"shop", r"price"],
    ),
}

SINGULAR = {"functions": "function", "properties": "property", "events": "event", "enums": "enum", "structs": "struct"}


def parse(text):
    """-> list of (kind, line, flags) for every entry in the report."""
    entries = []
    kind = None
    lines = text.splitlines()
    for index, line in enumerate(lines):
        header = re.match(r"^== (\w[\w ,()]*?)(?: \(.*\))? ==$", line)
        if header:
            name = header.group(1).lower()
            kind = ("functions" if name.startswith("functions") or name.startswith("key classes")
                    else "events" if "events" in name
                    else "properties" if name.startswith("properties")
                    else "enums" if name.startswith("enums")
                    else "structs" if name.startswith("structs")
                    else None)
            continue
        if line.startswith("######## ") or line.startswith("== ") or not line.strip():
            if line.startswith("######## "):
                kind = None
            continue
        if kind is None or line.startswith("    "):
            continue
        flags = ""
        if kind == "functions" and index + 1 < len(lines) and lines[index + 1].startswith("    flags="):
            flags = lines[index + 1].strip()
        entries.append((kind, line.strip(), flags))
    return entries


def member_name(line):
    """'/Script/ConZ.Foo:Bar (X: Int)' -> 'Bar'; '/Script/ConZ.Foo.OnBar: Delegate' -> 'OnBar'."""
    head = line.split(" (", 1)[0].split(": ", 1)[0]
    return re.split(r"[:.]", head)[-1]


def rank(kind, line, flags):
    """Lower is better."""
    name = member_name(line).lower()
    score = {"events": 0, "functions": 1, "properties": 2, "enums": 3, "structs": 4}[kind]
    if kind == "functions":
        if "NetClient" in flags or name.startswith("client"):
            score += 20  # runs on players' machines: no use to a server mod
        elif "Native" in flags:
            score -= 0.5
        if line.startswith("/Game/"):
            score += 2
    return score


def summarise(text):
    entries = parse(text)
    out = ["# ExclsvProbe summary", ""]
    header = re.search(r"^Classes scanned: .*$", text, re.M)
    if header:
        out += [header.group(0), ""]
    for feature, (why, patterns) in FEATURES.items():
        regex = re.compile("|".join(f"(?:{p})" for p in patterns), re.I)
        found = defaultdict(list)
        for kind, line, flags in entries:
            if regex.search(member_name(line)) or (kind in ("enums", "structs") and regex.search(line.split(":")[0])):
                found[kind].append((rank(kind, line, flags), line, flags))
        total = sum(len(v) for v in found.values())
        out.append(f"## {feature}: {total} candidate{'s' if total != 1 else ''}")
        out.append(why)
        if total == 0:
            out += ["", "Nothing in the report fits.", ""]
            continue
        best = sorted((item + (kind,) for kind, items in found.items() for item in items))[:25]
        out.append("")
        for score, line, flags, kind in best:
            note = f"  [{flags.replace('flags=', '')}]" if flags else ""
            client = "  (client only)" if score >= 20 else ""
            out.append(f"- {SINGULAR[kind]}: `{line}`{note}{client}")
        if total > len(best):
            out.append(f"- ... and {total - len(best)} more")
        out.append("")
    census = re.search(r"^== Census.*?==\n(.*?)(?:\n\n|\Z)", text, re.M | re.S)
    if census and census.group(1).strip():
        out += ["## World census", "", "```", census.group(1).strip(), "```", ""]
    return "\n".join(out)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
        print(summarise(handle.read()))


if __name__ == "__main__":
    main()
