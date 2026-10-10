#!/usr/bin/env bash
# Builds plugins/dist/scum-manager.zip, ready for Admin -> Plugins -> Import from file.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist
rm -f dist/scum-manager.zip
zip -qr dist/scum-manager.zip scum-manager -x 'scum-manager/tests/*'
echo "Built $(pwd)/dist/scum-manager.zip"
