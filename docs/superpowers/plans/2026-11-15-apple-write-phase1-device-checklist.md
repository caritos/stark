# Apple write path, phase 1: device checklist (2026-11-15)

## BEFORE SHIP (controller, not the owner)

After merging into main and BEFORE shipping TestFlight or deploying the website, run
`ios/scripts/install-stark-claude.sh` FROM `/Users/eladio/src/stark` (the main checkout; never from a
worktree, which would leave the link dangling once the worktree is removed). `~/.local/bin/stark-claude`
links to the main checkout's old release build, whose `today` still reads the phone's files, while the
new privacy page says the Mac reads none of them. `/stark` itself needs nothing (its file is a symlink
to the main checkout).

## Owner steps (on the iPhone, TestFlight build of phase 1)

Use test items with a recognisable title (e.g. "P1 test ..."), delete them in Apple's apps afterwards,
and note for each step: works / does not work / not tried.

1. **Add.** In Stark add a timed event and a reminder. Both appear in Apple Calendar / Reminders (in the
   default calendar and list from Settings > Apple Calendar and Reminders) and, after a minute, on
   another device signed in to the same iCloud.
2. **Repeating reminder.** In a Reminders list stored in iCloud (not "On My iPhone") make a daily
   reminder due yesterday; tick it in Stark. It should move to its next date after now, and Reminders
   should show one completed copy. Tap that completed copy in Stark and Undo: a notice says nothing
   was changed.
3. **Series edit.** Change the title of a repeating event in Stark. Every occurrence in Calendar gets the
   new title; time and repeat are unchanged.
4. **Rule change.** In Calendar move one occurrence of a weekly event to another time. In Stark change
   that event's repeat to daily and save: Stark warns that occurrences edited in Calendar will be reset;
   Cancel leaves the event unchanged.
5. **Skip one.** Open one occurrence of a repeating event, Remove This Occurrence. Only that date
   disappears in Calendar.
6. **Delete a series.** Delete a repeating event in Stark. All occurrences are gone in Calendar.
7. **Timebox.** Plan an Apple reminder in Plan, save, reopen Plan (block still there), tap the block >
   Done. The reminder is completed in Reminders.
8. **Bridge.** Send a `/stark` batch from Claude Code: "Added N items" in Stark and the items in
   Calendar/Reminders. Send the same file again: "Already added", nothing doubled.
9. **Batch across accounts.** Set the default calendar to an iCloud calendar and the default list to
   one On My iPhone; send a `/stark` batch with one event and one reminder. Both arrive, or neither
   does and a banner explains why.
10. **Access.** Settings > Privacy & Security > Calendars (then Reminders) > Stark: choose None (or Add
    Events Only). Stark shows "STARK NEEDS CALENDAR AND REMINDERS" with Open iOS Settings, older Stark
    items still visible, Add disabled. Set Full Access again.
11. **Read-only items.** An event you were invited to and an item on a calendar you cannot change
    (holidays, a read-only shared calendar) open read-only with no Delete. Tap Open in Calendar / Open
    in Reminders: the Apple app opens (the Reminders link is a guess; say if it does nothing).
12. **Old items.** Items made in Stark before this build still show, open and save as before.
13. **Convert refusal.** In Calendar make an event repeat monthly **on the fifth Monday** (Custom > Monthly >
    On the... > fifth > Monday): Stark's positions are 1st-4th and last, so it cannot hold it
    (`RecurrenceDescriptorTests.fifthMondayIsUnrepresentable`). In Stark its Repeat reads "Custom, set in Calendar" and there is no Event/Reminder switch.
14. **Undated reminder.** Make a reminder with no date in Reminders. In Stark it is not in the agenda but
    is in Search and in Plan's NO DATE pane. DRAG it onto today's timeline and save: it appears in
    today's agenda.

## If you have time

15. **Weekly Review.** Go back several weeks: completed Apple reminders show in the week they were
    completed. The Share button's text includes them.
16. **Hidden calendars.** The default calendar and list cannot be turned off in Settings; hide another
    calendar, add an item: it shows.
17. **Errors.** Open an item in Stark, delete it in Calendar, then save in Stark: a readable error
    banner, the sheet stays open.
18. **Time zone and calendar.** Set the phone to Tokyo time, then to a Buddhist or Japanese calendar:
    today's agenda, Add and ticking a reminder still land on the right day. Set both back.
19. **Big calendar.** With a few years of real events, open Search and type a word: results within a
    couple of seconds.
20. **VoiceOver** (quick pass): the access screen, Add's destination picker, Add Date, the NO DATE tab,
    the plan saving indicator.
21. **Mac** (Catalyst): Stark asks for access and shows the same Apple items as the phone.
