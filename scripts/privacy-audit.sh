#!/bin/bash
# Checks Forecast's privacy promises. Anyone can run it.
#
#   scripts/privacy-audit.sh                    # audit the source code
#   scripts/privacy-audit.sh path/to/Forecast.app   # also audit a built, signed app
#
# It fails if Forecast could reach the network, read event details (beyond the break check),
# write to your calendar, log anything, or ship personal signing details.

set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; failures=$((failures + 1)); }
section() { printf '\n%s\n' "$1"; }

SOURCES="App Widget Shared Tests"
READER="Shared/CalendarReader.swift"

# Entitlements Forecast may have. Anything else fails the audit.
ALLOWED_ENTITLEMENTS="com.apple.security.app-sandbox com.apple.security.personal-information.calendars"
# Added by Xcode when signing with a team. They identify the developer; they grant nothing.
SIGNING_IDENTITY_KEYS="com.apple.application-identifier com.apple.developer.team-identifier"

# True if the plist sets <key> to true. (plutil -extract can't take keys containing dots.)
has_true() { # <plist file> <key>
    plutil -convert xml1 -o - "$1" | grep -A1 "<key>$2</key>" | grep -q '<true/>'
}

check_entitlements() { # <label> <plist file> <extra allowed keys>
    local label="$1" file="$2" allowed="$ALLOWED_ENTITLEMENTS $3" ok=1 key
    for key in $(plutil -convert xml1 -o - "$file" | grep -o '<key>[^<]*</key>' | sed -E 's#</?key>##g'); do
        case " $allowed " in
            *" $key "*) ;;
            *) fail "$label has a disallowed entitlement: $key"; ok=0 ;;
        esac
    done
    if ! has_true "$file" com.apple.security.app-sandbox; then
        fail "$label is not sandboxed"; ok=0
    fi
    [ $ok = 1 ] && pass "$label: sandboxed, calendar only, no network"
    return 0
}

