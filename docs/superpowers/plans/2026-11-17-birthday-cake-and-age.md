# Birthday cake and age Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Events from Apple's Birthdays calendar show 🎂 and "Turns N" (N from the contact's birth year in Contacts), in rows, Search and VoiceOver.

**Architecture:** The Kit learns which events are birthday-calendar events and carries a birth year on `AppleSource`; `AgendaItem.milestone` reads it. A `BirthYearLookup` protocol (Kit) is implemented in the app by `ContactsBirthYears` (`CNContactStore`, read-only, off the main actor); `EventKitProvider.fetch` calls it only when the fetched events include a birthday-calendar event, and puts the result in `AppleSnapshot.birthYears`.

**Tech Stack:** Swift 6 / SwiftUI, EventKit, Contacts, Swift Testing, Go + static HTML for the website copy.

**Spec:** `docs/superpowers/specs/2026-11-17-birthday-cake-and-age-design.md`

## Global Constraints

- Work in a worktree; tests first (red, then green); one small commit per green step. Never `git add` `ios/.build`.
- Kit tests: `cd ios && swift test --scratch-path /private/tmp/claude-501/bday` (and the new suites under `TZ=Pacific/Honolulu`, `America/New_York`, `Asia/Tokyo`). Web: `cd web && make test-fast`, `make e2e`.
- Read-only Contacts access only; never store birthdays (sidecar, UserDefaults, logs); no prompt at launch; denied or unavailable means cake only, no banner.
- A contact with no birth year, or the placeholder year Apple uses (any year < 1900, e.g. 1604), has no age.
- The existing `%birthday` tag path and `MilestoneTag.years` rules stay unchanged.
- `Info.plist` key: `NSContactsUsageDescription`. The pbxproj uses a synchronized folder, so new Swift files in `ios/App/Stark/Stark/` need no project edit.
- Copy: privacy page keeps "LAST UPDATED: NOVEMBER 2026"; every page keeps the `Build @@BUILD_ID@@` footer once.

## Review Focus

- A birthday event on a contact with no birth year: 🎂, no note, no crash.
- Contacts access denied or restricted: cake only, no error banner, no repeated prompt.
- Birth year equal to the occurrence year (the birth day itself): no note (matches `MilestoneTag.years`).
- A birthday-calendar event whose contact id is missing from the lookup (contact deleted): cake only.
- A snapshot with no birthday events must not touch Contacts (no prompt, no work).

---

### Task 1: Kit model, lookup protocol and milestone

**Files:**
- Modify: `ios/Sources/StarkKit/Apple/AppleModels.swift` (`AppleCalendarInfo`, `AppleCalendarEvent`, `AppleSource`, `AppleSnapshot`)
- Modify: `ios/Sources/StarkKit/Apple/AppleMerge.swift` (source built at line ~41)
- Modify: `ios/Sources/StarkKit/Planner/Milestone.swift` (`AgendaItem.milestone`)
- Create: `ios/Sources/StarkKit/Apple/BirthYear.swift`
- Test: `ios/Tests/StarkKitTests/BirthdayMilestoneTests.swift`

**Interfaces:**
- Produces:
  - `AppleCalendarInfo.isBirthdayCalendar: Bool` (init param default `false`, last).
  - `AppleCalendarEvent.birthdayContactID: String?` (init param default `nil`, last).
  - `AppleSnapshot.birthYears: [String: Int]` (contact id to year; init param default `[:]`, last; `AppleSnapshot.empty` unchanged).
  - `AppleSource.isBirthday: Bool` and `AppleSource.birthYear: Int?` (init params default `false` / `nil`, last).
  - `enum BirthYear { static func year(from components: DateComponents?) -> Int? }` returns nil for nil components, a nil year, or a year < 1900.
  - `protocol BirthYearLookup: Sendable { func birthYears(forContactIDs ids: Set<String>) async -> [String: Int] }` in `BirthYear.swift` (returns `[:]` when access is missing; never throws).
- `AgendaItem.milestone`: for an `.event` row whose `appleSource?.isBirthday == true`, returns `MilestoneInfo(kind: .birthday, years:)` where years = occurrence year minus `appleSource.birthYear` if that is > 0, else nil (no birth year: nil). The tag path still applies to other rows, and a row that is both uses the birthday-calendar result.

- [ ] **Step 1: Write the failing tests** in `BirthdayMilestoneTests.swift` (Swift Testing, fixtures as in `AppleMergeItemsTests.swift:21`): `BirthYear.year` returns 1990 for `DateComponents(year: 1990, month: 5, day: 3)`, nil for a nil year, nil for 1604, nil for nil components; `mergeAppleItems` of an event on a calendar with `isBirthdayCalendar: true` and `birthdayContactID: "c1"` with `birthYears: ["c1": 1990]` gives a row whose `milestone` is `.birthday` with `years == occurrenceYear - 1990` and `note == "Turns N"`; same event with `birthYears: [:]` gives `.birthday` and `years == nil`; birth year equal to the occurrence year gives `years == nil`; a normal calendar's event gives `milestone == nil`; a `%birthday`-tagged normal Apple event still gives `.birthday` (years nil); a snapshot built with the old init (no new arguments) still compiles.
- [ ] **Step 2: Run to verify they fail** (`swift test --filter BirthdayMilestoneTests`; expected: compile errors for the missing members).
- [ ] **Step 3: Add the members and `BirthYear`/`BirthYearLookup`** exactly as in Interfaces; `mergeAppleItems` sets `AppleSource.isBirthday = apple.calendar.isBirthdayCalendar` and `birthYear = apple.birthdayContactID.flatMap { snapshot.birthYears[$0] }`; update `AgendaItem.milestone`.
- [ ] **Step 4: Run** the new suite under the three time zones, then the full `swift test`. Expected: all pass (931 plus the new ones).
- [ ] **Step 5: Commit** `feat: birthday-calendar events get the cake and an age from a birth year`.

