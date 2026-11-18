# Focus Filter: a calendar set per Focus (issue #120)

## Goal
When an iOS Focus (Work, Personal, ...) turns on, Stark shows only the calendars of a saved calendar set; when it turns off, Stark goes back to what it showed. Fantastical parity ("Focus Filters: switch visible calendars when a Focus mode turns on"). Hypothesis: sets are only worth having if the phone switches them for me.

## Done when
- `cd ios && swift test` green; new Kit suite `FocusFilterTests` seen red first.
- Generic iOS Debug build and the signed Release archive dry run succeed.
- Seen on the simulator: Settings > Focus > Add Filter lists "Stark" with a calendar set choice; choosing a set and turning that Focus on changes Stark's bar label and the month grid; turning it off restores them. (If the simulator cannot run Focus filters, say so: NOT verified.)
- NOT part of done: a real device, a real Focus schedule/automation, VoiceOver, Mac Catalyst, App Store review.

## Behaviour
- App Intents `SetFocusFilterIntent` in the app target, title "Calendar Set", one optional parameter `Calendar Set` (an `AppEntity` listing the saved sets by name; nil means "don't change calendars"). No new target, no new entitlement.
- perform() while a Focus turns ON with a set: if nothing is remembered yet, remember the current excluded ids (`before`); apply the set exactly as the bar does (`CalendarSets.selection(applying:allIDs:alwaysShown:)`), remember what was applied (`applied`). If a set was already applied by an earlier Focus, only re-apply (keep the original `before`).
- perform() with no set (Focus turned OFF, or a filter with nothing chosen): if something is remembered and the current selection still equals `applied`, restore `before`; if the owner changed calendars by hand meanwhile, leave their choice. Either way forget the memory.
- A deleted set, no Calendar access or no calendars yet: change nothing and remember nothing.
- State is device-only UserDefaults (`focusFilter.v1`, JSON `{before, applied}`). It writes the same excluded-id key the app reads (`AppleOverlayModel.Key.excluded`), mirrors it to the widget App Group, reloads widget timelines. The running app re-reads the stored selection when it becomes active, so a stale in-memory selection never overwrites the Focus's change.
- The default calendar and list (always shown) are the stored ones (`appleWrite.defaultCalendarID/ListID`); if unset the system default is not known inside the intent, and the app's next `sync()` reapplies the active set.
- Unknown on device: whether iOS runs the intent again with no parameter when the Focus turns off (the docs say the filter is re-run with defaults); the code treats nil that way.

## Not built
Per-Focus "also hide reminders only", Focus-driven widget/weather changes, notification filtering.

## Copy
FAQ (app and web) "Can a Focus switch my calendars?", README, feature notes. Privacy: unchanged in substance (device only); one sentence in the SETS-like storage paragraph is not needed. Web test first.
