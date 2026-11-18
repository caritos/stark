# Natural-language quick add (short design, 2026-11-18, issue #120)

## Why
Fantastical's headline feature: type "Lunch with Sarah at 1pm tomorrow" and get a dated event. The owner said "work on #120" and "no need to ask", so the calls below are mine, each reversible.

## Done when
- `cd ios && swift test` green with new tests first (red, then green), also under Honolulu, New York and Tokyo.
- Simulator (iPhone 17): typing a phrase in Add's Title shows one suggestion row; tapping it fills date, time, kind, repeat and title; Save writes the right item to Apple. Screenshots read.
- In-app FAQ, web FAQ and README mention it; web tests extended first. Website deploy needs no go.
- NOT done: App Store review, voice input, locations, attendees, languages other than English.

## Approaches (picked: 1, my call)
1. **Pure Kit parser + a suggestion row on Add (picked).** Anchored rules driven by the given `Calendar` find the date, time, repeat, kind and duration (not `NSDataDetector`: it reads the real clock and system zone, so it cannot be tested with a fixed now). The owner taps to apply, so a wrong guess never changes the form silently and an item whose title merely contains a date word stays editable.
2. Parse automatically as you type: faster but surprising, and fights the manual pickers.
3. A separate quick-add bar on the main screen: new UI surface, more work, same parser. Possible later on the same parser.

## Design
- Kit `QuickAddParser.parse(_ text:, now:, calendar:) -> QuickAddSuggestion?` (nil when nothing is recognised). `QuickAddSuggestion`: `title` (phrases removed, trimmed), `start: Date?`, `hasTime: Bool`, `end: Date?` (from "for 2 hours" / "for 30 min"), `recurrence: RecurrenceRule?`, `kind: ItemKind?` (reminder for a leading "remind me to" / "todo" / "task"), `summary: String` (what the row shows, e.g. "Tomorrow at 1:00 PM, repeats weekly").
- Date: first date phrase and clock time (anchored rules), their text removed together with a directly preceding "at", "on", "by" or "from". `hasTime` is true when the matched text has a clock time (`1pm`, `13:30`, `noon`, `midnight`); a date with no time is all-day for an event, date-only for a reminder.
- Repeat: "every day|daily", "every week|weekly", "every <weekday>[ and <weekday>...]", "every month|monthly", "every year|yearly|annually", "every N days|weeks|months|years"; the phrase is removed.
- Title never becomes empty: if removing phrases would empty it, no suggestion.
- App: Add shows a row under the Title field while a suggestion exists ("Tomorrow at 1:00 PM, repeats weekly" with an Apply button). Apply sets title, date (and end by duration, else the default hour), All day, repeat, kind. No Contacts, network or storage; the text never leaves the device.
- Copy: in-app FAQ, web FAQ, README, `docs/ios-feature-notes.md`, CLAUDE.md log.

## Non-goals
No automatic apply, no locations or people, no other languages, no changes to Edit.

## Left to the builder
Exact summary wording, how `end` is shown when absent.