# ---------------------------------------------------------------------------
section "Entitlements (source)"
for file in Config/*.entitlements; do
    check_entitlements "$file" "$file" ""
done
if grep -hE 'ENABLE_(OUTGOING|INCOMING)_NETWORK_CONNECTIONS = YES' Config/*.xcconfig Forecast.xcodeproj/project.pbxproj >/dev/null; then
    fail "a build setting turns on network access"
else
    pass "no build setting turns on network access"
fi
if grep -hE 'CFBundleURLTypes|NSAppTransportSecurity|NSServices|NSAppleEventsUsageDescription' -r Config Forecast.xcodeproj >/dev/null; then
    fail "Info.plist declares URL schemes, services, ATS exceptions or Apple Events"
else
    pass "no URL schemes, services or Apple Events: nothing can send Forecast commands"
fi

# ---------------------------------------------------------------------------
section "Calendar access"
eventkit_files=$(grep -rlE '^[[:space:]]*import[[:space:]]+EventKit' $SOURCES --include='*.swift' || true)
if [ "$eventkit_files" = "$READER" ]; then
    pass "only $READER imports EventKit"
else
    fail "EventKit must be imported only by $READER (found: ${eventkit_files:-none})"
fi

# Event fields that hold private information. None may appear in the reader.
# (title is handled separately below: it may only feed the yes/no break check.)
private_fields='notes|hasNotes|location|structuredLocation|attendees|hasAttendees|organizer|url|URL|calendar|calendarItemIdentifier|eventIdentifier|calendarItemExternalIdentifier|recurrenceRules|alarms|birthdayContactIdentifier'
if grep -nE "\.($private_fields)([^A-Za-z0-9_]|$)" "$READER"; then
    fail "$READER touches a private event field (above)"
else
    pass "no notes, locations, attendees, URLs or calendar names are read"
fi

# The title may be read exactly once, straight into BreakMatcher.isBreak, which returns only a Bool.
title_uses=$(grep -cE '\.title([^A-Za-z0-9_]|$)' "$READER" || true)
title_ok=$(grep -cE 'BreakMatcher\.isBreak\(event\.title\)' "$READER" || true)
if [ "$title_uses" = 1 ] && [ "$title_ok" = 1 ] \
    && grep -qE 'static func isBreak\(_ title: String\?\) -> Bool' Shared/BreakMatcher.swift \
    && [ "$(grep -cE '^import ' Shared/BreakMatcher.swift)" = 1 ] && grep -qE '^import Foundation$' Shared/BreakMatcher.swift; then
    pass "titles are only used for a yes/no break check (BreakMatcher.isBreak) and never kept"
else
    fail "event titles must only be passed to BreakMatcher.isBreak, once, which returns a Bool and imports only Foundation"
fi

allowed_fields=" startDate endDate isAllDay availability status title "
bad_fields=""
for field in $(grep -oE '\bevent\.[A-Za-z_]+' "$READER" | sed 's/event\.//' | sort -u); do
    case "$allowed_fields" in *" $field "*) ;; *) bad_fields="$bad_fields $field" ;; esac
done
if [ -z "$bad_fields" ]; then
    pass "events are read for: startDate, endDate, isAllDay, availability, status (and title, for the break check). Nothing else"
else
    fail "$READER reads event fields outside the allowlist:$bad_fields"
fi
if grep -nE '\$0\.|\$1\.' "$READER"; then
    fail "$READER uses \$0/\$1 shorthand, which hides field access from this audit"
fi

if grep -nE '\.(save|remove|commit|reset)\(|requestWriteOnlyAccess|EKEventEditViewController' "$READER"; then
    fail "$READER can write to the calendar (above)"
else
    pass "read-only: never saves, edits or deletes events"
fi

# ---------------------------------------------------------------------------
section "No way in or out"
forbidden_apis='URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|NWPathMonitor|import Network|CFSocket|CFStream|CFNetwork|socket\(|getaddrinfo|WKWebView|import WebKit|import CloudKit|NSUbiquitous|MultipeerConnectivity|NSXPCConnection|NSAppleScript|NSUserAppleScriptTask|OSAScript|NSUserUnixTask|Process\(|NSTask|posix_spawn|(^|[^.A-Za-z_])system\(|dlopen|dlsym|Bundle\(path|Bundle\(url|NSClassFromString|NSSelectorFromString|perform\(Selector|contentsOf:|FileManager|\.write\(to|FileHandle|UserDefaults\(suiteName|NSPasteboard|print\(|debugPrint\(|dump\(|NSLog|os_log|Logger\(|import OSLog|import os'
if grep -rnE "$forbidden_apis" $SOURCES --include='*.swift'; then
    fail "forbidden API found (above): networking, scripting, dynamic loading, file I/O or logging"
else
    pass "no networking, web views, scripting, dynamic code loading, file I/O, clipboard or logging"
fi

# A link handed to the browser is the one way data could leave a sandboxed app, so links are locked down:
# the only URL allowed is the System Settings privacy page, and it can only be opened one way.
allowed_url='x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars'
allowed_open='NSWorkspace.shared.open(SystemSettings.calendarPrivacy)'
open_calls=$(grep -rnE 'NSWorkspace|openURL|OpenURLAction|(^|[^A-Za-z_])Link[[:space:]]*[({]|LSOpen|NSApp\.open|\.open\(|onOpenURL|handlesExternalEvents' $SOURCES --include='*.swift' || true)
bad_open=$(printf '%s\n' "$open_calls" | grep -v '^$' | grep -vF "$allowed_open" || true)
url_literals=$(grep -rhoE 'URL\(string: *"[^"]*"' $SOURCES --include='*.swift' | sed -E 's/URL\(string: *"//; s/"$//' | sort -u)
bad_urls=$(printf '%s\n' "$url_literals" | grep -v '^$' | grep -vxF "$allowed_url" || true)
dynamic_urls=$(grep -rnE 'URL\((string|fileURLWithPath|filePath|resolvingAliasFileAt|dataRepresentation):[[:space:]]*[^"[:space:]]|URLComponents|URLQueryItem|appendingPathComponent|appending\((path|component|queryItems)' $SOURCES --include='*.swift' | grep -v '^Tests/' || true)
if [ -z "$bad_open" ] && [ "$(printf '%s\n' "$open_calls" | grep -c -F "$allowed_open")" -le 1 ] && [ -z "$bad_urls" ] && [ -z "$dynamic_urls" ]; then
    pass "links: only the System Settings privacy page can be opened, from a fixed address"
else
    [ -n "$bad_open" ] && printf '%s\n' "$bad_open"
    [ -n "$bad_urls" ] && printf '  URL: %s\n' $bad_urls
    [ -n "$dynamic_urls" ] && printf '%s\n' "$dynamic_urls"
    fail "links: a URL could be opened or built beyond the allowed System Settings page (above)"
fi

if find $SOURCES -type f \( -name '*.m' -o -name '*.c' -o -name '*.cpp' -o -name '*.mm' -o -name '*.h' -o -name '*.js' -o -name '*.dylib' -o -name '*.a' -o -name '*.framework' \) | grep -q .; then
    fail "non-Swift code or prebuilt binaries in the source tree"
else
    pass "pure Swift: no C, Objective-C, JavaScript or prebuilt binaries"
fi

# The only non-code files shipped are the Inter fonts, pinned by checksum to the official v4.1 release.
if (cd Shared/Fonts && shasum -a 256 -c --status Inter.sha256) \
    && [ "$(find $SOURCES -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.woff*' \) | wc -l | tr -d ' ')" = "$(wc -l < Shared/Fonts/Inter.sha256 | tr -d ' ')" ]; then
    pass "bundled fonts match their pinned checksums (Inter v4.1, SIL Open Font License)"
else
    fail "font files differ from Shared/Fonts/Inter.sha256, or unlisted fonts were added"
fi

if grep -qE 'XCRemoteSwiftPackageReference|XCLocalSwiftPackageReference|packageProductDependencies' Forecast.xcodeproj/project.pbxproj \
    || [ -f Package.swift ] || [ -f Podfile ] || [ -f Cartfile ]; then
    fail "third-party dependencies found"
else
    pass "no third-party dependencies"
fi

if grep -q 'PBXShellScriptBuildPhase' Forecast.xcodeproj/project.pbxproj; then
    fail "the project runs shell scripts during the build"
else
    pass "no build-time scripts"
fi

# ---------------------------------------------------------------------------
section "Nothing personal in the repo"
if grep -hE 'DEVELOPMENT_TEAM = [A-Z0-9]{10}' Forecast.xcodeproj/project.pbxproj Config/Base.xcconfig >/dev/null; then
    fail "a development team ID is committed; move it to Config/Local.xcconfig"
else
    pass "no team ID committed (personal signing lives in git-ignored Config/Local.xcconfig)"
fi
# Files that would be published: what git would commit, or (without git) everything
# except build output and the git-ignored Local.xcconfig.
if [ -d .git ]; then
    tracked=$(git ls-files --cached --others --exclude-standard)
else
    tracked=$(find . -type f -not -path './build/*' -not -path './.git/*' -not -name '.DS_Store' \
        -not -path './Config/Local.xcconfig' -not -path '*/xcuserdata/*' | sed 's#^\./##')
fi
if printf '%s\n' "$tracked" | grep -E '(^|/)Local\.xcconfig$|\.p12$|\.cer$|\.mobileprovision$|\.provisionprofile$|xcuserdata'; then
    fail "personal signing files would be committed (above)"
else
    pass "no signing certificates, profiles or user data would be committed"
fi
if printf '%s\n' "$tracked" | grep -v '^scripts/privacy-audit.sh$' | tr '\n' '\0' \
    | xargs -0 grep -lE '[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9-]*\.[A-Za-z.]{2,}' 2>/dev/null | grep .; then
    fail "email addresses found in the files above"
else
    pass "no email addresses in the repo"
fi

# ---------------------------------------------------------------------------
if [ $# -gt 0 ]; then
    app="$1"
    section "Built app: $app"
    [ -d "$app" ] || { fail "$app not found"; exit 1; }
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    bundles=("$app")
    for appex in "$app"/Contents/PlugIns/*.appex; do [ -d "$appex" ] && bundles+=("$appex"); done

    for bundle in "${bundles[@]}"; do
        name=$(basename "$bundle")
        if codesign --verify --strict --deep "$bundle" 2>/dev/null; then
            pass "$name: signature valid"
        else
            fail "$name: signature invalid or missing"
        fi

        codesign -d --entitlements - --xml "$bundle" > "$tmp/ent.plist" 2>/dev/null
        if [ ! -s "$tmp/ent.plist" ]; then
            fail "$name: has no entitlements, so it is not sandboxed"
            continue
        fi
        if has_true "$tmp/ent.plist" com.apple.security.get-task-allow; then
            fail "$name: debuggable (get-task-allow), so other processes could attach. Audit a Release build"
        fi
        check_entitlements "$name" "$tmp/ent.plist" "$SIGNING_IDENTITY_KEYS com.apple.security.get-task-allow"

        signature=$(codesign -dv "$bundle" 2>&1)
        if printf '%s' "$signature" | grep -q 'flags=.*runtime'; then
            pass "$name: hardened runtime on (blocks code injection)"
        else
            fail "$name: hardened runtime off"
        fi

        binary="$bundle/Contents/MacOS/$(plutil -extract CFBundleExecutable raw -o - "$bundle/Contents/Info.plist")"
        if otool -L "$binary" | grep -E 'Network\.framework|WebKit\.framework|CFNetwork\.framework|CloudKit\.framework'; then
            fail "$name: links a networking framework (above)"
        else
            pass "$name: links no networking frameworks"
        fi
    done
fi

printf '\n'
if [ $failures -gt 0 ]; then
    printf '\033[31m%d check(s) failed.\033[0m\n' "$failures"
    exit 1
fi
printf '\033[32mAll privacy checks passed.\033[0m\n'
