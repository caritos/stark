# Birthday cake and age on Apple events (short design, 2026-11-17)

## Why
The original design promised a cake emoji and the current age on birthdays. Since phase 3 every row is an Apple item, and `AgendaItem.milestone` (`Planner/Milestone.swift`) computes the age as occurrence year minus the event's start year. Apple events carry only each occurrence's start (`AppleCalendarEvent` has no original start), so years is 0 and no age shows. Apple's Birthdays calendar (type `.birthday`) never carries a `%birthday` tag, so it gets no cake either.

## Done when
- `cd ios && swift test` green with new tests written first (red, then green), also under Honolulu, New York and Tokyo.
- On the simulator: an event on a `.birthday`-type calendar (or a seeded contact with a birthday) shows 🎂 and "Turns N" in the agenda, Search and the detail, and a contact with no birth year shows 🎂 only. Screenshots read.
- Privacy page, web FAQ, in-app FAQ and the Contacts usage string updated and the web tests (`TestPrivacyDatedAndMentionsData`) extended first.
- NOT part of done: App Store review, Contacts writing, anniversaries from Contacts, device verification (listed as not verified).

## Approaches (picked: 1, by the owner)
1. **Birth year from Contacts (picked).** Exact age; needs read-only Contacts access, asked the first time a birthday event is shown.
2. Cake only, no age: no permission, but drops the promised age.
3. Age from the series master's start: works only for events Stark/the owner tagged `%birthday`, not for Apple's Birthdays calendar. Kept as a follow-up if cheap.

## Design
- **Kit (testable):** `AppleCalendarEvent` gains `isBirthday` (calendar type `.birthday`) and `birthdayContactID: String?`. `AppleCalendarInfo` gains `isBirthdayCalendar`. A pure `BirthdayAge.years(birth: DateComponents?, occurrence:)` (nil without a year; the year-less sentinel Contacts uses is treated as no year). `milestone` returns `.birthday` for a birthday-calendar event, with years from a `BirthdayYears` lookup (contact id -> birth year) when present, else no note.
- **App:** `EventKitProvider.map` fills the two fields from `EKCalendar.type` and `EKEvent.birthdayContactIdentifier`. A `ContactsBirthdayProvider` (protocol seam in the Kit, `CNContactStore` in the app, off the main actor) returns birth years for the contact ids in the snapshot. It asks for access only when the snapshot holds at least one birthday event; denied or missing means cake only, no error banner.
- **Display:** reuses the existing emoji prefix and secondary "Turns N" line in rows, Search and VoiceOver.
- **Copy:** privacy (new CONTACTS paragraph: read-only, on device, birth year only, never stored), FAQ, `NSContactsUsageDescription`, CLAUDE.md log, `docs/ios-feature-notes.md`.

## Non-goals / anti-goals
No Contacts writing, no storing birthdays in the sidecar, no prompt at launch, no age guessed from a title.

## Left to the builder
Exact lookup caching (per snapshot reload), the year-less sentinel check, and the ordering of the permission prompt relative to the Calendar access screen.
