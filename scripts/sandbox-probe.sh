#!/bin/bash
# Live test: does macOS actually stop a program signed like Forecast?
#
#   scripts/sandbox-probe.sh
#
# Builds a small probe (scripts/sandbox-probe/) three times: unprotected as a control, then signed with
# Forecast's real app and widget entitlements plus hardened runtime. Each copy tries to use the network,
# read and write your files, run injected code, and send Apple Events to Finder. Network traffic only
# goes to a listener on 127.0.0.1, and the Apple Event never shows a prompt.
#
# Fails if a Forecast-signed copy gets through anywhere, or if the control can't, which would mean the
# probe itself is broken. Needs Xcode or Command Line Tools, plus python3 and curl.

set -euo pipefail
cd "$(dirname "$0")/.."
SRC=scripts/sandbox-probe
WORK=$(mktemp -d)
SERVER=""
cleanup() {
    if [ -n "$SERVER" ]; then kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "Building the probe…"
xcrun swiftc -O "$SRC/probe.swift" -o "$WORK/probe" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$SRC/Info.plist" 2>/dev/null
xcrun clang -dynamiclib "$SRC/inject.c" -o "$WORK/inject.dylib"
codesign -s - -f "$WORK/inject.dylib" 2>/dev/null

cp "$WORK/probe" "$WORK/control"
cp "$WORK/probe" "$WORK/app"
cp "$WORK/probe" "$WORK/widget"
codesign -s - -f "$WORK/control" 2>/dev/null
codesign -s - -f -o runtime -i local.forecast.sandboxprobe \
    --entitlements Config/Forecast.entitlements "$WORK/app" 2>/dev/null
codesign -s - -f -o runtime -i local.forecast.sandboxprobe \
    --entitlements Config/ForecastWidget.entitlements "$WORK/widget" 2>/dev/null

# A web server on this Mac only, for the network checks to aim at.
PORT=$((50000 + RANDOM % 10000))
mkdir -p "$WORK/www"
(cd "$WORK/www" && exec python3 -I -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
SERVER=$!
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done

run() { # <binary> <output file>
    DYLD_INSERT_LIBRARIES="$WORK/inject.dylib" "$WORK/$1" "$PORT" > "$2" 2>/dev/null || true
    grep -q 'code injection' "$2" || printf 'BLOCKED\tcode injection: an injected library ran inside the process\t\n' >> "$2"
}
run control "$WORK/control.txt"
run app "$WORK/app.txt"
run widget "$WORK/widget.txt"

# One row per check: control | signed like the app | signed like the widget.
status() { # <file> <check name> → ALLOWED, BLOCKED, SKIPPED or "no result"
    local line
    line=$(awk -F'\t' -v name="$2" '$2 == name { print $1; exit }' "$1")
    printf '%s' "${line:-no result}"
}
checks=(
    "network: open a connection"
    "network: make a web request"
    "network: through a child process"
    "files: list ~/Documents"
    "files: read the Calendar database directly"
    "files: write to the Desktop"
    "code injection: an injected library ran inside the process"
    "apple events: send to Finder"
)
# The control must get through these, or the probe isn't really trying.
must_work_unprotected=" network: open a connection|network: make a web request|network: through a child process|code injection: an injected library ran inside the process "

failures=0
printf '\n%-58s %-11s %-11s %s\n' "What the probe tried" "Control" "Forecast" "Widget"
printf '%-58s %-11s %-11s %s\n' "--------------------" "-------" "--------" "------"
for check in "${checks[@]}"; do
    c=$(status "$WORK/control.txt" "$check")
    a=$(status "$WORK/app.txt" "$check")
    w=$(status "$WORK/widget.txt" "$check")
    printf '%-58s %-11s %-11s %s\n' "$check" "$c" "$a" "$w"
    for s in "$a" "$w"; do
        if [ "$s" = "ALLOWED" ]; then failures=$((failures + 1)); fi
    done
    case "|${must_work_unprotected# }|" in
        *"|$check|"*) [ "$c" = "ALLOWED" ] || { echo "  ! the control was blocked here, so this check proves nothing"; failures=$((failures + 1)); } ;;
    esac
    if [ "$check" = "apple events: send to Finder" ] && [ "$c" != "ALLOWED" ]; then
        echo "  (inconclusive: the control couldn't reach Finder either; is Finder running?)"
    fi
done

echo
if [ $failures -gt 0 ]; then
    echo "Sandbox probe FAILED ($failures problem(s) above)."
    exit 1
fi
echo "Sandbox probe passed: macOS blocked every attempt by the Forecast-signed copies."
echo "(macOS keeps an empty sandbox folder for the probe at ~/Library/Containers/local.forecast.sandboxprobe.)"
