#!/bin/zsh
# Build, install to ~/Applications and start Zones at login. Safe to re-run after changes.
set -e
cd "${0:A:h}"
./build.sh

pkill -x Zones 2>/dev/null && sleep 1 || true
mkdir -p ~/Applications ~/Library/LaunchAgents
rm -rf ~/Applications/Zones.app
cp -R build/Zones.app ~/Applications/
rm -rf build/Zones.app   # one copy only, so Spotlight finds a single Zones

uid=$(id -u)
plist=~/dotfiles/launchagents/com.rahul.zones.plist
cp "$plist" ~/Library/LaunchAgents/
launchctl bootout gui/$uid/com.rahul.zones 2>/dev/null || true
launchctl bootstrap gui/$uid ~/Library/LaunchAgents/com.rahul.zones.plist
echo "installed — Zones is in the menu bar and starts at login"
