# Security

Forecast's promise is simple: it reads only what it needs from your calendar (meeting times, plus a
yes/no check on titles to spot breaks), keeps nothing, and nothing leaves your Mac. If you find a way
that promise could be broken, please report it.

## Reporting

Use GitHub's private vulnerability reporting: **Security › Report a vulnerability** on this
repository. Please don't open a public issue for security problems.

Especially welcome:
- any way for Forecast to send or receive data over a network;
- any code path that reads notes, locations, attendees or other event details, or uses a title for anything but the break check;
- any way for another app or process to send Forecast commands or inject code;
- gaps in `scripts/privacy-audit.sh` that would let one of the above through unnoticed.

## What's tested, and how

| Route out | How it's covered |
|---|---|
| Network | No network entitlement. `sandbox-probe.sh` confirms macOS blocks connections, web requests and child processes. |
| Handing a link to the browser | The audit allows exactly one fixed URL (System Settings) and bans every other way of opening or building one. |
| Apple Events to other apps | No Apple Events entitlement (audit). `sandbox-probe.sh` confirms macOS blocks sending them. |
| Code injection | Hardened runtime, no debugger entitlement in Release (audit). `sandbox-probe.sh` confirms injected libraries don't load. This depends on System Integrity Protection, which is on by default; on a Mac with SIP turned off, macOS doesn't enforce it (CI runners are such machines, so the probe marks that row as not testable there). |
| Reading Forecast's data from another app | No shared app-group container. The widget's own container holds only macOS's widget snapshots, which tests show contain no text. |
| The widget extension | Same entitlements file as the app. The audit checks the built extension, and `sandbox-probe.sh` runs under its entitlements too. |
| The real app at runtime | `runtime-watch.sh` watches the installed app and widget for network connections, and checks the system log and Forecast's data for a word from your own meeting titles. |
| Shortcuts, Siri and Spotlight | The widget's settings intent is marked not discoverable, so only the widget can use it. |
| A malformed calendar event | Events missing a start or end are skipped rather than crashing (tested). |

## Outside Forecast's control

These belong to macOS, not to Forecast, but they're worth knowing:

- **Calendar sync.** If your calendars sync with iCloud, Google or Exchange, macOS's own calendar service does
  that, with or without Forecast.
- **Crash reports.** If Forecast crashes, macOS writes a report, and shares it with Apple if you allow analytics
  (System Settings › Privacy & Security › Analytics). Reports contain stack traces, not your calendar.
- **System logs.** Forecast's code never logs. Apple's frameworks may write their own log lines, with personal
  data redacted by default. `runtime-watch.sh --canary` checks for your titles there.
- **Backups.** Time Machine backs up Forecast's settings and the widget snapshots macOS keeps (weather, times,
  percentages).
- **Memory.** Apple's calendar framework loads full events, titles included, into Forecast's memory while it
  works. Hardened runtime stops other apps attaching to it; an administrator (root) can read any process's memory.
- **Your screen.** The widget shows how busy your day is to anyone who can see your screen, including screen
  shares.

## Rules for contributors

Pull requests must pass `scripts/privacy-audit.sh` and `scripts/sandbox-probe.sh`; changes to calendar or app
behaviour should also be checked with `scripts/runtime-watch.sh`. In particular, a change will not be merged if it:
- adds any entitlement beyond `app-sandbox` and `personal-information.calendars`;
- reads any EventKit field other than `startDate`, `endDate`, `isAllDay`, `availability` and `status`,
  or uses `title` anywhere except `BreakMatcher.isBreak(event.title)`;
- adds a third-party dependency, a build script, logging, analytics or file writes;
- opens any URL other than the System Settings privacy page, or builds a URL from data;
- commits a team ID, certificate, provisioning profile or personal information.
