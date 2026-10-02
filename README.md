# HeadsUp

A free macOS menu-bar app that flashes your upcoming calendar events full-screen, on every monitor, with a big **Join** button for Zoom / Google Meet / Teams links. A free take on In Your Face / Big Reminder.

It reads whatever Apple Calendar can see (Exchange/Outlook, Google, iCloud…), so there is no sign-in and no cloud backend. Add accounts in **System Settings → Internet Accounts**.

## Features
- Pick which calendars alert, per account.
- Per-calendar alert times: 10 min before, 1 min before, at start.
- Snooze 1 / 5 / 10 min or until the event starts. `Esc` dismisses, `Return` joins.
- Skips all-day, declined and canceled events. Events starting together share one alert.
- Open at login.

## Build
Requires macOS 14+ and Xcode.

```sh
./build.sh          # builds, signs, installs to ~/Applications/HeadsUp.app
open ~/Applications/HeadsUp.app
swift test          # unit tests
```

`build.sh` signs with your first "Apple Development" identity (set `SIGN_ID` to override), falling back to ad-hoc signing.

## Tip
Shared/delegated Google calendars are off by default in Apple Calendar. Turn them on in **Calendar → Settings → Accounts → Google → Delegation** and they appear in HeadsUp.