### Task 2: App wiring (EventKit mapping, Contacts lookup, usage string)

**Files:**
- Modify: `ios/App/Stark/Stark/EventKitProvider.swift` (`info`, `map`, `fetch`, init)
- Create: `ios/App/Stark/Stark/ContactsBirthYears.swift`
- Modify: `ios/App/Stark/Info.plist`
- Modify: `ios/Sources/StarkKit/Apple/AppleModels.swift` only if Task 1 left a gap (it should not)
- Test: `ios/Tests/StarkKitTests/BirthdayFetchGateTests.swift` (the gate logic, see below)

**Interfaces:**
- Consumes: Task 1's members.
- Produces: Kit pure function `BirthYear.contactIDsNeeded(in events: [AppleCalendarEvent]) -> Set<String>` (ids of birthday-calendar events with a non-nil `birthdayContactID`); `ContactsBirthYears: BirthYearLookup` (app); `EventKitProvider(birthYears: BirthYearLookup = ContactsBirthYears())`.

- [ ] **Step 1: Write the failing test** `BirthdayFetchGateTests`: `contactIDsNeeded` returns `[]` for events with no birthday-calendar event (so the provider must not call the lookup), the ids for two birthday events, and ignores a birthday event with a nil contact id.
- [ ] **Step 2: Run to verify it fails**, then implement `contactIDsNeeded` in `BirthYear.swift`; run to green; commit `feat: only look up birth years for birthday events`.
- [ ] **Step 3: `EventKitProvider`**: `info` sets `isBirthdayCalendar: calendar.type == .birthday`; `map` sets `birthdayContactID: event.birthdayContactIdentifier`; `fetch` computes `contactIDsNeeded`, calls the lookup only if non-empty, and builds `AppleSnapshot(events:reminders:birthYears:)`.
- [ ] **Step 4: `ContactsBirthYears`**: implements `birthYears(forContactIDs:)` with `CNContactStore`; checks `CNContactStore.authorizationStatus(for: .contacts)`, requests access only when `.notDetermined` (this is the one prompt, first time a birthday event is shown), returns `[:]` for denied/restricted/limited-without-contact or any thrown error, fetches only `CNContactBirthdayKey` for the ids via `unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers:), keysToFetch:)`, maps through `BirthYear.year(from:)`. Runs off the main actor; never logs birthdays.
- [ ] **Step 5: `Info.plist`**: add `NSContactsUsageDescription` = "Stark reads the birth year of the people in your Birthdays calendar, only to show their age. It is never stored or sent anywhere."
- [ ] **Step 6: Verify on the simulator (iPhone 17)**: build with `xcodebuild` for the simulator; add a contact with birthday 1990-05-03 and one with a birthday without a year (Contacts app or `simctl`), confirm the Birthdays calendar is ticked, open the agenda on that day with idb; screenshots read: 🎂 + "Turns N" for the first, 🎂 only for the second; deny the Contacts prompt on a fresh install and confirm cake only and no banner; Search finds the birthday row with the same display. Record each as seen or not seen.
- [ ] **Step 7: Run** the full `swift test`, the generic iOS build and the Mac Catalyst Debug build (`CODE_SIGNING_ALLOWED=NO`); commit `feat: read birth years from Contacts for birthday events`.

### Task 3: Copy, docs and ship

**Files:**
- Modify: `web/public/pages/privacy.html`, `web/public/pages/faq.html`, `ios/App/Stark/Stark/FAQView.swift`, `README.md`, `docs/ios-feature-notes.md` ("Birthdays and anniversaries"), `CLAUDE.md` (dated log)
- Test: `web/api/internal/web/web_test.go` (extend `TestPrivacyDatedAndMentionsData`), `web/test/e2e/site.spec.ts` only if it lists page text

**Interfaces:** consumes the shipped behaviour of Tasks 1-2.

- [ ] **Step 1: Write the failing web test**: `/privacy` mentions Contacts, says Stark reads only the birth year of people in the Birthdays calendar, on the device, that it is optional, and never stored or sent; `/faq` has a birthday entry saying the same and that denying access still shows the cake without the age. Run `cd web && make test-fast`; expected FAIL on the new strings.
- [ ] **Step 2: Update** the privacy page (new "CONTACTS" paragraph after APPLE CALENDAR AND REMINDERS), the web FAQ, the in-app `FAQView`, README and `docs/ios-feature-notes.md`; run `make test-fast` and `make e2e` to green; commit `docs: Contacts access for birthday ages`.
- [ ] **Step 3: Full verification on the merged result**: `swift test` (all green), `make test-fast`, Release build for a device (`ios/App/deploy.sh` build step or the `ship.sh` archive), read the privacy and FAQ pages in the local build.
- [ ] **Step 4: Log and ship**: add a dated "Birthday cake and age log (2026-11-17)" to `CLAUDE.md` (Done, Not yet verified on device: the real Contacts prompt and real birthdays, iOS 17, VoiceOver for the birthday row, Deferred: `%birthday`-tagged Apple events still show no age (series-master follow-up)); merge to main locally after the suite is green; push; upload TestFlight with `ios/App/ship.sh` (TestFlight only). Deploy the website only after the owner has seen the prompt on the phone, and say so in the report.
