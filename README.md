# Forecast

**Your calendar as the weather.** A macOS desktop widget that turns your day into a forecast.
Back-to-back meetings roll in as a thunderstorm. An empty afternoon is sunshine.

> Forecast reads your calendar and provides a view of what to expect for the day.

It has no network access, keeps nothing, and is small enough to read in an afternoon.
Fork it, build it, and run it as your own local app.

## The weather

| Your calendar | Forecast |
|---|---|
| Nothing on | ☀️ Sunshine |
| Under a quarter of the workday | 🌤 Partly cloudy |
| A quarter to a half | ☁️ Overcast |
| Half or more | 🌧 Showers |
| Three or more back-to-back, double-booked, or ¾ of the day | ⛈ Thunderstorms |

"Back-to-back" means less than 10 minutes between meetings. The big number is **cover**:
the share of your workday spent in meetings, like cloud cover. Each widget shows today, the
next few hours, and (large size) the days ahead.

All-day events, events marked *Free*, and cancelled events don't count.

**Breaks count as free time.** People block out time to eat, walk the dog, go to the gym or just
breathe. Forecast spots events titled like *Lunch*, *Break*, *Gym*, *Walk*, *Meditation* or *Yoga*
and keeps that time sunny. Titles that sound like work stay as meetings, for example
*Lunch & Learn*, *Working lunch* or *Walk and call*. The word lists are in
[`Shared/BreakMatcher.swift`](Shared/BreakMatcher.swift). You can turn this off in the app, or per
widget in *Edit "Forecast"*.

## Seasons

Pick a palette per widget: **Spring** (blossoms), **Summer** (beach and sea), **Autumn**
(pumpkins and leaves) or **Winter** (snow). In winter, showers fall as snow and storms become
blizzards. *Match the date* picks the season automatically, flipped for the southern hemisphere
(guessed from your time zone, no location access needed).

## Privacy, and how to check it yourself

Forecast makes three promises. Each one is enforced by the operating system or checked by
a script, so you don't have to take them on trust.

**1. Nothing leaves your Mac.** The app and widget run in the macOS App Sandbox *without* the
network entitlement. macOS refuses to let a sandboxed app open a network connection unless it
holds that entitlement, so Forecast can't reach the internet even if someone tried.
Check the signed app:

```sh
codesign -d --entitlements - Forecast.app
codesign -d --entitlements - Forecast.app/Contents/PlugIns/ForecastWidgetExtension.appex
```

Both list exactly two entitlements: `app-sandbox` and `personal-information.calendars`.
Neither has `network.client` or `network.server`.

**2. Only what it needs is read.** Every calendar read goes through one file,
[`Shared/CalendarReader.swift`](Shared/CalendarReader.swift). It reads each event's start, end,
all-day flag, free/busy flag and cancelled status, then keeps only start and end. For the break
check, it passes the title to `BreakMatcher.isBreak`, which answers yes or no; the title isn't
kept, shown or logged. Notes, locations, attendees, URLs and calendar names are never touched.
Turn off *Count breaks as free time* and titles aren't read at all. (macOS has no times-only
calendar permission, so Forecast has to ask for full access.)

