# Stark for Apple Watch: design (2026-11-24)

Status: **revised 2026-11-24 after the Stage 0 spike; the owner chose approach B (phone-mediated writes).** Needs the owner's approval of the revision. Part of the Fantastical-parity goal (GitHub issue #120).

**Revision note.** The first version (approach A, a standalone watch app on EventKit) was approved, then the Stage 0 spike (`2026-11-24-watch-spike-findings.md`) found that every EventKit write (`saveEvent`, `saveReminder`, `removeReminder`, `commit`) is `__WATCHOS_PROHIBITED` in the watchOS 27.2 SDK, so a watch app cannot complete or create anything itself. The owner picked B: the watch reads its own EventKit store for the list and sends writes to the iPhone app over WatchConnectivity; the iPhone does the saving through `AppleItemRepository`. Everything below is the revised design.

## Intent and why

The owner wants to use Stark from the wrist for three things, in his words: **glancing at what is next, completing reminders, and adding items by voice.** Fantastical's Apple Watch app (complications, Up Next, quick add) is the prior art. Hypothesis to test: if the next item is one glance away and a reminder can be ticked or an item dictated without taking out the phone, the owner uses Stark more during the day. Success is the owner using all three on a real watch for a week without reaching for the phone for them.

## Goals

1. **Glance:** an "Up Next" screen (today's and tomorrow's events, due and overdue reminders) and complications showing the next item.
2. **Complete:** tap a reminder on the watch; the watch sends the command to the iPhone app, which completes it with the same rules as the phone (Apple's rules for repeating reminders). The row leaves the list at once and comes back with an error if the phone reports a failure.
3. **Add by voice:** dictate a phrase ("Lunch with Sarah at 1pm tomorrow", "Pay rent every month"); the existing `QuickAddParser` (on the watch) turns it into a date, time, repeat and kind; the owner sees the result and confirms; the watch sends it to the iPhone, which saves it to Apple Calendar or Reminders in the phone's default calendar/list and replies with where it went.
4. **Glance works without the phone** (the watch reads its own EventKit store, which Apple syncs). **Completing and adding need the iPhone**: when it is not reachable the command is queued on the watch (`transferUserInfo`), shown as "Waiting for iPhone", and runs when the phone app next gets to run. A queued command is never lost and never applied twice.
5. Nothing new is stored or sent anywhere: no account, no server, no analytics. The only transport is the system's watch-to-phone link.

## Non-goals

- Editing, deleting, converting items, templates, Search, Planner, Weekly Review, weather, calendar sets, Focus filter, month/quarter/year views on the watch.
- Writing to EventKit from the watch (impossible: see the revision note).
- Offline completing or adding without any iPhone ever reaching the watch (commands wait in the queue; no other fallback).
- Android/Wear OS. Mac.
- Submitting for App Store review (TestFlight only, as always).

## Anti-goals (a failure even if it technically works)

- The watch app shows items the phone does not, or completes a repeating reminder differently from the phone.
- Adding by voice saves something the owner did not see first (it never saves silently on a misparse).
- A queued add that is applied twice (every command carries an id and the phone remembers the ids it has applied), or a queued command that vanishes silently.
- A permission prompt or empty screen on first launch with no explanation.
- Logic living in the watch views: anything testable goes in `StarkKit`.


## Constraints

- Native only: SwiftUI, watchOS app target embedded in the iOS app; `StarkKit` gains `.watchOS(.v10)` in `Package.swift` (keeps `.iOS(.v17)` and `.macOS(.v14)` so `swift test` still runs on the Mac; the spike confirmed it builds for watchOS with no Kit changes). watchOS 10 matches iOS 17 as the floor (my call).
- Apple Calendar and Reminders stay the only store. All writes happen in the iPhone app through `AppleItemRepository`/the router; the watch never writes, and never reads or writes `sidecar.json` (it lives on the phone). `AppleItemRepository.swift` does NOT compile for watchOS (writes are prohibited) and stays out of the watch targets.
- The pbxproj is edited by hand (folder-synced project, no XcodeGen for `ios/App/Stark`; see `CLAUDE.md`). `ship.sh` and `deploy.sh` must embed and sign the watch app; bundle id `com.caritos.todo-txt.watchkitapp` (my call, conventional).
- Shared code: `EventKitProvider.swift` (reads only) compiles for the watch app and a watch widget extension (spike-verified) and is shared by file reference.
- The App Group `group.com.caritos.todo-txt` does not cross to a separate watch device. The phone's hidden-calendar mirror therefore does not reach the watch (see decisions).
- The transport is WatchConnectivity (`WCSession`), wrapped behind a Kit protocol so all logic is testable with fakes; only thin glue touches `WCSession`.
- Tests first for any logic; `cd ios && swift test` stays green; watch UI is verified on the watch simulator when a runtime exists and on the real watch, each labelled separately (there is NO watchOS simulator runtime installed and 13 GB of disk free on 2026-11-24).

## Approaches considered

- **A. Standalone watch app on EventKit.** Chosen first, then ruled out by the spike: EventKit writes are prohibited on watchOS, so it cannot complete or add.
- **B. Watch reads its own store; writes go to the iPhone over WatchConnectivity (chosen by the owner after the spike).** Covers all three jobs. Costs: completing and adding need the iPhone reachable or a queue, an "iPhone not reachable" state, and real-device testing of the watch-phone link.
- **C. Glance-only (list and complications).** Cheap and fully standalone, but misses completing and voice add. Not chosen; its parts are Stage 1 of B.

## Design (decisions, as decided; calls marked "my call")

**Stages** (each ends with its own check; stop and report if a stage's check fails):

- **Stage 0, spike: done 2026-11-24** (`2026-11-24-watch-spike-findings.md`; spike code on the throwaway branch `watch-spike`). Result: reads compile on the watch (app and widget extension), writes are prohibited. Still needing the real watch: the permission prompt, whether the watch's store holds the iCloud data, whether a watch widget extension gets data, the account of the watch's default calendar/list.
- **Stage 1, glance:** Up Next list from `WidgetAgenda` rows read from the watch's own EventKit; watchOS widget extension with complications `accessoryRectangular`, `accessoryInline`, `accessoryCircular`, `accessoryCorner` (my call: reuse the Lock Screen widget views and Kit text helpers). Access-needed and error states reuse the widget's wording. Refresh at least hourly, as the widget does.
- **Stage 2, the link:** a command protocol and its transport.
  - Kit `WatchEnvelope` (Codable: a `UUID` id, a sent date, and a `WatchCommand` that is `complete` (reminder identifier, optional external id, the occurrence date) or `add` (kind, title, start, end, all-day, recurrence; absolute dates, parsed on the watch so the phone does no re-parsing and no time-zone guessing)) and `WatchReply` (`done(notice, warning)` or `failed(message)`).
  - Phone side: Kit `WatchCommandHandler` applies an envelope through `ItemRepository` and `DefaultDestination`s (the phone's own default calendar/list), replies with `DestinationLabel.addedNotice` and the local-only warning when it applies, and remembers applied envelope ids (a bounded list in UserDefaults) so a redelivered command is acknowledged and not applied again. Completing is already idempotent per occurrence day.
  - Watch side: Kit `WatchOutbox` sends `sendMessage` when the phone is reachable and falls back to `transferUserInfo` (queued, survives relaunch) when it is not; it tracks each envelope as `sending`, `waiting` (queued), `done` or `failed`.
  - Thin glue: `WCSessionTransport` in the iOS app and the watch app, behind a Kit `WatchTransport` protocol; the iOS app activates its `WCSession` at launch so a queued command can wake it in the background (my call).
- **Stage 3, complete:** tap a reminder row; the row leaves the list at once (optimistic), the outbox sends a `complete` envelope; on `failed` the row returns with the error; while `waiting` the row shows "Waiting for iPhone"; no undo window (my call: the phone's 2.5 s checkbox window is not copied; haptic on tap).
- **Stage 4, voice add:** a "+" button opens the system dictation text field; the text goes through `QuickAddParser` on the watch; a confirm screen shows kind, title, date/time and repeat (unrecognised text becomes a reminder with no date so nothing is lost: my call); Add sends an `add` envelope; the watch then shows the phone's reply ("Added to <calendar> · <account>", plus the local-only warning) or "Waiting for iPhone"; Cancel discards. The destination is the PHONE's default calendar/list (my call: it already has a Settings choice and the label logic; the watch has none).
- **Stage 5, ship:** `ship.sh` (TestFlight) and `deploy.sh` build and embed the watch app; version bump as usual; copy updated (see below).

**Calendars shown (my call):** the watch shows all calendars and lists it can read; hidden-calendar choices and calendar sets made on the phone do not apply on the watch in v1. Deferred: send the selection to the watch (WatchConnectivity application context).

**Where logic lives:** all new pure code (the envelope and reply types, the handler, the outbox, the confirm-screen summary and the dictation fallbacks, the list model) goes in `StarkKit` with Swift Testing tests, red first. Views and the `WCSession` glue are thin.

## Calls added after the builder check and the spike (all mine, each reversible)

- **Spike also asked:** can a watchOS widget extension read EventKit itself? It compiles; whether it returns data needs the real watch. If it does not, the watch app writes a snapshot into a watch-side App Group for the complications.
- **Local-only sources:** the phone's reply carries the existing local-only warning when the phone's default calendar/list is a local source that does not sync (issue #123); the item is still saved. The Up Next list gets a "nothing is syncing to this watch yet" empty state when the watch store has no sources.
- **Queue limits (my call):** the watch keeps at most 20 waiting envelopes and drops none silently: past 20 it refuses a new one with a visible message. An envelope waiting more than 7 days is shown as failed ("Not delivered").
- **Portal and signing:** the watch app ID, the watch widget extension ID and any watch-side App Group get registered in the developer portal in the owner's logged-in Chrome, as on 2026-11-18, announced before it is done and checked back; this happens at the start of Stage 5 (earlier only if a real-watch install needs it).
- **Version:** the watch app's marketing version and build number track the iOS app's (`ship.sh` bumps both together).

## Test hardware (owner's answer, 2026-11-24)

The owner has an Apple Watch Series 12 (the Mac's `devicectl` listed only his iPhone 16 Plus and an iPad, not the watch). Assumption (mine, he did not say it): it is paired with the iPhone he installs Stark on. Real-watch checks (the spike checklist, then each stage) are recorded as "confirmed on device" separately from "unit-tested" and "simulator-verified". The deployment floor stays watchOS 10 (my call; his watch runs a newer version). A watch simulator needs a watchOS runtime download (several GB; 13 GB free): ask the owner before downloading one.

## Copy and docs ("done includes the website")

- Privacy page, web FAQ, in-app FAQ, README, `Info.plist` usage strings for the watch target, and `PrivacyInfo.xcprivacy` if needed: say the watch app reads Calendar and Reminders on the watch itself, sends complete and add requests to the iPhone app over the system's watch-to-phone link, dictation uses the system's speech recognition (which Apple may process on its servers: state that plainly, not "nothing is sent"), nothing else leaves the devices. Web tests first, as for the other features (a `TestFAQExplainsWatch` style test and the privacy test extended, seen red first). Website deploy needs no approval once tests, preflight and smoke pass (memory: website deploys).
- `docs/ios-feature-notes.md`: a "Watch app" paragraph. `CLAUDE.md`: a dated log with Done / Not yet verified / Deferred.

## Done when

- `cd ios && swift test` green on the merged result (new tests included); `cd web && make test-fast` and `make e2e` green after the copy change.
- Kit tests cover the link without a device: an add delivered twice is applied once; a failed phone write comes back as `failed`; an unreachable phone queues and later delivers; a full queue refuses visibly.
- Simulator or real-watch screenshots read where a runtime or device exists: Up Next with items, empty and access-needed states; each complication family; a reminder completed (row gone, confirmed in the phone's store); a phrase dictated or typed, the confirm screen, the phone's reply, and the item in Apple's store. Any of these that cannot be seen is reported "not verified".
- Signed Release archive with the embedded watch app succeeds (dry run), and TestFlight build uploaded with `ios/App/ship.sh`.
- Report each criterion as met, unmet or not verified.

**Also done when:** the owner has run the build from TestFlight or `deploy.sh` on his Series 12 and reports each of the three jobs (glance, complete, voice add) working, or reports which one does not, including with the phone out of reach for a moment (queued, then delivered); until he does they stay "not yet verified on device".

**Not part of done:** VoiceOver, watchOS 10 runtime, large text sizes, Mac Catalyst, App Store review.

## Left to the builder

File layout of the watch target and the glue, exact complication layouts, the watch app's navigation shape, haptics, the wording of states, the on-the-wire encoding of the envelope (JSON through `WCSession`'s dictionary), and the size of the applied-id list on the phone (bounded; 200 suggested).
