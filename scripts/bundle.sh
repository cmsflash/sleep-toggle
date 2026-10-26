#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app=build/SleepToggle.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/SleepToggle" "$app/Contents/MacOS/SleepToggle"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict --verbose=2 "$app"
if [[ "${1:-}" == "--install" ]]; then
    pkill -x SleepToggle || true
    while pgrep -x SleepToggle >/dev/null; do sleep 0.2; done
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/SleepToggle.app"
    ditto "$app" "$HOME/Applications/SleepToggle.app"
    open "$HOME/Applications/SleepToggle.app"
fi
