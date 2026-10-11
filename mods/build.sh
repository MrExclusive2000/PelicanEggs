#!/usr/bin/env bash
# Builds mods/dist/<Mod>.zip for every mod, ready for the SCUM Mods page. Tests are left out.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist
for mod in */; do
    mod=${mod%/}
    [ "$mod" = dist ] && continue
    [ -f "$mod/Scripts/main.lua" ] || continue
    rm -f "dist/$mod.zip"
    zip -qr "dist/$mod.zip" "$mod" -x "$mod/tests/*"
    echo "Built dist/$mod.zip"
done
