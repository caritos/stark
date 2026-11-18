# Quick add, second round (short design, 2026-11-18, issue #120)

## Why
The owner said "then do the quick add". Quick add shipped in v2.0.39 with these listed as Deferred: time ranges ("1-2pm"), "next wednesday" meaning the week after, "every weekday", and the suggestion row coming back after Apply. Same design as `2026-11-18-quick-add-design.md` (a pure Kit parser, a tap-to-apply row, English only, on device).

## Done when
- `cd ios && swift test` green with new tests first (red, then green), also under Honolulu, New York and Tokyo, and with a Buddhist and a Hebrew `Calendar`.
- Simulator (iPhone 17): "Lunch tomorrow 1-2pm" fills Starts 1:00 PM and Ends 2:00 PM; "Standup every weekday at 9am" fills a weekly repeat on Mon-Fri; after Apply the row does not return for the same text; screenshots read.
- FAQ (app and web) lists the new phrases (web test first, anchored); CLAUDE.md quick add log updated (Deferred list shrinks).
- NOT done: other languages, "for 3 days" multi-day, "every other week", places, people, bare "at 7" without am/pm.

## Design (my calls)
- **Time ranges**: "1-2pm", "1pm-2pm", "1 to 2pm", "from 1pm to 2pm", "13:00-14:30", "9am until 10:30am". A missing meridiem on the start takes the end's ("1-2pm" = 1pm-2pm; "11-1pm" = 11am-1pm, i.e. the start is the same or earlier than the end by the nearest reading, never after it). `end` is set (not only duration). A range with the end before the start after meridiem inference is not a range (leave the text). Duration phrases ("for 2 hours") still work and lose to an explicit range.
- **"this/next <weekday>"**: "this friday" = the coming Friday (today if it is Friday); "next friday" = the Friday of next week (the first Friday after the coming Sunday's week boundary: define it as the coming Friday plus 7 days when the coming Friday falls in the current week, else the coming one); a bare "friday" with on/by/before keeps "the next one strictly after today".
- **"every weekday"** = weekly on Mon-Fri; also "every weekend" (Sat, Sun) and "every other day" is NOT done.
- **After Apply**: the row stays hidden while the title equals the title that Apply produced (the app remembers `appliedTitle`); any edit re-enables parsing.
- Keep every existing false-positive rule (a phrase list in the tests must still pass).

## Non-goals
No new UI, no network, no new permission, no other languages.
