# Stark

> A to-do list and calendar in one flat, fast agenda. Your data is plain `.ics` files on your device.

Stark is a native iOS app (Swift / SwiftUI) that puts reminders and events on a single scrolling agenda,
with a week / month / year calendar above it. Website: [stark.caritos.com](https://stark.caritos.com).

## Features

- **One agenda** for reminders and events. Overdue reminders are pinned to today, with the missed date shown.
- **Week, month and year views**, switched with a drag bar. Scrolling the agenda moves the calendar selection.
- **Recurrence** with standard `RRULE` rules, including custom repeats, positional days ("first Tuesday"), and
  an end date or count. Complete, skip, or remove a single occurrence.
- **Event attendance**: mark each occurrence attended or skipped.
- **Search** across your whole history, plus tag suggestions for `+project`, `@context`, `%label` and `~person`.
- **Local and private.** Data is stored as `recurring.ics` and one `YYYY-MM.ics` per month in the app's Documents
  folder. There is no account, no cloud sync and no subscription.

## Repository layout

| Path | What it is |
|---|---|
| `ios/Sources/StarkKit` | SwiftPM package with all testable logic (parsing, recurrence, agenda). Tested with Swift Testing. |
| `ios/App/Stark` | The SwiftUI app: thin views over StarkKit. Builds for iPhone and Mac Catalyst. |
| `web/` | The stark.caritos.com marketing site (Bun + Hono). |
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
cd web && bun install && bun run src/index.ts
web/scripts/deploy.sh         # deploy to the DreamHost VPS
```

See [CLAUDE.md](CLAUDE.md) for architecture notes and conventions.
