# Stark phase 3 inventory: removing the local `.ics` store

Read-only reconnaissance, 2026-11-17, against `main` at 48f4a6f (clean tree). Paths are relative to
`/Users/eladio/src/stark`. "L" = line. Nothing in the repo was edited.

Scope reminder (from the brief): after phase 3 Stark reads and writes ONLY Apple data plus the sidecar
(plans for Apple reminders, attended/skipped marks on Apple events). The import feature goes. The
`.ics` files in the app's Documents are never touched: the app simply stops reading them.

Facts that shape the whole plan:

- The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (3 groups in
  `ios/App/Stark/Stark.xcodeproj/project.pbxproj`) and there is no `project.yml`: deleting a Swift file
  from `ios/App/Stark/Stark/` needs NO pbxproj edit. `ios/Package.swift` has no resources and no
  per-file lists, so Kit deletions need no Package.swift change either.
- Every app view gets local data from one `@EnvironmentObject PlannerStore` (`store.events`,
  `store.reminders`, `store.plans`, `store.loadMonths`, `store.loadAllMonths`, `store.error`). Apple data
  comes from `AppleOverlayModel.snapshot` (EventKit, already expanded into occurrences, synthetic
  `Event`/`Reminder` values with `apple-` ids, never a `recurrence`) and `PlanCache.applePlans` (sidecar).
- `store.error` is ALSO the app's main error banner for Apple failures (see section 3, hazard H1).
  Deleting `PlannerStore` needs a replacement error surface.

---

## 1. Classification table

### 1a. StarkKit sources (`ios/Sources/StarkKit`)

