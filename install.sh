#!/bin/zsh
# Build and install to ~/Applications for day-to-day use on this Mac. Safe to re-run after changes.
# (Others install from the .dmg that build-dmg.sh makes. Opening at login is the app's own
# login item, switched in Places & appearance.)
set -e
cd "${0:A:h}"
./build.sh
pkill -x Halfpast 2>/dev/null && sleep 1 || true
mkdir -p ~/Applications
rm -rf ~/Applications/Halfpast.app
cp -R build/Halfpast.app ~/Applications/
rm -rf build/Halfpast.app   # one copy only, so Spotlight finds a single Halfpast
open ~/Applications/Halfpast.app
echo "installed — rest the pointer on the notch"
