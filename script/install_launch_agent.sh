#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Worktime.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Worktime"
TEMPLATE="$ROOT_DIR/launchd/dev.benj.Worktime.plist.template"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs/Worktime"
PLIST="$LAUNCH_AGENTS_DIR/dev.benj.Worktime.plist"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Worktime.app is missing. Build it first with ./script/build_and_run.sh --verify" >&2
  exit 1
fi

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Worktime executable is missing. Build it first with ./script/build_and_run.sh --verify" >&2
  exit 1
fi

mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR"

sed \
  -e "s#__WORKTIME_APP_EXECUTABLE__#$APP_EXECUTABLE#g" \
  -e "s#__WORKTIME_LOG_DIR__#$LOG_DIR#g" \
  "$TEMPLATE" > "$PLIST"

plutil -lint "$PLIST"

launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl enable "gui/$UID/dev.benj.Worktime"
launchctl kickstart -k "gui/$UID/dev.benj.Worktime"

echo "Installed dev.benj.Worktime LaunchAgent:"
echo "  $PLIST"
echo "Lifedata URL: http://100.94.53.42:8787"
