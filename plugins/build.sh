#!/usr/bin/env bash
# Builds plugins/dist/scum-manager.zip, ready for Admin -> Plugins -> Import from file.
# The mods in mods/dist (except the probe) are bundled into resources/mods first.
set -euo pipefail
cd "$(dirname "$0")"
bash ../mods/build.sh >/dev/null
mkdir -p dist scum-manager/resources/mods
rm -f scum-manager/resources/mods/*.zip scum-manager/resources/mods/manifest.json
for mod in ExclsvConsole ExclsvPlayerTools ExclsvAntiCheat ExclsvMessages; do
    cp "../mods/dist/$mod.zip" scum-manager/resources/mods/
done
cp ../mods/dist/manifest.json scum-manager/resources/mods/manifest.json
rm -f dist/scum-manager.zip
zip -qr dist/scum-manager.zip scum-manager -x 'scum-manager/tests/*'
echo "Built $(pwd)/dist/scum-manager.zip"