**3. Nothing is kept, and nothing can get in.** No database, no logs, no analytics, no file
writes, no clipboard access. There are no URL schemes, services or Apple Events, so other apps
can't send Forecast commands. Hardened runtime is on, so nothing can attach to or inject code
into it. There are no third-party dependencies and no build scripts. It's pure Swift on Apple
frameworks only. The one bundled asset is the [Inter](https://github.com/rsms/inter) typeface
(v4.1, SIL Open Font License), with each file's checksum pinned so you can verify it against the
official release.

### The audit script

[`scripts/privacy-audit.sh`](scripts/privacy-audit.sh) checks all of the above and fails loudly
if anything changes:

```sh
scripts/privacy-audit.sh                                          # check the source
scripts/privacy-audit.sh build/Build/Products/Release/Forecast.app   # also check a built app
```

It checks that:
- the entitlements are on an allowlist, and the sandbox is on;
- only one file imports EventKit, and it reads only allowlisted event fields and never writes;
- the title is used exactly once, as input to the yes/no break check;
- there's no networking, web view, scripting, dynamic loading, file I/O or logging API anywhere;
- there's no C, Objective-C, JavaScript, prebuilt binaries, dependencies or build scripts;
- the bundled Inter fonts match the checksums pinned in `Shared/Fonts/Inter.sha256`;
- no team IDs, certificates, provisioning profiles or email addresses are in the repo;
- the built app's signature is valid, with hardened runtime on, no debugger entitlement, and no networking frameworks linked.

The tests back this up: thousands of random calendars (including daylight-saving days and reversed or
overlapping times) and hostile titles (a million characters, control characters, injection strings),
plus a check that nothing the widget hands to macOS contains any text. The build treats every warning
and possible data race as an error.

CI runs all of this on every push and pull request.

## Install

You need macOS 14 or later and Xcode 26 or later (free from the App Store). Liquid Glass shows on
macOS 26; older versions get a frosted fallback. You don't need an Apple developer account.

> **Full Xcode is required. Command Line Tools alone won't work.** Building a widget needs
> `xcodebuild` and Apple's App Intents tooling, which only ship with the full Xcode app.
> Check before you start:
>
> ```sh
> xcodebuild -version
> ```
>
> If that prints an Xcode version, you're set. If it says
> *"tool 'xcodebuild' requires Xcode, but active developer directory … is a command line tools instance"*,
> install Xcode from the App Store, open it once to finish setup, then point the command line at it:
>
> ```sh
> sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
> ```

### From the command line

```sh
# 1. Get the code
git clone https://github.com/andreasaez/forecast.git
cd forecast

# 2. Optional: check the privacy promises before building
scripts/privacy-audit.sh

# 3. Build
xcodebuild -project Forecast.xcodeproj -scheme Forecast -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build build

# 4. Install into Applications and check the installed app
ditto build/Build/Products/Release/Forecast.app /Applications/Forecast.app
scripts/privacy-audit.sh /Applications/Forecast.app

# 5. Remove the build copy, so macOS only knows about the installed app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u build/Build/Products/Release/Forecast.app
rm -rf build

# 6. Open it
open /Applications/Forecast.app
```

### From Xcode

```sh
git clone https://github.com/andreasaez/forecast.git
cd forecast
open Forecast.xcodeproj      # then press ⌘R
```

### First run

1. Forecast opens and explains what it reads. Click **Allow calendar access**.
2. Right-click the desktop › **Edit Widgets** › search for **Forecast** and add a size.
3. Right-click the widget › **Edit "Forecast"** to choose its season, working hours, and whether
   breaks count as free time.

**Signing.** Out of the box, Forecast signs to run locally with no Apple ID. If the widget
doesn't show up in the gallery, sign with your own (free) Apple ID instead, then build again:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then fill in your team ID
```

`Config/Local.xcconfig` is git-ignored, so your team ID never ends up in a commit or a fork.

## Uninstall

**First, remove Forecast's widgets from your desktop** (right-click each one › **Remove Widget**).
If you delete the app first, macOS can leave a widget stuck on the desktop.

```sh
# 1. Quit Forecast
pkill -x Forecast

# 2. Remove its calendar permission (do this while the app is still installed)
tccutil reset Calendar local.forecast

# 3. Delete the app and forget it
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u /Applications/Forecast.app
rm -rf /Applications/Forecast.app

# 4. Remove its settings (season, onboarding) and macOS's widget snapshots
rm -rf ~/Library/Containers/local.forecast ~/Library/Containers/local.forecast.widget

# 5. Refresh the widget gallery
killall chronod
```

If step 4 says *Operation not permitted*, macOS is protecting the folders. Run
`open ~/Library/Containers`, drag both `local.forecast` folders to the Trash, and empty it.

If you set your own `BUNDLE_ID_PREFIX` in `Config/Local.xcconfig`, replace `local.forecast` above
with your app's bundle ID.

## Tests

```sh
xcodebuild test -project Forecast.xcodeproj -scheme Forecast -destination 'platform=macOS'
```

## Project layout

```
App/        The app: onboarding, season picker, live preview, app icon
Widget/     The widget: configuration, timeline, layouts
Shared/     Used by both
  CalendarReader.swift   The only code that touches the calendar
  BusyInterval.swift     The only calendar data kept: start and end
  ForecastEngine.swift   Meetings → weather (pure logic, no I/O)
  Season.swift           Palettes, motifs and weather words per season
  BreakMatcher.swift     Spots breaks (Lunch, Gym, Walk) so they count as free time
  Typography.swift       Inter
  Fonts/                 Inter v4.1 (SIL Open Font License), checksums in Inter.sha256
  ForecastViews.swift    The widget layouts, also used for the app's preview
Tests/      Engine tests
Config/     Entitlements, build settings, widget Info.plist
scripts/    privacy-audit.sh
```

## Known limitations

- **Declined invitations still count.** Your RSVP is stored on the attendee list, and Forecast
  never reads attendees. Mark an event *Free* if you want it ignored.
- **Break spotting is word matching.** It's English only and can guess wrong. Marking an event
  *Free* always works, whatever it's called.
- **The widget reads the calendar itself.** It needs the app to have been opened once to grant
  access. If it shows "Open Forecast to allow calendar access", open the app.
- macOS keeps rendered widget snapshots in its own system caches, as it does for every widget.
  Those snapshots show weather, times and percentages, never event details.

## License

Code: MIT. See [LICENSE](LICENSE).
Inter typeface: SIL Open Font License 1.1. See [Shared/Fonts/Inter-LICENSE.txt](Shared/Fonts/Inter-LICENSE.txt).