| File / type | Verdict | Why / what changes |
|---|---|---|
| `Planner/PlannerStore.swift` (643 lines) | DELETE | The store itself: month loading (L45-150), add/update/delete/convert/complete/skip/outcome on local items (L152-582, incl. `carriedOccurrences` L569), import hiding (`allEvents`/`allReminders`/`allPlans` L18-21, `importedIDs` L25, `notImportedIDs` L28, `recurringLoaded` L31, `setImportedIDs` L586, filter in `rebuild` L599-601), `error`/`warnings` (L11-16). |
| `Planner/PlannerFile.swift` (129) | DELETE | `.ics` file I/O, `availableMonths`, `deleteMonth`, `Library/PendingWrites` queue (`retryPendingWrites` L114). |
| `ICS/ICSParser.swift`, `ICS/ICSSerializer.swift`, `ICS/ICSDateFormat.swift` | DELETE | Only `PlannerFile` (and tests) use them. Plan-block ICS (`ICSSerializer.serialize(plan:)` L47) dies with them; there is no separate `PlanBlockICS` type (only the test file `PlanBlockICSTests.swift`). |
| `ICS/RRuleCodec.swift` (140) | DELETE (recommended) | Production callers: `ICSParser`, `ICSSerializer` only. `OnWeekPickerView.swift` L35 mentions it in a comment only. Tests: `RRuleCodecTests` (delete), `OccurrenceExpanderTests` L275-278, L314 and `RepeatEndTests` L44 (rewrite those 3 asserts to compare `RecurrenceRule` values; it is `Equatable`). Alternative: keep as an unused RFC 5545 codec (no cost), but nothing Apple uses it (`RecurrenceDescriptor` maps to EventKit). |
| `Import/ImportModel.swift`, `ImportPlan.swift`, `ImportPlanner.swift`, `ImportRunner.swift` | DELETE | The one-time import; nothing left to import. `ImportModel` is the only Kit user of `PlannerStore.allEvents/recurringLoaded/loadAllMonths/setImportedIDs`. |
| `Items/LocalItemStore.swift` | DELETE file, MOVE `DefaultDestinations` | `LocalItemStore` protocol + `extension PlannerStore: LocalItemStore` (L8-26) die. **`DefaultDestinations` (L30-34) is still needed** by `ItemRouter` and `App/DefaultDestinationModel.swift`: move it to `Items/DefaultDestination.swift`. |
| `Items/ItemRouter.swift` (494) | MODIFY | Remove `ItemOrigin.local` (L7) and every `.local` branch: `update(event:)` L170-171, `update(reminder:)` L186-187, `deleteEvent/deleteReminder` L218/L225, `complete` L235 (drop the `today:` parameter, only the local path used it), `uncomplete` L242, `skipEvent` L250, `skipReminder` L256-264 (whole method: Apple always throws; delete it), `setEventOutcome(id:)` L271-272, `convertEvent/convertReminder` L315-319/L332-336 (return type can become non-optional `AppleItemRef`), `plans(on:)` L378-385 (sidecar only), `replacePlans` L405-441 (drop the local half and the "only Stark's own blocks still saves" catch at L423-427; decide what a non-`apple-` block does: recommend ignore, like blocks not on `day`), `ItemRouterError.local` (L43-44, L69-70), `local` init parameter (L99, L108, L112), doc comments L85-95, L160, L309. A non-`apple-` id must now fail loudly: either keep `ItemOrigin.init(id:kind:)` returning an optional/throwing, or keep a `.notApple` case that every method maps to `ItemRouterError.unsupported("This item is no longer stored by Stark.")`. |
| `Items/ItemSidecar.swift` (303) | MODIFY | Delete the import API: `ImportRecord` (L71-86), `importedIDs()` (L211), `recordImport` (L217-230), `markImportFinished` (L232). `SidecarData.importLedger`/`importedAt` (L33-36, L43-51, L55, L66-67): see hazard H4 (recommend keeping the two keys decoded and re-encoded unchanged, no public API, so a downgrade to v2.0.33-36 does not re-offer the import). Doc L19 "import ledger". |
| `Items/FakeItemRepository.swift` | KEEP | Test fake in Sources; uses `OccurrenceExpander` (L66, L336) to simulate series. |
| `Items/ItemRepository.swift`, `RecurrenceDescriptor.swift`, `ItemPatchDiff.swift`, `ItemEditForm.swift`, `ItemDeletePrompt.swift`, `ReminderAlarmShift.swift`, `DefaultDestination.swift`, `DestinationLabel.swift` | KEEP | Apple write path. |
| `Planner/OccurrenceExpander.swift` | KEEP | Used by `FakeItemRepository` (L66, L336), `DayPlanModel.make` L135-136 (runs on Apple events too: the midnight-end spill filter for multi-day timed events), `TimelineLayout` L131 (local-series branch only, dead after phase 3), `SearchResults` L96/L107 (local only), `AgendaBuilder`. Delete only if task 5 below also rewrites the fake and DayPlanModel L136 (for a non-recurring event the call equals `e.start == item.occurrence`). |
| `Planner/AgendaBuilder.swift` | MODIFY (minimal) / split later | KEEP `AgendaItem` (L5-101), `sortAgendaItems` (L248, used by `mergeAppleItems`, `applyPlans`, `timelineAgendaItems`), `spanDays` (L271, used by `mergeAppleItems`, `DayPlanModel`, `TimelineLayout`). DELETE `marked(notImported:)` (L103-118) and `AgendaItem.isNotImported` (L29-31). `buildAgendaItems` (L143-242) is the local-only expander: with no local items it returns `[]`; keep it in phase 3 (engine tests use it), delete in the optional slimming task. Recommend moving `AgendaItem` + `sortAgendaItems` + `spanDays` to their own file when `buildAgendaItems` goes. |
| `Planner/AgendaDays.swift` (`groupAgendaByDay`) | KEEP | Pure grouping of any rows. |
| `Planner/AgendaWindow.swift` | KEEP, edit docs | `range(around:)` (display + Apple fetch), `loadRange(around:)` still used by `DayPlanModel.make` L112 and `PlannerDays.loadRange` (planner's Apple fetch window), `overdueLookbackDays` still used by `AppleOverlayModel` L148 (completed-reminder fetch), `OverdueLabel` (90+ cap), `DayPlanModel`. Doc comments L8-9, L34 name `PlannerStore.start`. |
| `Planner/PlannerDays.swift` | KEEP | `loadRange(for:)` feeds `overlay.reload(for: .planner, ...)` (PlannerView L198). |
| `Planner/WeeklyReview.swift` | MODIFY | `loadRange(forWeekStarting:today:)` (L≈95-103) only feeds `store.loadMonths` (WeeklyReviewView L75): DELETE it and its test. `summary` keeps working with `events: [], reminders: []`; its doc (L5-14) describes the local semantics. Behaviour: `attendedEventCount` becomes always 0 (Apple events add none, section 2). |
| `Planner/CompletionHistory.swift` | DELETE | Only caller: `EditItemView` L330-337, behind `guard !isApple`. |
| `Planner/CompletionNote.swift` | KEEP | `AgendaItem.completionNote` ("done Oct 14") is drawn by `AgendaRow` L303 and works for Apple completed reminders (they carry `completedAt` and a due date). |
| `Planner/PendingCompletions.swift` | KEEP | Already routes through `router.complete` (StarkApp L87-93). Doc L13-15 mentions `PlannerStore`. The sync `init(commit:)` is now used only by tests. |
| `Planner/DayExport.swift` | KEEP | Pure over `[AgendaItem]`; no local dependency. |
| `Planner/SearchResults.swift` | KEEP (dead local loops) | `find(events:reminders:apple:...)`: local loops L38-45 and `representativeOccurrence` L94-110 become dead with `[]` inputs; `matches(_ reminder:)` is still used for Apple reminders (L63). Slim in task 5. |
| `Planner/TagAutocomplete.swift` | KEEP (dead params) | `suggestions(for:events:reminders:apple:)` L45; local loops dead. |
| `Planner/AgendaDensity.swift` (`dayDensity`, `gridDensity`, `yearDensity`, `YearGrid`) | KEEP (dead params) | All call `buildAgendaItems` then `agendaWithApple`; with `[]` they reduce to the Apple merge + plans. |
| `Planner/MonthLayout.swift`, `QuarterGrid.swift`, `MonthGrid.swift` | KEEP | Take `[AgendaItem]`. `YearMonth` (in `DateMath.swift`) stays: used by MonthLayout, QuarterGrid, MonthGrid, densities and 4 views. `YearMonth.fileName` (DateMath L65) becomes unused except by `description` (L69 returns "2026-09.ics"): change `description`, drop `fileName` and `DateMathTests` L36. |
| `Planner/TimelineLayout.swift` | KEEP (one dead branch) | `timelineAgendaItems` L59-71 calls `buildAgendaItems`; `timelineLayout` L126-132 local-series branch (`event.recurrence != nil, item.appleSource == nil`) is unreachable after phase 3. |
| `Planner/PlanAgenda.swift` (`applyPlans`, `agendaWithApple`) | KEEP | Core of every Apple screen. `reminders:` lookup (L69, synthesize planned local one-offs) becomes dead with `[]`; L63 copies `isNotImported` (delete with the flag). |
| `Planner/DayPlanModel.swift` | KEEP | `make(day:events:reminders:plans:...)` L103-; local one-off loop (L153-158) and local matching in `doneBlock` (L235-245) become dead; `appleDoneBlock` stays. `combinedPlans` stays. |
| `Planner/DayHistory.swift` | KEEP | `make`/`weekStats` with `[]`; `classify` local-open branch (L105) dead. |
| `Planner/PlannerPlans.swift` | KEEP or inline | With `local: []` every function is the Apple list unchanged (`forModel` L12-18, `saved` L22-25, `all` L28-30). Simplest: keep, pass `[]`; slim later. |
| `Planner/PlanDraft`, `PlanSession`, `PlanLayout`, `PlanRowText`, `TrayPane`, `PlanCacheState`, `EventOutcomeActions`, `OverdueLabel`, `Milestone`, `CalendarMode`, `CalendarViewMenu`, `AgendaScrollTracking` | KEEP | No local-store dependency. |
| `Models/*` (`Event`, `Reminder`, `RecurrenceRule*`, `RepeatEnd`, `PositionalDay`, `Weekday`, `ReminderPriority`, `PlanBlock`, `QuarterHour`, `FormFields`, `EventSchedule`, `Month`) | KEEP | Synthetic Apple values, edit forms, repository and sidecar. Fields only the local store wrote (`Reminder.seriesID`, `exceptionDates`, `Event.outcomes`) stay: `FakeItemRepository`, `ItemDetails`, `withStoredItem` (AppleReadOnly L19) use them. |
| `Models/ItemConversion.swift` | KEEP | `reminder(from:)`/`event(from:undatedStart:)` are used internally by `appleReminder(from:)` and `event(fromEdited:)`. `droppedMarks(converting:)` (L67) becomes dead (EditItemView L373-375 returns 0 for Apple). |
| `Apple/AppleReadOnly.swift` | MODIFY | "Local half of the read-only gate": `AgendaItemDetail.edit` (L36) for `appleSource == nil` (L41-42) and the unused `editable` (L57-60). After phase 3 a row without `appleSource` cannot occur in production; drop `.edit` (route a source-less row to `.readOnly`) and `editable`. `isReadOnly` (L10) can stay as is. `openURL` "nil for a Stark item" (L145) is harmless. |
| `Apple/AppleMerge.swift` and the rest of `Apple/*` | KEEP | Doc of `mergeAppleItems` L17-18 mentions "Stark's own items" lookback. |

### 1b. App target (`ios/App/Stark/Stark`)

| File | Verdict | What changes |
|---|---|---|
| `ImportStarkItemsView.swift` (279) | DELETE | Import screen. |
| `StarkApp.swift` | MODIFY | Remove `@StateObject store` (L13, L34-35), `makeStore()` (L126-134, the Documents + `Library/PendingWrites` paths), `importModel` (L24-26, L62-81, L105), `local: store` in the router (L51), `store?.error` sinks (L54 PlanCache failures, L91 pending-commit failures) -> new error surface (H1); `.environmentObject(store)` (L99). Comment L82-86 (Stark ids to the local store). |
| `ContentView.swift` | MODIFY | `@EnvironmentObject store` L17; `ImportModel` L22 and `interactiveDismissDisabled(importModel.isRunning)` L230; error banner L102-104 (new surface); launch `.task` L234-243: drop `AgendaWindow.loadRange`/`store.start` (L236-237) and `importModel.refreshStatus()` (L240); scene `.active` `store.retryPendingWrites()` L251; `followCalendarDay` `store.loadMonths` L291 (the overlay fetch in `moveAgendaWindow` already gates the move); `selectDate` `store.loadMonths` L350. |
| `AgendaView.swift` | MODIFY | `store` L23; uncomplete failure `store.error` L299; `makeSections` L309-326: `buildAgendaItems(store.events, store.reminders)` -> `[]` (or call `agendaWithApple(local: [], ...)`), `plans: store.plans + planCache.applePlans` -> `planCache.applePlans`, `reminders: store.reminders` -> none, `.marked(notImported:)` L325 removed. Doc L12. `DayExport` L223 unchanged. |
| `AgendaRow.swift` | MODIFY | "Not imported" chip/label L92-95, L172-174, accessibility L251, `NotImportedLabel` struct L378+: delete. |
| `EditItemView.swift` (561) | MODIFY (largest app change) | `store` L23; not-imported section L67-75 and `isNotImported` L345-350; History section L203-212 + `history` L328-337 (CompletionHistory); `store.loadAllMonths()` task L252-256; `showsSkip` L437-441 and the reminder branch of `skipOccurrence` L551; `droppedMarks` L371-381 + confirm L398; local convert branch L504-508 and local URL branch L518-519. `details: ItemDetails?` (L31) can become non-optional and `isApple` (L320) disappears once `AgendaItemDetail.edit` is gone (callers: `AppleItemDetailView.swift` L15, L59). Doc L5-21. |
| `AppleItemDetailView.swift` | MODIFY | `AgendaItemDetailSheet` L13-18: drop the `.edit` case; doc L5-7, L109. |
| `AddItemView.swift` | MODIFY | `store` L10, `store.loadAllMonths()` L129-133 (tag corpus). |
| `TagSuggestionRow.swift` | MODIFY | `store` L14, `events: store.events, reminders: store.reminders` L21 -> `[]`. |
| `SearchView.swift` | MODIFY | `store` L19, `loadAllMonths` L89, `onReceive(store.$events...)` L101-103, `refreshResults` L108-112 (`[]`, no `marked`). Doc L9. |
| `WeeklyReviewView.swift` | MODIFY | `store` L13, `summary(events: store.events, reminders: store.reminders)` L26, `loadWeek()` L64-76. Doc L5-11. Decide the "Events attended" line (always 0, section 2). |
| `PlannerView.swift` | MODIFY | `store` L57; store error banners L118-119, L141 (new surface); `.onChange(of: store.reminders/events)` L208-209; `makeModel` L226-235 (`store.events/reminders/plans` -> `[]`); `freshDraft` L249 (`store.plans(on:)`); `loadDay` L285 and `step` L311 `store.loadMonths`; `pastDay` L382-385; `title(ofReminder:)` L435 local lookup; `completeBlock` passes `today:` (L402) -> drop. |
| `PlannerView+Timeline.swift` | MODIFY | `storeErrorBanner` L27-28 clears `store.error`. |
| `PlannerView+Tray.swift` | MODIFY | `.marked(notImported:)` L77, not-imported label L146-148. |
| `MonthGridView.swift`, `YearView.swift`, `FullMonthView.swift`, `FullQuarterView.swift`, `FullWeekView.swift`, `FullDayView.swift` | MODIFY | Each: `@EnvironmentObject store` (L37 / L19 / L20 / L22 / L18 / L16), a `store.loadMonths(covering:)` (L196 / L88 / L79 / L92 / L105 / L86), and inputs `events: store.events, reminders: store.reminders, plans: PlannerPlans.all(local: store.plans, ...)` (L218-219 / L137-138 / L133-135 / L142-144 / L152-153 / L132-133). Month and Quarter also call `buildAgendaItems` themselves (FullMonthView L148, FullQuarterView L157). Docs mention `buildAgendaItems`. |
| `PlanCache.swift` | KEEP, edit doc | Doc L9 "Stark's own plans still come from `PlannerStore.plans`". `onLoadFailure` sink rewired (H1). |
| `SettingsView.swift` | MODIFY | Import row L13-14, L55-80, L134; doc L5-7 ("Storage is just the local Documents directory"). |
| `FAQView.swift` | MODIFY | See section 5. |
| `AccessRequiredView.swift` | MODIFY (comment) | L8 "Stark's own (local) items stay visible below it" (false: nothing shows without access). |
| `AppleOverlayModel.swift` | KEEP | `isEnabled` is hard-wired `true` (L27): the spec's "overlay on/off switch goes away" is effectively done; optional cleanup of `isEnabled`/`AppleSettings.showsCalendars(isEnabled:)`. |
| `NoticeCenter.swift` | KEEP (candidate home for the error banner, H1). |
| `AppleItemRepository.swift`, `EventKitProvider.swift`, `DefaultDestinationModel.swift`, `AppleSettingsView.swift`, everything else | KEEP | No local-store dependency (`AppleItemRepository.seriesID` L357 is its own EventKit helper, unrelated). |
| `Info.plist` (`ios/App/Stark/Info.plist`) | KEEP | Only the two usage strings; they mention no local files. No `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`/`UIBackgroundModes`. |
| `PrivacyInfo.xcprivacy` | KEEP | Declares only UserDefaults (CA92.1); `PlannerFile` used no required-reason API (`contentsOfDirectory` without properties). |

### 1c. Tests (`ios/Tests/StarkKitTests`, test counts in brackets)

DELETE whole files (about 222 tests):
`PlannerStoreTests` [66], `PlannerStoreConversionTests` [9], `PlannerStoreImportHidingTests` [9],
`PlannerStorePlansTests` [11], `PlannerFileTests` [9], `ParityTests` [3], `ExportFixtureTests` [6]
(reads `shared/tests/fixtures/ics/expected`), `ICSParserTests` [8], `ICSSerializerTests` [11],
`ICSCompletionTimestampTests` [3], `PlanBlockICSTests` [4], `RRuleCodecTests` [13] (if RRuleCodec goes),
`ImportModelTests` [14], `ImportPlannerTests` [27], `ImportRunnerTests` [14], `CompletionHistoryTests` [4],
`CompletionHistorySummaryTests` [2], `ItemSidecarImportLedgerTests` [9] (but MOVE its three compatibility
cases `oldSidecarWithBridgeLedgerKeyStillLoads`, `v2SidecarWithImportLedgerAndBridgeLedgerKeyStillLoads`
and the v1 fixture load into `ItemSidecarTests`; `Fixtures/sidecar-v1.json` stays).

MODIFY:
- `ItemRouterTests` [42]: delete `FakeLocalStore` (L8-41) and the local cases ("an apple- model id routes
  to Apple, a Stark UUID to the local store" L141, "Stark ids go to the local store..." L239, "a local
  convert the store refuses throws" L262, the local half of "plans for an Apple reminder go to the
  sidecar, local ones to the store" L400, "a refused local plan save throws" L415, "an unreadable sidecar
  does not block a day with only Stark's own blocks" L423, the "nil for Stark ids" half of L721,
  "skipReminder on an Apple reminder is unsupported" L286 if the method is deleted); add "a non-apple id is
  refused and writes nothing" and "replacePlans ignores non-Apple blocks".
- `PendingCompletionsTests` [20]: delete the "Against a real PlannerStore" section (L220-~395, 6 tests:
  L237, L256, L275, L293, L312, L330); the scheduler tests and the two async-commit tests (L396, L418) stay.
- `ItemSidecarTests` [23]: L38, L44-60, L70 use `importLedger` as a convenient field (switch to `plans`
  or `externalIDs`), L161 uses `recordImport` in the no-absolute-paths test.
- `AppleReadOnlyTests`: `starkItemRoutesToEditSheet` (L39-43) and the `editable` assert L36.
- `WeeklyReviewTests`: `loadRange` test (L173-182).
- `OccurrenceExpanderTests` L275-278, L314 and `RepeatEndTests` L44 (RRuleCodec), `DateMathTests` L36
  (`fileName`), comment L46.
- `PlanAgendaTests` L153-157 is a helper mirroring `PlannerStore.completeReminder` (keeps working; comment).

KEEP unchanged in phase 3 (they test pure engines with local `Event`/`Reminder` fixtures; they only need
rewriting if the optional slimming task removes the local parameters): `AgendaBuilderTests` [34],
`AgendaDaysTests` [11], `AgendaDensityTests` [27], `GridDensityTests` [14], `YearDensityTests` [8],
`PlanDensityTests` [5], `AgendaWindowTests` [25], `AgendaWithAppleTests` [3], `DayPlanModelTests` [31],
`DayPlanModelElsewhereTests` [4], `PlanDraftTests` [13], `PlanDraftCompleteTests` [4], `PlanSessionTests` [7],
`TrayPaneTests` [3], `PlanAgendaTests` [12], `PlannerAppleWriteFixTests` [10], `PlannerAppleWriteTests` [13],
`DayHistoryTests` [10], `WeeklyReviewTests` [19], `SearchResultsTests` [7], `TagAutocompleteTests` [15],
`TimelineLayoutTests` [23], `MonthLayoutTests` [26], `ItemConversionTests` [17] (incl. `droppedMarks`),
`EventScheduleTests`, `ModelsTests`, `EventRescheduleTests`, `CompletionNoteTests`, `DayExportTests`, and all
`Apple*`, `ItemRepositoryContractTests`, `RecurrenceDescriptorTests` (uses `OccurrenceExpander`, keep).

### 1d. Outside `ios/`

- `web/public/pages/privacy.html`, `faq.html`; `web/api/internal/web/web_test.go`
  (`TestPrivacyDatedAndMentionsData` L60-87). See section 5.
- `shared/commands/exportIcs.ts` and `shared/ics/` lose their last reason to exist (CLAUDE.md says they
  remain only for `ExportFixtureTests` and `ParityTests`). Delete or note as dead in CLAUDE.md.
- `README.md` L19, L25.
- `CLAUDE.md`, `docs/ios-feature-notes.md` (section 5).

---

## 2. Call graph today vs after, and every behaviour change

Today every screen computes `buildAgendaItems(store.events, store.reminders)` -> `agendaWithApple(local:,
snapshot: overlay.snapshot, plans: store.plans + planCache.applePlans, reminders: store.reminders)`.
Post-import the store is already almost empty on the owner's phone (imported ids are filtered in
`PlannerStore.rebuild` L599-601), so for most screens "after" = "today minus the leftovers below".

