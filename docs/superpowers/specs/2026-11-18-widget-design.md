# Home Screen widget (short design, 2026-11-18, issue #120)

## Why
Fantastical's widgets show the next events and tasks without opening the app. Hypothesis: a glanceable "what's next" on the Home Screen is the feature the owner would use daily. First version is deliberately small. Calls are mine, each reversible.

## Done when
- `cd ios && swift test` green, new Kit tests red first, also under Honolulu, New York and Tokyo; generic iOS Debug and Release builds (`CODE_SIGNING_ALLOWED=NO`) compile with the widget embedded; Mac Catalyst Debug builds (or the widget is excluded from Catalyst with a recorded reason).
- Simulator (iPhone 17): the widget added to the Home Screen shows today's real items from the simulator's Calendar/Reminders (small and medium), updates after an item is added in Stark, shows an access-needed state when Calendar access is denied; screenshots read.
- A signed device Release archive builds with `ios/App/ship.sh`'s flags (automatic signing, ASC key) including the widget; `ship.sh` still uploads (TestFlight only). Registration of the widget App ID and profiles is done by automatic signing; if it cannot be, stop and report.
- Privacy page, web FAQ, in-app FAQ, README, `docs/ios-feature-notes.md`, CLAUDE.md log updated (web test first). Website deploy needs no go.
- NOT done: App Store review, lock-screen and StandBy widgets, interactive (checkbox) widgets, widget configuration, Live Activities, Focus Filters.

## Design
- New target `StarkWidget` (WidgetKit extension, bundle id `com.caritos.todo-txt.widget`, team 3U8L77G9QV, iOS 17), embedded in the app. App Group `group.com.caritos.todo-txt` (already registered in the developer portal) on both targets through new `.entitlements` files.
- Families: `.systemSmall` (the next 3 items) and `.systemMedium` (the next 5 items plus today's date). Rows: time or all-day chip, title, calendar colour dot; reminders with a hollow circle; overdue reminders in red as the app does (open Apple reminders of any age pin to today). Tapping the widget opens Stark (no deep link in v1).
- Data: the widget reads EventKit itself (events from now to the end of tomorrow, open reminders). It honours the app's calendar selection through a mirror: the app writes the excluded calendar ids to the App Group `UserDefaults` suite every time its selection changes (write only; the app keeps reading its own `UserDefaults.standard`, so no migration). Without the mirror (never written) everything is shown.
- Logic in StarkKit, tested: a pure `WidgetAgenda.items(events:reminders:excluded:now:limit:calendar:)` ordering (timed events not yet ended, all-day, overdue/due-today reminders, undated reminders excluded) and the entry times for the timeline (refresh at the next item's start/end, else hourly). The widget view only draws.
- The widget reloads when the app saves (`WidgetCenter.shared.reloadAllTimelines()` after a write and when the selection mirror changes) and on its own timeline.
- Access: no Calendar/Reminders permission prompt from the widget; without access the widget says "Open Stark to allow Calendar access".
- Privacy: nothing leaves the device; the App Group holds only the excluded calendar ids; privacy page notes it.

## Risks
- The Xcode project is hand-made with a folder-synced group and no `project.yml`; adding a target means editing `project.pbxproj` carefully (or via a script) and then re-checking the app target builds unchanged.
- Catalyst: the app supports Mac Catalyst; WidgetKit extensions on Catalyst need the target to support it or be excluded.
- Automatic signing must create the widget App ID and profile in the portal; if `-allowProvisioningUpdates` with the ASC key cannot, the owner registers it.
