#!/bin/bash
# Watches the real, installed Forecast while it runs.
#
#   scripts/runtime-watch.sh [path/to/Forecast.app] [--seconds 60] [--canary "word"]
#
# Launches Forecast, then for the given time checks its processes (app and widget) for open network
# connections and records everything they write to the system log.
#
# --canary: a word from one of your meeting titles. The watch fails if that word shows up in the log or
# anywhere in Forecast's data folders (including the widget snapshots macOS keeps). The word is only
# compared on your Mac; this script prints a summary, never the log itself.
#
# Add a Forecast widget to your desktop first, so the widget is watched too.

set -euo pipefail
APP="/Applications/Forecast.app"
SECONDS_TO_WATCH=60
CANARY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --seconds) SECONDS_TO_WATCH="$2"; shift 2 ;;
        --canary) CANARY="$2"; shift 2 ;;
        *) APP="$1"; shift ;;
    esac
done
[ -d "$APP" ] || { echo "Forecast isn't at $APP. Pass the app's path."; exit 1; }

APP_ID=$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")
WIDGET_ID=$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/PlugIns/ForecastWidgetExtension.appex/Contents/Info.plist")
WORK=$(mktemp -d)
LOG="$WORK/forecast.log"
LOGGER=""
cleanup() { if [ -n "$LOGGER" ]; then kill "$LOGGER" 2>/dev/null || true; wait "$LOGGER" 2>/dev/null || true; fi; }
trap cleanup EXIT

was_running=0
pgrep -x Forecast >/dev/null && was_running=1

log stream --style compact --level info \
    --predicate 'process == "Forecast" OR process == "ForecastWidgetExtension"' > "$LOG" 2>/dev/null &
LOGGER=$!
sleep 1

echo "Launching Forecast and watching for ${SECONDS_TO_WATCH}s…"
open "$APP"

net_hits=0
saw_app=0
saw_widget=0
end=$((SECONDS + SECONDS_TO_WATCH))
while [ $SECONDS -lt $end ]; do
    for name in Forecast ForecastWidgetExtension; do
        for pid in $(pgrep -x "$name" || true); do
            if [ "$name" = Forecast ]; then saw_app=1; else saw_widget=1; fi
            # Any internet socket at all (IPv4 or IPv6) counts.
            # lsof exits non-zero when it finds nothing, which is the result we want.
            sockets=$( { lsof -nP -a -p "$pid" -i 2>/dev/null || true; } | tail -n +2 | wc -l | tr -d ' ')
            if [ "$sockets" -gt 0 ]; then
                net_hits=$((net_hits + sockets))
                { lsof -nP -a -p "$pid" -i 2>/dev/null || true; } | tail -n +2 >> "$WORK/network.txt"
            fi
        done
    done
    sleep 0.5
done
cleanup
LOGGER=""

if [ $was_running = 0 ]; then pkill -x Forecast 2>/dev/null || true; fi

failures=0
echo
printf 'App process seen:     %s\n' "$([ $saw_app = 1 ] && echo yes || echo no)"
printf 'Widget process seen:  %s\n' "$([ $saw_widget = 1 ] && echo yes || echo 'no (add a Forecast widget to your desktop to include it)')"
if [ $net_hits -eq 0 ]; then
    echo "Network connections:  none"
else
    echo "Network connections:  $net_hits seen (details in $WORK/network.txt)"
    failures=$((failures + 1))
fi
lines=$(grep -c . "$LOG" 2>/dev/null || true)
echo "System log lines:     ${lines:-0} (full log, kept on this Mac: $LOG)"

if [ -n "$CANARY" ]; then
    if grep -qiF -- "$CANARY" "$LOG"; then
        echo "Canary in the log:    FOUND"
        failures=$((failures + 1))
    else
        echo "Canary in the log:    not found"
    fi
    found_in=""
    for id in "$APP_ID" "$WIDGET_ID"; do
        dir="$HOME/Library/Containers/$id/Data"
        [ -d "$dir" ] || continue
        if grep -rqiF -- "$CANARY" "$dir" 2>/dev/null; then found_in="$found_in $id"; fi
    done
    if [ -n "$found_in" ]; then
        echo "Canary in data:       FOUND in$found_in"
        failures=$((failures + 1))
    else
        echo "Canary in data:       not found in Forecast's data folders or widget snapshots"
    fi
else
    echo "Canary:               not checked (pass --canary \"a word from one of your meeting titles\")"
fi

echo
if [ $failures -gt 0 ]; then
    echo "Runtime watch FAILED."
    exit 1
fi
echo "Runtime watch passed."