| Screen | Reads today | Reads after |
|---|---|---|
| Agenda (`AgendaView.makeSections` L309-326) | local rows over display range + 90-day lookback (store loaded via `AgendaWindow.loadRange`), Apple merge, local+sidecar plans, not-imported marks | `agendaWithApple(local: [], snapshot, plans: planCache.applePlans, ...)` |
| Month grid dots (`MonthGridView` -> `gridDensity`) | same pipeline over the grid range | same with `[]` |
| Year (`YearView` -> `yearDensity`) | same over the year | same with `[]` |
| Full Month / Quarter (`FullMonthView` L148, `FullQuarterView` L157 -> `monthLayout`/`gridLayout`) | same | same with `[]` |
| Day / Week (`timelineAgendaItems`) | local events over days, local reminders from min(today, first day), Apple from the day before | Apple only |
| Search (`SearchResults.find`) | ALL local months (`loadAllMonths`) + Apple events +-2 years + all open reminders + completed reminders in the window | Apple only (+-2 years events; completed reminders from 2 years + 90 days back) |
| Planner (`DayPlanModel.make`, `PlanDraft`, `DayHistory`) | local events/reminders/plans for the day's `PlannerDays.loadRange` + Apple + sidecar plans | Apple + sidecar plans |
| Weekly Review (`WeeklyReview.summary`) | local rows of the week (+lookback loaded) + Apple reminders by completion week | Apple only |
| Tag autocomplete (`TagSuggestionRow`) | ALL local months (Add/Edit call `loadAllMonths`) + overlay snapshot | overlay snapshot only (the windows currently registered: agenda, plus Search's +-2 years only while Search is open) |
| Day export (`DayExport.text`) | the agenda's rows for today/yesterday | same, Apple rows only |
| Edit sheet | local items: `EditItemView(item:)` with History and Skip; Apple: `AppleItemEditor` -> details | Apple only |
| Checkbox commit (`PendingCompletions` -> `router.complete`) | local ids -> `PlannerStore.completeReminder` (sync, idempotent, carried-miss sweep); Apple ids -> EventKit | EventKit only |

Behaviour changes (not just wiring):

1. Visible history disappears. Phase 2 deliberately did NOT import (a) completed copies of repeating
   reminders (`ImportPlanner` L13, L54-56: "history: counted, not imported") and (b) finished repeating
   reminder series (L84, "kept in the .ics backup"). Neither is in the ledger, so TODAY they still show
   in past agenda days, Search, Weekly Review weeks, month/year dots and the planner's past-day done
   blocks (`DayPlanModel.doneBlock` matches local completed copies by `seriesID`, L235-245). After phase 3
   they vanish from every screen (the FAQ even promises "completed copies of an imported repeating
   reminder still show in past days and Search", FAQView L37). The gate ("empty plan, no
   unrepresentable") does not cover them. Unknown count; see risk R1.
2. Local overdue semantics end: the 90-day lookback for local reminders, the single carried OLDEST miss
   per repeating reminder, "only misses after the latest completion count", today's occurrence folded
   into the miss, the one-tap clear of every carried miss (`PlannerStore.carriedOccurrences` L569-582),
   "only the NEXT occurrence of a repeating reminder is listed" (issue #107). All of this lives in
   `buildAgendaItems` L143-242 and `PlannerStore.completeReminder`/`skipReminder`. Apple reminders
   already follow Apple's rules (one current occurrence, overdue at any age). The CLAUDE.md "Overdue and
   completion semantics" paragraph (L159) becomes history.
3. Skip for reminders is gone (`showsSkip` was local-only); Undo of a series' completed copy is already a
   notice for Apple. Event "Remove This Occurrence" stays (Apple `deleteOccurrence`).
4. Completion History section in the edit sheet is gone (CompletionHistory; Apple items never had it).
5. Event attended/skipped marks: for Apple events they live only in the sidecar and are shown only in the
   edit sheet (`withStoredItem`). Consequences that become universal after phase 3:
   `AgendaItem.outcome` is nil on every agenda row (no dimming/strikethrough, no sort group 2 for
   events, AgendaBuilder L292-296), the planner's "skipped event frees its slot" (`DayPlanModel` L123,
   issue #117) never fires, and Weekly Review's "Events attended: N" is always 0. Decide: wire sidecar
   outcomes into `mergeAppleItems`/the planner, or drop the attended line. (Same is already true for
   imported events since the import.)
6. Search no longer covers the whole history: Apple events only +-2 years (`SearchWindow.range`), completed
   reminders only from about 2 years + 90 days back. Old imported events are not findable.
7. Tag suggestions lose the full-history corpus (`loadAllMonths` in Add/Edit); only the overlay's current
   windows feed them.
8. Launch and access: nothing shows before the first EventKit fetch lands or without access (the
   AccessRequiredView comment says local items stay visible below it; no longer true).
9. Undated items: only Apple undated reminders (Search, NO DATE pane); local reminders were always dated.
10. Plan blocks: only the sidecar's. Local plan blocks of non-imported leftovers (finished series) and of
    completed copies are no longer shown on past days (`DayHistory` loses those done/missed blocks).
    Imported reminders' plans were moved to the sidecar by the import (`ImportRecord.plans`).
11. Planner title lookup (`PlannerView.title(ofReminder:)` L435) falls back to "Task" for any block whose
    reminder is not in the snapshot (previously local reminders were found first).
12. Midnight rollover / re-centring: `followCalendarDay` and `selectDate` no longer load months first; the
    overlay fetch inside `moveAgendaWindow` is the only gate (already the case for Apple data).
13. Window/fetch ranges: `AgendaWindow.loadRange` remains only as the planner's Apple fetch range
    (`PlannerDays.loadRange`) and `DayPlanModel`'s merge range; `WeeklyReview.loadRange` dies (the review
    already registers `.weeklyReview` with the overlay, WeeklyReviewView L64-67).
14. Router: `complete(today:)` loses its only use (local carried-miss sweep); `replacePlans` no longer
    writes a second store, so a planner save is one sidecar write (no partial-save state).
15. `PendingCompletions.flush()` on backgrounding now always commits asynchronously to EventKit without
    `beginBackgroundTask` (T9a review minor): a tick just before suspension can be lost. Previously local
    ticks were written synchronously.

---

## 3. Dead-code hazards

Look unused but are still needed:
- H0 `DefaultDestinations` lives in `LocalItemStore.swift` (L30-34): move before deleting the file.
- `OccurrenceExpander`: `FakeItemRepository` L66/L336 (contract suite) and `DayPlanModel` L136 (Apple
  events). `spanDays`/`sortAgendaItems` (AgendaBuilder): used by `mergeAppleItems`, `applyPlans`,
  `timelineAgendaItems`, `DayPlanModel`. `AgendaWindow.loadRange` + `overdueLookbackDays`: overlay,
  planner, OverdueLabel. `YearMonth`: grids and densities. `ItemConversion.reminder(from:)`/`event(from:)`:
  internal callers. `CompletionNote`: AgendaRow L303 for Apple rows. `PlanBlock`: sidecar.
  `Reminder.seriesID`/`exceptionDates`/`Event.outcomes`: fake repository, details, `withStoredItem`.
  `SearchResults.matches(_ reminder:)`: Apple reminders.
- H1 `PlannerStore.error` is the main error banner for Apple failures: `ContentView` L102-104, StarkApp L54
  (`PlanCache.onLoadFailure`) and L91 (pending-commit failures), AgendaView L299 (uncomplete), PlannerView
  L118-119/L141 and `PlannerView+Timeline` L27-28. Replace with a small app-target `@Observable` error
  holder (or an `error` property on `NoticeCenter`) injected via `.environment`, BEFORE deleting the store.
- `PlannerStore.warnings` has no reader in the app (dies silently, fine).

Compile but become unreachable after the app stops passing local data (delete in phase 3 or in the
optional slimming task): `buildAgendaItems` (all of it), `marked(notImported:)`/`isNotImported`,
`SearchResults` local loops + `representativeOccurrence`, `TagAutocomplete` local loops,
`TimelineLayout` L126-132 local-series branch, `DayPlanModel` local one-off loop and local `doneBlock`
matching, `DayHistory.classify` local branch, `applyPlans`'s `reminders:` lookup, `PlannerPlans` (identity
with `local: []`), `ItemConversion.droppedMarks`, `AgendaItemDetail.edit/editable`, `EditItemView` `isApple ==
false` branches, `PendingCompletions(commit:)` sync init (tests only), `WeeklyReview.loadRange`,
`YearMonth.fileName`, `ItemRouter.skipReminder` (always throws), `AppleOverlayModel.isEnabled` (always true),
`AgendaItem.isRecurring` for rows (always false for Apple; `showsRepeatGlyph` uses `appleSource`).

Grep results for proposed deletions (who references them today):
- `PlannerStore`: StarkApp, every view listed in 1b, `LocalItemStore`, `ImportModel`; tests: PlannerStore*,
  ImportModel, PendingCompletions, Parity, DateMath (comment), PlanAgenda (comment).
- `PlannerFile`: PlannerStore, StarkApp; tests PlannerStore*, ImportModel, PendingCompletions, Parity, PlannerFile.
- `ICSParser`/`ICSSerializer`/`ICSDateFormat`: PlannerFile, ICS/*; tests ExportFixture, PlanBlockICS,
  ICSParser, ICSSerializer, ICSCompletionTimestamp, PlannerStore, PlannerStorePlans, Parity.
- `RRuleCodec`: ICS/*; tests RRuleCodec, OccurrenceExpander, RepeatEnd; app comment only.
- `CompletionHistory`: EditItemView; tests CompletionHistory*.
- `ImportModel`/`ImportPlanner`/`ImportRunner`/`ImportPlan`/`ImportRecord`: Import/*, ItemSidecar, StarkApp,
  ContentView, SettingsView, ImportStarkItemsView; tests Import*, ItemSidecar*.
- `notImportedIDs`/`isNotImported`/`marked(notImported:)`: PlannerStore, ImportModel, AgendaBuilder,
  PlanAgenda L63, AgendaView, AgendaRow, EditItemView, SearchView, PlannerView+Tray; test PlannerStoreImportHiding.
- `LocalItemStore`: ItemRouter, ItemRouterTests.
- `loadMonths`/`loadAllMonths`/`retryPendingWrites`: 10 views + ContentView, WeeklyReview (doc), ImportModel.

---

## 4. Proposed task breakdown (each leaves `swift test` green and the app building)

Task 1 - Router is Apple-only (Kit + small app edits). CHANGES BEHAVIOUR for writes to the remaining
local leftovers (they become refused).
- Kit: `ItemRouter` as in 1a (no `local`, no `.local` origin/error, no `skipReminder`, `complete` without
  `today:`, `plans(on:)` sidecar-only, `replacePlans` sidecar-only ignoring non-Apple blocks); move
  `DefaultDestinations` into `Items/DefaultDestination.swift`; delete `LocalItemStore.swift`.
- App: StarkApp drops `local: store` (L51); EditItemView drops the reminder skip branch (L551) and
  `showsSkip`; PlannerView `completeBlock` drops `today:`.
- Tests: ItemRouterTests edits listed in 1c (red first: "a non-apple id is refused", "replacePlans ignores
  a non-Apple block").
- Verify: `cd ios && swift test`; simulator Debug build; idb: complete an Apple reminder from the agenda
  and from a planner block, edit/delete an event, plan + save a block, Remove This Occurrence.

Task 2 - The app stops reading the local store and the import UI goes (app + small Kit). CHANGES
BEHAVIOUR (section 2 items 1-13).
- App: new error surface (H1) first; remove `PlannerStore` from StarkApp and the environment; every view
  in 1b reads Apple + `planCache.applePlans` only (pass `[]` for local events/reminders/plans); remove
  `loadMonths`/`loadAllMonths`/`start`/`retryPendingWrites` calls; delete ImportStarkItemsView, the Settings
  row, ImportModel wiring, not-imported marks (AgendaRow, Tray, Search, Agenda, EditItemView), History
  section; `EditItemView.details` non-optional, `isApple` branches removed; decide the Weekly Review
  attended line.
- Kit: `AgendaItemDetail` without `.edit`/`editable` (+ AppleReadOnlyTests); nothing else yet (Kit still
  contains PlannerStore/ICS/Import, unused by the app but still tested).
- Tests: AppleReadOnlyTests change (red first: "a row without appleSource opens read-only").
- Verify on the simulator (iPhone 17) with a Documents folder that still holds `.ics` files (copy some in
  with `xcrun simctl get_app_container ... data`): launch shows only Apple items, no crash, the `.ics` files
  are unchanged (checksum before/after); agenda, month grid dots, Year, Month, Quarter, Week, Day,
  planner (tray, NO DATE, save, past day), Search, Weekly Review, Add with tag suggestions, edit sheet
  (no History, no Skip, convert both ways), Settings without the import row, error banner (force a
  sidecar read failure, e.g. make `sidecar.json` a directory), denied access shows an empty app under the
  access screen. Light and dark screenshots of each screen. Generic iOS Release build and Mac Catalyst
  Debug build (`CODE_SIGNING_ALLOWED=NO`).

Task 3 - Delete the local store code (Kit). PURE DELETION, no behaviour change.
- Delete `PlannerStore`, `PlannerFile`, `ICS/*` (RRuleCodec included or kept, decide), `Import/*`,
  `CompletionHistory`, `isNotImported` + `marked(notImported:)`, `WeeklyReview.loadRange`,
  `YearMonth.fileName` (fix `description`), sidecar import API (keep the ledger keys per H4), PlanAgenda L63.
- Tests: delete/modify per 1c; move the sidecar compatibility tests; add "a sidecar with importLedger
  and importedAt round-trips them unchanged" if the keys are preserved.
- Verify: `swift test` full run, grep for every deleted symbol across `ios/` (zero hits outside history
  docs), simulator smoke (launch, agenda, planner save), generic iOS Release build.

Task 4 - Copy and docs (app FAQ, website, README, CLAUDE.md, feature notes). Copy-only (web test first).
- `TestPrivacyDatedAndMentionsData` rewritten first (drop the import wants; forbid "Import Stark's own
  items", "still shows", "Not imported"); then privacy.html and faq.html; in-app FAQView; README; CLAUDE.md
  and `docs/ios-feature-notes.md` (section 5); Settings/AccessRequired doc comments.
- Verify: `cd web && make test-fast` and `make e2e` (Node 24), FAQ screenshot in the app. The website
  deploy needs the owner's go.

Task 5 (optional, separable; can become a GitHub issue) - Slim the engines to Apple-only inputs.
PURE REFACTOR. Drop `events:`/`reminders:` parameters from `dayDensity`/`gridDensity`/`yearDensity`,
`timelineAgendaItems`, `DayPlanModel.make`, `DayHistory.make/weekStats`, `WeeklyReview.summary`,
`SearchResults.find`, `TagAutocomplete.suggestions`, `applyPlans`/`agendaWithApple`; delete
`buildAgendaItems` and the dead branches in section 3; replace `DayPlanModel` L136 with a start
comparison; collapse `PlannerPlans`. Rewrites roughly 250 engine tests (the KEEP list in 1c) to build
`AppleSnapshot` fixtures instead of local `Event`/`Reminder` values. `OccurrenceExpander` then stays only
for `FakeItemRepository`.

Ordering note: Task 1 before Task 2 keeps the router change unit-testable alone; Task 2 must land before
Task 3 (the app references the store until then). Do NOT drop the import hiding while the app still reads
the store, or imported items would show twice.

---

## 5. Copy that becomes false

In-app (`ios/App/Stark/Stark/FAQView.swift`):
- L34-41 entry "What about the items I made in Stark before?": the whole answer (Settings > Import Stark's
  own items, "hides the imported originals (completed copies ... still show in past days and Search)",
  "Not imported"). Replace with: they were copied into Apple; the old files stay on the device as a
  backup and Stark no longer reads them.
- L92-93 (planner entry): "...and Stark's older ones in the week they were due."
- L100-101 (convert entry): "for Stark's older events, any attended/skipped marks are dropped (Stark asks first)".
- L79 (tags entry) "in the items it has loaded" stays true but the corpus is smaller (fine).
- `SettingsView.swift` L5-7 doc ("Storage is just the local Documents directory"), L65-75 row text.
- `EditItemView.swift` L71 "Apple can't hold this item's repeat, so it stays in Stark's own files..." (deleted with the mark).
- `AccessRequiredView.swift` L8 comment.
- `ios/App/Stark/Info.plist`: both usage strings stay true (no local-file claim).

Website (`web/public/pages`):
- `privacy.html` L26: "and the record of which of Stark's own items were already imported into Apple"
  (only true while the ledger is kept; if H4 keeps the keys, reword to "a record of the one-time import").
- `privacy.html` L30: "Items Stark created before ... may still be stored in files ... Stark can copy them
  into Apple Calendar and Reminders once (Settings, Import Stark's own items); after that Stark hides its
  own copies and keeps the old files ... only as a backup, and it deletes nothing." -> the files stay as
  an untouched backup, Stark no longer reads them.
- `privacy.html` L31 ("Apple's backup includes Stark's files") stays true.
- `faq.html` L23 (the whole "items I made in Stark before" answer: ".ics files ... until you import them
  Stark still shows them ... Import Stark's own items ... marked Not imported").
- `faq.html` L26 "Stark's older items in its own files do not sync; they are included in your normal
  device backups" (still true as backup; reword "items" to "backup files").
- `faq.html` L38 "For Stark's older items, completing or skipping that row clears every miss...".
- `faq.html` L44 "Stark's older events stay on the agenda, marked and dimmed."
- `faq.html` L50 "Search looks through ... everything Stark saved in its own files".
- `faq.html` L59 "Stark's older reminders in the week they were due."
- `faq.html` L62 "(for Stark's older events its URL too ...)" and "for Stark's older events, attended or
  skipped marks are dropped".
- `terms.html` L30 ("and in Stark's own private storage on your device") stays true (sidecar + backup).
- `web/api/internal/web/web_test.go` L65-80: wants "the record of which of Stark's own items were already
  imported", "copy them into Apple Calendar and Reminders once", "Settings, Import Stark's own items",
  "only as a backup", "it deletes nothing"; comment L64-66.

README.md: L19 "stay in `.ics` files in the app's Documents folder until a later update imports them";
L25 "the older `.ics` store".

CLAUDE.md (root): L151 ("does not read todo.txt"... fine) ; L153 Storage paragraph (whole: `recurring.ics`,
`YYYY-MM.ics`, `PlannerFile`, `Library/PendingWrites`, "Stark's older `.ics` items are still shown and
edited ... until phase 2 ... phase 3 then removes this store", "the phase 2 import ledger"); L155 agenda
architecture (`buildAgendaItems` as single source of truth, load range, "anything that moves the window
must `store.loadMonths(covering:)` first"); L157 midnight rollover ("loads `loadRange(around: newToday)`'s
months first"); L159 overdue/completion semantics (local; `PlannerStore.carriedOccurrences`,
`completeReminder` idempotence "lives in the store", commit closure "sends Stark's own ids to
`store.completeReminder`"); L161 feature-notes list; L167 "pull the container ... --source /Documents"
(still valid for pulling the backup, reword); L176 "Kept although the bridge used it"; L180-190 write-through
log ("Stark's older `.ics` items", Deferred > Phase 3 removal L190 becomes Done); L196+ Fantastical log
mentions of local-only fallbacks ("dots fallback for local-only event days"); L217 Next; L219-233 phase 2
log (import, `PlannerStore` gains `importedIDs`...); L252 overdue fix ("lookback applies to Stark's own
items only"); L267 overlay log ("phase 3 removal of the local store"); L273-285 Timeboxing log
(`PlannerStore.replacePlans`, "plan saved in a month that is not loaded"); Repo Structure has no iOS tree
(fine); the "No CLI, no iCloud storage" paragraph L7 (`ExportFixtureTests`/`ParityTests` keep
`shared/ics` alive: false after deletion).

`docs/ios-feature-notes.md`: L7 Completion history (`CompletionHistory`, store stamps); L11 Event attendance
(`PlannerStore.setEventOutcome`); L13 conversion (local path); L23 Search (`PlannerFile.availableMonths`,
`PlannerStore.loadAllMonths`, full history); L25 Timeboxing (`PlannerStore.replacePlans`/`plans`); L29 Weekly
Review (by due date for local); L41 Mac Catalyst ("only Stark's older `.ics` items and its sidecar stay per
device"); L45 Apple overlay and write-through (local router branch, read-only gate).

Spec/plan docs under `docs/superpowers/` are history; leave them.

---

## 6. Risks and unknowns

- R1 History that phase 2 left local (completed copies of repeating reminders, finished repeating
  reminder series, their plan blocks) disappears from every screen. Count unknown from code. Mitigation:
  before shipping, pull the phone's Documents (`xcrun devicectl device copy from --domain-type
  appDataContainer --domain-identifier com.caritos.todo-txt --source /Documents ...`) and count VTODOs with
  a series link / ended RRULE; show the owner the number and get an explicit OK (or import history as
  completed one-offs first, a scope change). The FAQ currently promises they still show.
- R2 `.ics` files at launch: after task 2 nothing opens Documents, so present files are inert. Nothing else
  in the app writes Documents (grep: only `StarkApp.makeStore` L127). Test it explicitly (task 2 verify).
  Files are not visible in the Files app (no `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`);
  they survive app updates and Offload, are deleted with the app, and are in device backups.
- R3 `Library/PendingWrites`: a write that failed and was never retried would sit there and is now never
  replayed (it would also have been invisible to the import if the retry kept failing). Mitigation: pull
  `/Library/PendingWrites` from the phone before shipping; expect it empty. Leave the folder alone in code.
- R4 Sidecar downgrade (H4): if phase 3 stops writing `importLedger`/`importedAt`, an older TestFlight build
  (v2.0.33-v2.0.36) would decode an empty ledger, show "Import Stark's own items" again and could import
  everything a second time (duplicates in iCloud). Mitigation: keep both keys decoded and re-encoded as
  opaque data (no API), or bump the sidecar version so older builds refuse the file (but then older builds
  also lose plans/marks). Keeping the keys is cheaper and reversible.
- R5 Other installs: the gate was checked on the owner's phone only. Any other TestFlight tester who never
  ran the import loses sight of all their Stark-created items. The App Store build is the old Expo app
  (todo.txt), which the native app never read anyway. Mitigation: confirm TestFlight testers = owner only;
  never submit phase 3 for review without this check.
- R6 Error surface (H1): if `store.error` is removed without a replacement, Apple write failures, plan
  cache failures and pending-commit failures become silent. Add the replacement and test it on the
  simulator (task 2).
- R7 Empty first frame: the agenda shows "No Events" until the first EventKit fetch lands (previously
  local items appeared at once). Check on device whether this flashes; consider a loading state.
- R8 Mac Catalyst: the target is sandboxed (`ENABLE_APP_SANDBOX = YES`, pbxproj L261/L305), so its
  Documents is inside its container; no separate path logic exists in code. No `.entitlements` file is in
  the repo (CLAUDE.md lists Catalyst entitlements as unverified). Phase 3 does not change this; build it.
- R9 Weekly Review attended count and agenda outcome dimming become permanently inert (section 2 item 5):
  a product decision, not a removal detail.
- R10 Search/tag scope shrink (items 6-7): old imported events beyond 2 years are not searchable; may
  surprise the owner. Possible follow-up: a dedicated wide Search fetch.
- R11 Background flush (item 15): pending ticks commit asynchronously at suspension without
  `beginBackgroundTask`. Pre-existing for Apple items; now the only path.
- R12 Flaky timing tests (`yearDensity under 2 s`, PendingCompletions live scheduler) may fail under load
  while verifying; shut down simulators first (CLAUDE.md L241).
- Not resolvable from code: how many leftover local items/plans exist on the phone (R1, R3); whether any
  second device has `.ics` data; whether the owner wants the attended feature kept.
