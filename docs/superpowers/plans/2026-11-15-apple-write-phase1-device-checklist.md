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
3. **Alerts.** In an iCloud list in Reminders make a timed reminder with an alert at the due time. In
   Stark change its due date, save; then switch its time off, save; then on again, save. After each
   step Reminders shows the alert on the new day at its old time of day.
4. **Series edit.** Change the title of a repeating event in Stark. Every occurrence in Calendar gets the
   new title; time and repeat are unchanged.
5. **Rule change.** In Calendar move one occurrence of a weekly event to another time. In Stark change
   that event's repeat to daily and save: Stark warns that occurrences edited in Calendar will be reset;
   Cancel leaves the event unchanged.
6. **Skip one.** Open one occurrence of a repeating event, Remove This Occurrence. Only that date
   disappears in Calendar. Also try it on the occurrence you moved in step 5: only the moved one goes.
7. **Delete.** Delete a repeating event in Stark: the dialog says every occurrence goes, and all are gone
   in Calendar. Delete an event you organise that has invitees: the dialog adds that they may be notified.
8. **Unrepresentable repeat.** In Calendar make an event repeat monthly **on the fifth Monday** (Custom >
   Monthly > On the... > fifth > Monday; Stark's positions are 1st-4th and last). In Stark its Repeat
   reads "Custom, set in Calendar", there is no Event/Reminder switch, and Delete's dialog says every
   occurrence goes (Cancel).
9. **Timebox.** Plan an Apple reminder in Plan, save, reopen Plan (block still there), tap the block >
   Done. The reminder is completed in Reminders. (Not expected: if Plan ever shows "Couldn't read
   Stark's plan file", note it; do not try to provoke it.)
10. **Undated reminder.** Make a reminder with no date in Reminders. In Stark it is not in the agenda but
    is in Search and in Plan's NO DATE pane. DRAG it onto today's timeline and save: it appears in
    today's agenda.
11. **Bridge.** Send a `/stark` batch from Claude Code: "Added N items" in Stark and the items in
    Calendar/Reminders. Send the same file again: "Already added", nothing doubled.

## If you have time

12. **Batch across accounts.** Default calendar on iCloud, default list On My iPhone; send a `/stark`
    batch with one event and one reminder: both arrive, or neither and a banner explains why.
13. **Access.** Settings > Privacy & Security > Calendars (then Reminders) > Stark: None (or Add Events
    Only). Stark shows "STARK NEEDS CALENDAR AND REMINDERS" with Open iOS Settings, older Stark items
    still visible, Add disabled. Set Full Access again.
14. **Read-only items.** An invitation and an item on a calendar you cannot change open read-only with
    no Delete; Open in Calendar / Open in Reminders opens the Apple app (the Reminders link is a guess).
15. **Old items.** Items made in Stark before this build still show, open and save as before.
16. **Weekly Review.** Several weeks back: completed Apple reminders show in the week they were
    completed; the Share text includes them.
17. **Hidden calendars.** The default calendar and list cannot be turned off; hide another, add an item:
    it shows.
18. **Errors.** Open an item in Stark, delete it in Calendar, save in Stark: a readable banner, the sheet
    stays open.
19. **Time zone and calendar.** Tokyo time, then a Buddhist or Japanese calendar: today's agenda, Add and
    ticking a reminder land on the right day. Set both back.
20. **Big calendar.** Search a word with a few years of events: results within a couple of seconds.
21. **VoiceOver** (quick pass): access screen, Add's destination picker, Add Date, NO DATE tab, plan
    saving indicator.
22. **Mac** (Catalyst): Stark asks for access and shows the same Apple items as the phone.
