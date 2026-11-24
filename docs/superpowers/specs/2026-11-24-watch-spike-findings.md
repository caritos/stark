# Watch app Stage 0 spike: findings (2026-11-24)

Spec: `2026-11-24-watch-app-design.md` (Stage 0). Plan: `../plans/2026-11-24-watch-app.md` (Task 0).
The spike code is on the throwaway branch `watch-spike` (commit c701d31), never on `watch-app`.

## Verdict

**Writing to EventKit on the watch is impossible for a third-party app.** In the watchOS 27.2 SDK every
EventKit write is marked `__WATCHOS_PROHIBITED` (unavailable at compile time):

- `EKEventStore.save(_:span:commit:)`, `save(_:span:)` (events)
- `EKEventStore.remove(_:span:commit:)`, `remove(_:span:)` (events)
- `EKEventStore.save(_:commit:)`, `remove(_:commit:)` (reminders)
- `EKEventStore.commit()`, `saveCalendar`, `removeCalendar`, `refreshSourcesIfNecessary`

So question (c) is **no**, settled by the compiler, not a runtime behaviour: completing a reminder and
creating a reminder or an event cannot be done on the watch's own store. Stages 2 (complete) and 3 (voice
add) of the spec cannot be built as a standalone EventKit app. Per the spec's "If the Stage 0 spike says
no" call, work stops here until the owner picks:

- **C, glance-only**: Up Next list and complications, read-only, from the watch's own EventKit store. Reads
  compile (see below); whether they return data on the watch still needs the real watch.
- **B, phone-mediated**: the watch sends "complete <id>" / "add <draft>" to the iPhone app over
  WatchConnectivity and the phone writes through its existing `AppleItemRepository`. Cost: the phone must be
  reachable (Bluetooth/Wi-Fi) and the iPhone app woken in the background (`sendMessage` wakes it when
  reachable; `transferUserInfo` queues until the phone app runs), plus an "iPhone not reachable" state and a
  pending queue on the watch. The watch can still read its own store for the list.

## What compiled (watchOS 27.2 SDK, Xcode 27.2)

| Piece | watchOS device (`generic/platform=watchOS`) | watchOS Simulator |
|---|---|---|
| StarkKit with `.watchOS(.v10)` added to `ios/Package.swift` | builds, 0 errors | builds, 0 errors |
| `EventKitProvider.swift` in a watch app (default `@MainActor` isolation, approachable concurrency) | builds | builds |
| `EventKitProvider.swift` in a watchOS WidgetKit extension | builds | builds |
| `AppleItemRepository.swift` in a watch app | **11 errors**, all `... is unavailable in watchOS` (save/remove/commit) | same |
| Spike app + widget without the repository | **BUILD SUCCEEDED**, signed (Apple Development, "iOS Team Provisioning Profile: *", team 3U8L77G9QV) | **BUILD SUCCEEDED** |

- No StarkKit file needed a change for watchOS (compile only; `swift test` does not run on watchOS).
- `@concurrent`, `nonisolated`, `requestFullAccessToEvents/Reminders` (`watchos(10.0)`), `fetchReminders`,
  the reminder predicates, `predicateForEvents`, `events(matching:)`, `defaultCalendarForNewEvents`,
  `defaultCalendarForNewReminders()`, `calendars(for:)`, `EKCalendar.cgColor`, `reset()` and
  `.EKEventStoreChanged` are all available on watchOS.
- Setting properties on `EKReminder`/`EKEvent` compiles; only persisting them is prohibited.
- No simulator runtime is installed and no watch was connected, so nothing has run yet.

## Answers to (a)-(f)

| | Question | Answer |
|---|---|---|
| a | Permission prompt on the watch, Calendars and Reminders | API available on watchOS 10+; **needs the real watch** |
| b | Reminders and events list | Compiles; **needs the real watch** (does the watch's store hold the iCloud data?) |
| c | Complete a reminder, create a reminder and an event | **No** (SDK: writes are `__WATCHOS_PROHIBITED`) |
| d | Watch-created items appear on the iPhone; a completion syncs back | Watch-created: moot (cannot create). Phone-made change showing on the watch: **needs the real watch** |
| e | Account/source of the watch's default calendar and list | Spike shows it; **needs the real watch** (only matters for C's empty state or B's destination) |
| f | Can a watchOS widget extension read EventKit itself | Compiles with `EventKitProvider.fetch`; whether it inherits the app's access and gets data: **needs the real watch** |

## Owner checklist on the Series 12 (only needed if C or B is chosen)

1. iPhone connected to the Mac, Series 12 paired, Developer Mode on the watch (Settings > Privacy &
   Security > Developer Mode). In Xcode open `ios/App/Stark/Stark.xcodeproj` on branch `watch-spike`,
   scheme **StarkWatchSpike**, destination the Series 12, Run (Xcode registers the watch with the team if
   needed). The app is "Stark Spike", bundle id `com.caritos.todo-txt.watchspike`, watch-only.
2. Tap **Request access**: record whether a prompt appears ON THE WATCH, one for Calendars and one for
   Reminders, and the "Access:" header afterwards (`granted`, `denied`, `writeOnly`, `notAsked`).
3. Tap **Read defaults**: record the Calendar and List lines (title · account, `[LOCAL]` if local-only) and
   the calendar/list counts.
4. Tap **Load today**: compare today's events and the open reminders with the phone's Calendar and
   Reminders; note anything missing.
5. The Complete/Add buttons only print "Not possible on watchOS ..." (expected).
6. On the iPhone complete a reminder that the watch listed, wait a minute, tap **Load today** on the watch:
   record whether it is gone (phone to watch sync).
7. Add the "Stark spike" complication to a watch face: record its text ("N ev · M rem", "No access (...)"
   or "Fetch failed").
8. Delete Stark Spike from the watch afterwards.
