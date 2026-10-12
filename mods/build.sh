#!/usr/bin/env bash
# Builds mods/dist/<Mod>.zip for every mod, ready for the SCUM Mods page. Tests are left out.
# Also writes mods/dist/manifest.json, which ExclsvSCUM Manager reads from GitHub to update
# the mods: each zip's sha256 (checked after download) and a build id that only changes when
# the mod's files change.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist
entries=()
for mod in */; do
    mod=${mod%/}
    [ "$mod" = dist ] && continue
    [ -f "$mod/Scripts/main.lua" ] || continue
    rm -f "dist/$mod.zip"
    zip -qrX "dist/$mod.zip" "$mod" -x "$mod/tests/*"
    build=$(find "$mod" -type f ! -path "$mod/tests/*" | LC_ALL=C sort | while read -r file; do
        echo "$file"; sha256sum < "$file"
    done | sha256sum | cut -c1-12)
    sha=$(sha256sum "dist/$mod.zip" | cut -d' ' -f1)
    bytes=$(stat -c %s "dist/$mod.zip")
    entries+=("    \"$mod\": { \"file\": \"$mod.zip\", \"build\": \"$build\", \"sha256\": \"$sha\", \"bytes\": $bytes }")
    echo "Built dist/$mod.zip ($build)"
done
manager=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' ../plugins/scum-manager/plugin.json | head -1)
{
    echo "{"
    echo "  \"format\": \"exclsv-mods\","
    echo "  \"manager\": \"$manager\","
    echo "  \"mods\": {"
    last=$(( ${#entries[@]} - 1 ))
    for i in "${!entries[@]}"; do
        if [ "$i" -lt "$last" ]; then echo "${entries[$i]},"; else echo "${entries[$i]}"; fi
    done
    echo "  }"
    echo "}"
} > dist/manifest.json
echo "Wrote dist/manifest.json"
