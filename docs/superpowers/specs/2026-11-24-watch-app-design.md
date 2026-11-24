# Stark for Apple Watch: design (2026-11-24)

Status: draft for the owner's approval. Part of the Fantastical-parity goal (GitHub issue #120).

## Intent and why

The owner wants to use Stark from the wrist for three things, in his words: **glancing at what is next, completing reminders, and adding items by voice.** Fantastical's Apple Watch app (complications, Up Next, quick add) is the prior art. Hypothesis to test: if the next item is one glance away and a reminder can be ticked or an item dictated without taking out the phone, the owner uses Stark more during the day. Success is the owner using all three on a real watch for a week without reaching for the phone for them.

## Goals

1. **Glance:** an "Up Next" screen (today's and tomorrow's events, due and overdue reminders) and complications showing the next item.
2. **Complete:** tap a reminder on the watch to complete it, using the same rules as the phone (Apple's rules for repeating reminders).
3. **Add by voice:** dictate a phrase ("Lunch with Sarah at 1pm tomorrow", "Pay rent every month"); the existing `QuickAddParser` turns it into a date, time, repeat and kind; the owner sees the result and confirms; it is saved to Apple Calendar or Reminders.
4. Works with the phone out of reach (the watch talks to its own EventKit store, which Apple syncs).
5. Nothing new is stored or sent anywhere: no account, no server, no analytics.

## Non-goals

- Editing, deleting, converting items, templates, Search, Planner, Weekly Review, weather, calendar sets, Focus filter, month/quarter/year views on the watch.
- A phone-mediated design (WatchConnectivity). The watch does not depend on the phone app running.
- Android/Wear OS. Mac.
- Submitting for App Store review (TestFlight only, as always).

## Anti-goals (a failure even if it technically works)

- The watch app shows items the phone does not, or completes a repeating reminder differently from the phone.
- Adding by voice saves something the owner did not see first (it never saves silently on a misparse).
- A permission prompt or empty screen on first launch with no explanation.
- Logic living in the watch views: anything testable goes in `StarkKit`.

## Constraints

- Native only: SwiftUI, watchOS app target embedded in the iOS app; `StarkKit` gains `.watchOS(.v10)` in `Package.swift` (keeps `.iOS(.v17)` and `.macOS(.v14)` so `swift test` still runs on the Mac). watchOS 10 matches iOS 17 as the floor (my call).
- Apple Calendar and Reminders stay the only store. Same sidecar rule as now: Stark writes through `AppleItemRepository` semantics; the watch does not read or write `sidecar.json` (it lives on the phone).
- The pbxproj is edited by hand (folder-synced project, no XcodeGen for `ios/App/Stark`; see `CLAUDE.md`). `ship.sh` and `deploy.sh` must embed and sign the watch app; bundle id `com.caritos.todo-txt.watchkitapp` (my call, conventional).
- Existing shared code: `EventKitProvider.swift` (223 lines, imports only CoreGraphics/EventKit/Foundation/StarkKit) is already compiled into both the app and the widget by file reference; `AppleItemRepository.swift` (719 lines) has no UIKit in it. Both live in the app target today. The watch needs them compiled in too; moving them into `StarkKit` is the builder's call if watchOS builds show a problem with file-reference sharing.
- The App Group `group.com.caritos.todo-txt` does not cross to a separate watch device. The phone's hidden-calendar mirror therefore does not reach the watch (see decisions).
- Tests first for any logic; `cd ios && swift test` stays green; watch UI is verified on the watch simulator and, separately labelled, on a real watch.

## Approaches considered

- **A. Standalone watch app on EventKit (chosen by the owner).** The watch reads and writes Calendar and Reminders itself. Works without the phone nearby; reuses `WidgetAgenda`, `QuickAddParser` and the EventKit code. Risk: whether EventKit's reminder read/write behaves on watchOS and how permission is requested on the watch; checked first by a spike.
- **B. Thin watch app asking the iPhone via WatchConnectivity.** Reuses phone code unchanged but needs the phone reachable and the app woken in the background; the most fragile part of watch apps. Rejected.
- **C. Complications only.** Cheap, but covers only glancing, not completing or voice. Rejected as the whole answer; complications are stage 1 of A.

## Design (decisions, as decided; calls marked "my call")

**Stages** (each ends with its own check; stop and report if a stage's check fails):

- **Stage 0, spike (throwaway, labelled):** a bare watchOS target on the watch simulator that requests Calendar and Reminders access, lists today's items through `EventKitProvider`, completes one reminder and creates one reminder and one event. Records: does the permission prompt appear on the watch, does reminder write work, does an item created on the watch show in the phone's store (simulator pair or real watch), and does `swift build` of `StarkKit` for watchOS succeed. Output is a findings note; the spike code is deleted unless the owner says to keep it (that is a new request).
- **Stage 1, glance:** Up Next list from `WidgetAgenda` rows; watchOS widget extension with complications `accessoryRectangular`, `accessoryInline`, `accessoryCircular`, `accessoryCorner` (my call: reuse the Lock Screen widget views and Kit text helpers). Access-needed and error states reuse the widget's wording. Refresh at least hourly, as the widget does.
- **Stage 2, complete:** tap a reminder row to complete it, via the same idempotent `AppleItemRepository` completion the phone uses; a short undo window is not built (my call: the phone's 2.5 s checkbox window is not copied; completion happens on tap, with a haptic).
- **Stage 3, voice add:** a "+" button opens the system dictation text field; the text goes through `QuickAddParser`; a confirm screen shows kind, title, date/time and repeat from the parse (or "Reminder, no date" / "Event, now" style fallbacks when nothing is recognised: my call: unrecognised text becomes a reminder with no date so nothing is lost); Add saves to the watch's default calendar/list (EventKit defaults on the watch; the phone's `DefaultDestination` setting is a UserDefaults value on the phone and does not reach the watch: my call), Cancel discards.
- **Stage 4, ship:** `ship.sh` (TestFlight) and `deploy.sh` build and embed the watch app; version bump as usual; copy updated (see below).

**Calendars shown (my call):** the watch shows all calendars and lists it can read; hidden-calendar choices and calendar sets made on the phone do not apply on the watch in v1. Deferred: send the selection to the watch (WatchConnectivity application context).

**Where logic lives:** new pure code (rows for the watch list if different from the widget's, the confirm-screen summary, fallback rules for unrecognised dictation) goes in `StarkKit` with Swift Testing tests, red first. Views are thin.

## Calls added after the builder check (all mine, each reversible)

- **If the Stage 0 spike says no** (reminders cannot be read or written on watchOS, or items do not sync): stop, report to the owner with the findings, and let him pick between glance-only (C, complications and a read-only list) and the phone-mediated B. Stages 2 and 3 are contingent on the spike; nothing past Stage 0 starts before the report.
- **Spike also answers:** can a watchOS widget extension read EventKit itself (as the iOS widget does), or does the watch app have to hand it a snapshot? If it cannot, the watch app writes a snapshot into a watch-side App Group for the complications.
- **Local-only sources:** the confirm screen names where the item will go ("Added to <calendar> · <account>", via the Kit's `DestinationLabel`) and shows the existing local-only warning when the watch's default calendar/list is a local source that does not sync (issue #123). It still saves; it does not refuse. The Up Next list gets an "Open Stark on your iPhone / nothing is syncing yet" style empty state when the watch store has no sources.
- **Portal and signing:** the watch app ID, the watch widget extension ID and any watch-side App Group get registered in the developer portal in the owner's logged-in Chrome, as on 2026-11-18, announced before it is done and checked back; this happens at the start of Stage 4 (earlier only if the spike needs a real-watch install).
- **Version:** the watch app's marketing version and build number track the iOS app's (`ship.sh` bumps both together).

## Test hardware (owner's answer, 2026-11-24)

The owner has an Apple Watch Series 12. Assumption (mine, he did not say it): it is paired with the iPhone he installs Stark on. So Stage 0 and later builds can be tried on a real watch, and "standalone EventKit works and items sync to the phone" can be proven on hardware instead of staying unverified. The deployment floor stays watchOS 10 (my call; his watch runs a newer version, so watchOS 10 behaviour is still verified only on the simulator if one is installed). Real-watch checks are recorded as "confirmed on device" separately from "unit-tested" and "simulator-verified". Stage 0's install on the watch uses the same signing as the phone build (team 3U8L77G9QV, automatic).

## Copy and docs ("done includes the website")

- Privacy page, web FAQ, in-app FAQ, README, `Info.plist` usage strings for the watch target, and `PrivacyInfo.xcprivacy` if needed: say the watch app reads and writes Calendar and Reminders on the watch itself, dictation uses the system's speech recognition (which Apple may process on its servers: state that plainly, not "nothing is sent"), nothing else leaves the device. Web tests first, as for the other features (a `TestFAQExplainsWatch` style test and the privacy test extended, seen red first). Website deploy needs no approval once tests, preflight and smoke pass (memory: website deploys).
- `docs/ios-feature-notes.md`: a "Watch app" paragraph. `CLAUDE.md`: a dated log with Done / Not yet verified / Deferred.

## Done when

- Stage 0 findings note written and any "no" answer reported to the owner before Stage 1 starts.
- `cd ios && swift test` green on the merged result (new tests included); `cd web && make test-fast` and `make e2e` green after the copy change.
- Watch simulator screenshots read: Up Next with items, empty state, access-needed state; each complication family on a watch face; a reminder completed (row gone, confirmed in the phone's store); a phrase dictated or typed, the confirm screen, and the item present in Apple's store after Add.
- Signed Release archive with the embedded watch app succeeds (dry run), and TestFlight build uploaded with `ios/App/ship.sh`.
- Report each criterion as met, unmet or not verified.

**Also done when:** the owner has run the build from TestFlight or `deploy.sh` on his Series 12 and reports each of the three jobs (glance, complete, voice add) working, or reports which one does not; until he does they stay "not yet verified on device".

**Not part of done:** VoiceOver, iOS 17 / watchOS 10 runtime, large text sizes, Mac Catalyst, App Store review.

## Left to the builder

File layout of the watch target, whether to share EventKit files by reference or move them to the Kit, exact complication layouts, the watch app's navigation shape, haptics, and the wording of states, following the widget's conventions.
