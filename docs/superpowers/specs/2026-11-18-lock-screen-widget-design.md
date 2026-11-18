# Lock Screen widgets (issue #120)

## Goal
Add the Lock Screen families to the existing "Up Next" widget: `accessoryRectangular` (next 2-3 items), `accessoryInline` (the next item on one line) and `accessoryCircular` (how many items are left today). Fantastical parity ("Home screen, Lock Screen and StandBy widgets"). Hypothesis: a glance at the lock screen answers "what's next" without unlocking.

## Done when
- `cd ios && swift test` green; any new Kit logic seen red first.
- Generic iOS Debug build and the signed Release archive dry run succeed; the appex still carries the App Group.
- Seen on the simulator if it can show Lock Screen widgets (customise Lock Screen > add widget); if it cannot, say NOT verified.
- NOT part of done: a real device, StandBy tuning, interactive widgets, VoiceOver, App Store review.

## Behaviour
- Same provider, timeline and `WidgetAgenda.items`; entries get a third list per family via limits: rectangular 3 rows, inline 1, circular count of today's remaining items (events not ended, reminders due or overdue, excluding tomorrow's), capped display "9+".
- Rectangular: one line per item, "time title" (all day: title only with a small "All day" marker avoided; overdue reminders are shown with their title, no red: lock screen is monochrome). Inline: "time title" of the first item, or "Nothing coming up". Circular: the count in a gauge-like ring is NOT used; just the number with a calendar glyph above it.
- Titles use `.privacySensitive()` already (redacted when the device is locked if the owner chose to hide sensitive widget content); the count and times stay.
- `needsAccess` and `failed` states show the same short text in each family. Tapping opens Stark.
- Small widget's StandBy stays disfavoured. No new target, entitlement or data.

## Copy
FAQ (app and web) "Is there a widget?" gains one sentence; README line; feature notes; CLAUDE.md log. Web test first (extend `TestFAQExplainsWidget` with "lock screen").
