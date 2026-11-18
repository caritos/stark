# Stark

> A to-do list and calendar in one flat, fast agenda, on top of Apple Calendar and Reminders.

Stark is a native iOS app (Swift / SwiftUI) that puts reminders and events on a single scrolling agenda,
with a week / month / year calendar above it. Website: [stark.caritos.com](https://stark.caritos.com).

## Features

- **One agenda** for reminders and events. Overdue reminders are pinned to today, with the missed date shown.
- **Week, month and year views**, switched with a drag bar. Scrolling the agenda moves the calendar selection.
- **Recurrence**: daily, weekly, monthly or yearly, including custom repeats, positional days ("first Tuesday"), and
  an end date or count. Complete a reminder, or remove a single occurrence of an event.
- **Search** titles, notes and locations, plus tag suggestions for `+project`, `@context`, `%label` and `~person`.
- **Plan your day**: drag tasks onto a timeline as time blocks; a Weekly Review of what got done.
- **Private.** Events and to-dos live in Apple Calendar and Reminders (Apple syncs them through iCloud if you use it);
  Stark makes no network connection unless you switch on the optional weather forecast (see Weather). Items made in Stark before it saved to Apple Calendar and Reminders
  were kept in `.ics` files in the app's Documents folder; Stark no longer reads them, and they stay there untouched
  until the app is deleted. No account, no subscription.
- **Weather** (optional, off by default): Settings > Show weather puts a forecast glyph and high/low in the agenda day headers, from MET Norway's public service. Only an approximate location rounded to about 11 km is sent, nothing else, and it is never stored.
- **Calendar sets**: the calendars button at the bottom lists "All Calendars" and your saved sets (named choices of calendars
  and reminder lists, for example Work and Home); tapping one switches every view. A calendar added later is not in an
  existing set until you edit it. Sets are kept on this device only; the Apple calendar list stays under "Calendar list".
- **Quick add**: type "Lunch with Sarah at 1pm tomorrow" in Add and tap the suggestion to fill in the date, time,
  repeat and kind (English, on the device, never applied automatically).
- **Birthdays**: events on Apple's Birthdays calendar show a cake and, if you allow optional read-only Contacts
  access, "Turns N" from the contact's birth year (read on the device, never stored or sent).

## Repository layout

| Path | What it is |
|---|---|
| `ios/Sources/StarkKit` | SwiftPM package with all testable logic (agenda, recurrence, the Apple item router and sidecar). Tested with Swift Testing. |
| `ios/App/Stark` | The SwiftUI app: thin views over StarkKit, plus the EventKit code. Builds for iPhone and Mac Catalyst. |
| `web/` | The stark.caritos.com marketing site: one Go binary serving static pages (see `web/CLAUDE.md`). |
| `docs/superpowers/` | Design specs and implementation plans. |
| `shared/`, `mobile/` | Legacy. The deprecated Expo app and the todo.txt logic it uses. Not maintained. |

## Development

Requires Xcode 26 or later.

```bash
cd ios && swift test          # StarkKit tests
ios/App/deploy.sh             # build, install and launch on the connected iPhone
```

The website:

```bash
cd web && make dev             # Go server + Vite; pages at http://127.0.0.1:8080/
cd web && make test           # full test tier (see web/docs/testing.md)
web/scripts/deploy-app.sh <user>@<host> --check   # deploy preflight (see web/docs/deploy.md)
```

See [CLAUDE.md](CLAUDE.md) for architecture notes and conventions.
