# Completion history and carried-over misses (ios/)

Date: 2026-10-14. Status: approved in chat, awaiting written-spec review.

## Intent

The user wants to know *when* a reminder was completed or an event attended, how often a repeating
item is done, and where the gaps are. Mostly daily tasks: "I missed a day but made it up the next
day", and "I missed it for a week". A repeating item that is not done must never create another
row; it carries over.

## 1. One open row per series, carrying the first miss

Replaces "latest miss" (4682eb7) and "daily misses are dropped" in `buildAgendaItems`.

- For every recurring incomplete reminder (daily, weekly, monthly, yearly) the agenda shows at most
  one open row: the **oldest** unresolved occurrence inside the overdue lookback (90 days),
  pinned to today (`isOverdue`), keeping its real date in `occurrence`.
- Today's own occurrence is folded into that row (not shown separately). If there is no miss,
  today's occurrence shows normally.
- Row label: `due <date>` plus days overdue ("7 days overdue"); capped display "90+ days" when the
  miss is at the lookback start.
- One-offs are unchanged (pinned as-is). Events are never overdue.

## 2. Resolving the open row

`completeReminder` / `skipReminder` on the carried occurrence exdate: that occurrence, every later
un-exdated miss in the lookback, and today's occurrence. Complete also appends exactly one
completed one-off copy (as today). Idempotency guarantees stay.

## 3. Data

- `Reminder.completedAt: Date?` — real tick time. `completedDate` keeps meaning due date (Weekly
  Review unaffected). Serialized as `X-STARK-COMPLETED-AT:`.
- `Reminder.seriesID: String?` — master id on completed copies, `X-STARK-SERIES:`.
- `EventOutcomeRecord.recordedAt: Date?` — when attended/skipped was marked; serialized as a
  parameter on the existing `X-STARK-ATTENDED/SKIPPED` line.
- Old files parse unchanged; missing values show nothing. Un-completing clears `completedAt`;
  clearing an event mark removes the record.
- The 2.5 s pending-completion path stamps `completedAt` at commit time.

## 4. History (detail sheet, `EditItemView`)

Pure logic in StarkKit (`CompletionHistory`): for a series (by `seriesID`, falling back to identical
title for older completed copies) compute: done in last 30/90 days split on time vs late, last
done, average and longest gap between completions, and a recent list (due, done, days late).
Events: same over attended marks. Agenda row: secondary "done <date>" only when done on a different
day than due.

## 5. Testing

StarkKit tests: first-miss selection (daily/weekly/monthly), fold of today's occurrence, resolve
clears later misses + today, stamping on complete/attend/pending path, undo clearing, file
round-trip and old-file parse, history stats incl. title fallback. Update tests that encode
"latest miss"/"daily dropped". Verify on device (hit-testing, labels) via `ios/App/deploy.sh`.

## Out of scope

Separate Habits screen, charts, a per-miss ledger (misses collapse into one late completion),
completion timestamps for pre-existing history.
