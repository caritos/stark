# Join links and event time zone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A Join button for conference links and a time zone card on event detail, plus a video glyph on rows.

**Architecture:** Two pure Kit helpers over fields the Apple snapshot already carries (plus a new `timeZoneID`); thin app wiring in the read-only Apple detail and the agenda row.

**Tech Stack:** Swift 6 / SwiftUI, EventKit (`EKEvent.timeZone`), Swift Testing, Go + static HTML.

**Spec:** `docs/superpowers/specs/2026-11-18-join-links-timezone-design.md`

## Global Constraints
- Worktree; tests first (red, then green); small commits; never `git add` `ios/.build` or `.superpowers`.
- Kit tests: `cd ios && swift test --scratch-path /private/tmp/claude-501/jl` (new suites also under `TZ=Pacific/Honolulu`, `America/New_York`, `Asia/Tokyo`). Web: `cd web && make test-fast`, `make e2e` (Node 24: `nvm use` inside `web/`, same shell).
- A link is opened only on tap, https only, never fetched; no logging of URLs; theme tokens only; defaulted init params so existing callers compile; Search's synthetic events keep working.
- Edit never changes an event's time zone (the writer must keep it untouched; check `AppleItemRepository` does not reset `timeZone` when saving other fields, with a test through the fake or a read of the code).

## Review Focus
- URL false positives: "zoom.us" with no path, "https://notzoom.us/j/1", "https://zoom.us.evil.com/j/1" (host suffix attack), "http://zoom.us/j/1", "javascript:...", a Zoom link followed by "." or ")" or ">" in notes, uppercase, two links (first supported wins, url field before location before notes), a Google Meet link in the location, a Teams link with query string, a link in the URL field that is NOT conference (not shown) while notes holds Zoom.
- Time zone: floating event (no zone) and all-day: no card; same zone: none; same offset but different zone name (e.g. London and Dublin in winter): no card? (offset equal at that instant means no card); different offset on a DST-straddling event; a zone ID unknown to the system: no card, no crash; end missing; event crossing midnight in the other zone ("11:00 PM-1:00 AM"); half-hour zones (Kolkata); phone in Kiritimati.
- Row glyph appears on agenda rows only for events with a link, not for all-day chips, not for reminders.

### Task 1: Kit helpers and EventKit field
**Files:** Create `ios/Sources/StarkKit/Apple/ConferenceLink.swift`, `EventTimeZoneCard.swift`; modify `AppleModels.swift` (`AppleCalendarEvent.timeZoneID: String?` default nil, and `AppleSource.timeZoneID`/`hasJoinLink` as needed by rows), `AppleMerge.swift`, `ios/App/Stark/Stark/EventKitProvider.swift` (`timeZoneID: event.timeZone?.identifier`, nil when all-day); Test `ios/Tests/StarkKitTests/ConferenceLinkTests.swift`, `EventTimeZoneCardTests.swift`, and an end-to-end chain test (snapshot -> `AppleSelection.filtered` -> `mergeAppleItems` -> row shows the fields) like `BirthdayChainTests`.
**Interfaces (produces):** `public struct ConferenceLink: Equatable, Sendable { provider: Provider; url: URL; var title: String ("Join Zoom") }`, `public enum ConferenceLinkDetector { static func detect(url: String?, location: String?, notes: String?) -> ConferenceLink? }`; `public struct EventTimeZoneCard: Equatable, Sendable { zoneName: String; eventRange: String; yourRange: String }`, `public enum EventTimeZoneCardMaker { static func make(start: Date, end: Date?, isAllDay: Bool, timeZoneID: String?, phoneZone: TimeZone, locale: Locale) -> EventTimeZoneCard? }`.
- [ ] **Step 1:** Write failing tests for every Review Focus line that is Kit logic and the chain test; run `swift test --filter 'ConferenceLink|EventTimeZoneCard'`; expect compile failure (record the red).
- [ ] **Step 2:** Implement; add the model field and mapping; run suites under the three zones, then the full `swift test`; commit `feat: conference links and event time zone helpers`.

### Task 2: Detail, row glyph, copy, simulator
**Files:** Modify `ios/App/Stark/Stark/AppleItemDetailView.swift`, `AgendaRow.swift`, `FAQView.swift`, `web/public/pages/faq.html`, `docs/ios-feature-notes.md`, `CLAUDE.md`; Test `web/api/internal/web/web_test.go` (`TestFAQExplainsJoinLinksAndTimeZones`, red first).
- [ ] **Step 1:** Web test first (anchored phrases: "Join" button for Zoom, Google Meet, Microsoft Teams, Webex and FaceTime links, opened only when you tap, and the time zone card for events in another time zone); red.
- [ ] **Step 2:** Detail: "Join Zoom" row (`openURL` on tap), time zone card section; row: video glyph for events with a link; accessibility labels per the spec.
- [ ] **Step 3:** Copy + CLAUDE.md "Join links and time zone log (2026-11-18)" (Done / Not yet verified on device / Deferred); web tests green.
- [ ] **Step 4:** Simulator (iPhone 17, idb; restart idb_companion by hand if it crashes, redirect output): seed events with `xcrun simctl` or an EventKit script (a Zoom link in the URL, a Meet link in the notes, one in Tokyo, one all-day); screenshots read of detail and row; seen / not seen honestly.
- [ ] **Step 5:** Full `swift test`, generic iOS and Mac Catalyst Debug builds (`CODE_SIGNING_ALLOWED=NO`), `make test-fast`, `make e2e`; commit `feat: Join button and time zone card on event detail`.
