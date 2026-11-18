# Templates (short design, 2026-11-18, issue #120)

## Why
Fantastical templates: save the details of a recurring kind of item ("Dentist", "Weekly 1:1") and start a new item from them in one tap. Hypothesis: the owner re-types the same title, length, notes, repeat and calendar often enough that one tap saves time. Calls below are mine, each reversible.

## Done when
- `cd ios && swift test` green, new tests red first, also under Honolulu, New York and Tokyo; `cd web && make test-fast` and `make e2e` green with the FAQ test written first.
- Simulator (iPhone 17, idb): in Add, fill a form and "Save as Template"; reopen Add, pick the template, the form fills (title, length, all day, repeat, notes, URL or priority, destination) and the date stays as it was; delete a template by swipe; relaunch keeps them. Screenshots read.
- In-app FAQ, web FAQ, README, `docs/ios-feature-notes.md`, CLAUDE.md log updated; website FAQ deployed after tests, preflight and smoke pass; TestFlight via ship.sh.
- NOT done: App Store review, saving from the edit sheet or from an existing item, widgets, template sync between devices, a date or time of day in a template.

## Design
- Kit `ItemTemplate` (Codable, Identifiable): `id`, `name`, `kind` (event or reminder), `title`, `durationMinutes: Int?` (events only, from end - start; nil for all-day), `allDay`, `notes`, `url` (events), `priority` (reminders), `recurrence: RecurrenceRule?` (without its end), `destinationID: String?` (calendar or list id).
- Kit `ItemTemplates` (value type, like `CalendarSets`): `add(name:from:)`, `rename`, `delete`, `templates(for kind)`, name rules (trimmed, 1-30 chars, unique ignoring case, at most 50 templates), `decode(Data?)` never throws (missing, corrupt or newer version gives none) and `encoded()`, version 1.
- Kit `TemplateFormValues` from a template plus the form's current start: title, notes, url, priority, recurrence, allDay, `endForPicker`/duration (start + duration; default hour when nil), destination id only if it still exists in the offered choices.
- App: `TemplatesModel` (`@MainActor @Observable`, UserDefaults key `templates.v1`, device only), Add gets a "Templates" menu row (only when any exist for this kind) and a "Save as Template..." row (alert with a name field; disabled while the title is empty); templates list rows swipe to delete. Applying never changes the date or time the form shows, and never saves anything.
- A saved destination id that no longer exists falls back to the default silently.
- Privacy: stored on this device only; nothing sent. Privacy page unchanged.

## Non-goals
No sync, no editing a template's fields in place (delete and re-save), no tags or placeholders, no Edit-sheet entry point.
