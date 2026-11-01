# Plan history Implementation Plan

> For agentic workers: use superpowers:subagent-driven-development. TDD: test first.

**Goal:** read-only History screen for past days' plans with done/open stats.
**Architecture:** pure `DayHistory` in StarkKit (tested), thin `DayHistoryView` in the app target, button in PlannerView header.
**Spec:** docs/superpowers/specs/2026-11-01-plan-history-design.md

## Global Constraints
- Swift Testing in StarkKit; `cd ios && swift test`. xcodegen generate after adding files, commit pbxproj. Every xcodebuild: `-skipPackagePluginValidation`; never `CODE_SIGNING_ALLOWED=NO`.
- Never `Date()` in views for "today": use the `today` passed in. Gregorian calendar like DayPlanModel.
- Do not change DayPlanModel behaviour or PlanDraft.

## Task 1: DayHistory model (StarkKit)
Files: create `Sources/StarkKit/Planner/DayHistory.swift`, test `Tests/StarkKitTests/DayHistoryTests.swift`.
Interfaces produced:
- `public struct DayHistory { day; events: [AgendaItem]; allDayEvents: [AgendaItem]; done: [DayPlanModel.DoneBlock]; open: [OpenBlock]; stats: Stats }`
- `OpenBlock { block: PlanBlock; title: String; id }`
- `Stats { done: Int; open: Int; plannedMinutes: Int; doneMinutes: Int; var completion: Double? ; var hasPlan: Bool }`
- `DayHistory.make(day:events:reminders:plans:today:calendar:) -> DayHistory` (day after today -> empty)
- `DayHistory.weekStats(containing day: Date, reminders:, plans:, today:, calendar:) -> Stats` (Sunday-Saturday, days after today ignored)
- `DayHistory.summaryLine(stats:isToday:) -> String?` ("3 DONE - 2 MISSED", "OPEN" on today, nil when no plan), `minutesText(_:)` ("4h", "2h30", "45m"), `weekLine(_:) -> String?` ("WEEK: 11 of 16 blocks done - 69%").
Tests first (names): doneAndOpenClassified, deletedReminderIgnored, skippedEventLeftOut, recurringCompletedCopyMatchesBySeriesAndDay, minutesAndCompletion, noPlanHasNoPlan, futureDayEmpty, weekStatsSumsSundayToSaturday, summaryLineWording, minutesTextFormats. Reuse DayPlanModel's matching/event filtering (extract a shared internal helper if needed without changing its behaviour; existing tests must stay green).

## Task 2: DayHistoryView + entry (app)
Files: create `App/Stark/Stark/DayHistoryView.swift`; modify `PlannerView.swift` (header button, `fullScreenCover`/sheet) only minimally.
- Read-only timeline (hour rows, events, done blocks styled like `doneBlock`, open blocks outlined accent, MISSED/OPEN label), ‹ › header stepping by day (› disabled at today), numbers under the title, week line. Loads months with `store.loadMonths(covering:)` for the day's week widened by the overdue lookback on appear and on every step. Accessibility labels on blocks and arrows.
- Verify on the iPhone 17 Pro Max simulator with idb screenshots (seed a past plan in a month file, never touch the "iPhone 14 Plus" device); record "not verified on device".
- Update project CLAUDE.md (timeboxing section + log) and the in-app/website FAQ only if user-facing copy needs it (website copy lives on branch web-go: note as deferred).
