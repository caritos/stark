# Apple write path, phase 1: device checklist (2026-11-15)

For the TestFlight build of phase 1, on the iPhone. Use test items with a recognisable title (e.g.
"P1 test ..."), and delete them in Apple's apps afterwards. Note for each step: works / does not work
/ not tried. Before step 7, on the Mac, after the merge: run `ios/scripts/install-stark-claude.sh`
from the main checkout (the installed CLI is a link to the old build).

1. **Add.** In Stark add a timed event and a reminder. Both appear in Apple Calendar / Reminders
   (in the default calendar and list from Settings > Apple Calendar and Reminders) and, after a
   minute, on another device signed in to the same iCloud.
2. **Repeating reminder.** Make a daily reminder due yesterday; tick it in Stark. It should move to
   its next date after now, and Reminders should show one completed copy. Tap that completed copy in
   Stark and Undo: a notice should say nothing was changed.
3. **Series edit.** Change the title of a repeating event in Stark. Every occurrence in Calendar gets
   the new title; time and repeat are unchanged.
4. **Skip one.** Open one occurrence of a repeating event, Remove This Occurrence. Only that date
   disappears in Calendar.
5. **Delete a series.** Delete a repeating event in Stark. All occurrences are gone in Calendar.
6. **Timebox.** Plan an Apple reminder in Plan, save, reopen Plan (block still there), tap the block >
   Done. The reminder is completed in Reminders. While saving, the plan is dimmed briefly.
7. **Bridge.** Send a `/stark` batch from Claude Code: "Added N items" in Stark and the items in
   Calendar/Reminders. Send the same file again: "Already added", nothing doubled.
8. **Access.** In iOS Settings > Privacy > Calendars (and Reminders) turn Stark off: Stark shows the
   "STARK NEEDS CALENDAR AND REMINDERS" screen with Open iOS Settings, older Stark items still visible,
   Add disabled. Turn access back on.
9. **Read-only items.** An event you were invited to (someone else organises) and an item on a
   calendar you cannot change (e.g. holidays or a read-only shared calendar) open read-only with no
   Delete. There, tap Open in Calendar / Open in Reminders: the Apple app should open (the Reminders
   link is a guess; say if it does nothing).
10. **Old items.** Items made in Stark before this build still show, open and save as before.
11. **Convert refusal.** In Calendar make an event repeating "every 2nd Tuesday of each month" (or
    another custom rule Stark cannot show). In Stark its Repeat reads "Custom, set in Calendar" and
    there is no Event/Reminder switch.
12. **Undated reminder.** Make a reminder with no date in Reminders. Stark: not in the agenda, in Search
    and in Plan's NO DATE pane. DRAG it onto today's timeline and save: it appears in today's agenda.
13. **Weekly Review.** Settings > Weekly Review, go back several weeks: completed Apple reminders show
    in the week they were completed.
14. **Hidden calendars.** In Settings > Apple Calendar and Reminders the default calendar and list
    cannot be turned off; hide another calendar, add an item to the default: it still shows.
15. **Errors.** Try something that should fail (e.g. edit an item, then delete it in Calendar before
    saving in Stark): a readable error banner appears and the sheet stays open.
16. **VoiceOver** (quick pass): the access screen, Add's destination picker, Add Date, the NO DATE tab,
    the plan saving indicator. Each is read sensibly.
17. **Mac (optional).** Run Stark on the Mac (Catalyst): it asks for access and shows Apple items.
