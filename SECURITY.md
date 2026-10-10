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

## Rules for contributors

Pull requests must pass `scripts/privacy-audit.sh`. In particular, a change will not be merged if it:
- adds any entitlement beyond `app-sandbox` and `personal-information.calendars`;
- reads any EventKit field other than `startDate`, `endDate`, `isAllDay`, `availability` and `status`,
  or uses `title` anywhere except `BreakMatcher.isBreak(event.title)`;
- adds a third-party dependency, a build script, logging, analytics or file writes;
- commits a team ID, certificate, provisioning profile or personal information.
