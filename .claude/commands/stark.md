---
description: Send the tasks and events from this conversation to the Stark app on my iPhone
---

Turn the tasks and events we have just discussed (or `$ARGUMENTS`, if given) into a request file and send it to Stark with the `stark-claude` CLI. Do not ask me to approve the list first: when I say to add them, add them.

## Permissions

This needs two Bash permissions: `Bash(stark-claude:*)` and `Bash(xcrun devicectl:*)` (the CLI runs `devicectl` itself). A sandboxed session may block `devicectl` and the Mac login Keychain (where the pairing secret lives); if a command fails for that reason, say so and tell me which permission or sandbox setting to change. Do not work around it.

## Before sending

1. If `stark-claude` is not found, tell me to run `ios/scripts/install-stark-claude.sh` from the Stark repo and stop.
2. If it says it is not paired, do the pairing flow: tell me to open Stark > Settings > Claude Code, tap Copy, and run `stark-claude pair` in my own terminal (it asks for the secret with a hidden prompt, or reads it from stdin). Never ask me to paste the secret into the chat and never put it in a command argument, a file or your output.
3. The phone must be unlocked and reachable from this Mac (USB cable or the same Wi-Fi). A locked phone silently drops the request, so the CLI checks first and refuses; if it reports the phone is locked, ask me to unlock it and run the same command again.
4. If you are adding to days that may already be busy, run `stark-claude today --date yyyy-MM-dd` for those days first and spread the tasks so they do not pile onto full days. It is best effort (it reads a copy of the app's data from the unlocked phone, using this Mac's calendar); if it refuses or fails, carry on with a sensible spread and say so.

## The request file

Write JSON to a temporary file (for example `/tmp/stark-request.json`) or pipe it with `stark-claude add -`:

```json
{
  "label": "spanish-practice",
  "items": [
    {
      "kind": "reminder",
      "title": "Practise 20 verbs",
      "notes": "Use the flashcard deck",
      "start": "2026-11-10T18:30",
      "priority": "medium"
    },
    {
      "kind": "event",
      "title": "Spanish class",
      "start": "2026-11-12T19:00",
      "end": "2026-11-12T20:00",
      "location": "Room 4",
      "url": "https://example.com/class",
      "recurrence": { "freq": "weekly", "byDay": ["thu"], "until": "2026-12-17" }
    },
    { "kind": "reminder", "title": "Order the textbook", "start": "2026-11-09" }
  ]
}
```

Fields per item:

- `kind`: `reminder` or `event` (required). `title` (required, at most 500 characters). `start` (required): `yyyy-MM-dd` for a date-only item (an all-day event, or a reminder with no time) or `yyyy-MM-ddTHH:mm` (24-hour).
- Optional: `notes` (at most 5000 characters), `end` (events only; `yyyy-MM-ddTHH:mm`, or just `HH:mm` on the start day; ignored on an all-day event), `location` and `url` (events only in practice; `url` must be http or https), `priority` (`low`, `medium` or `high`; reminders only), `recurrence`.
- `recurrence`: `{ "freq": "daily|weekly|monthly|yearly", "interval": n, "byDay": ["mon","tue","wed","thu","fri","sat","sun"], "until": "yyyy-MM-dd", "count": n }`. Only `freq` is required. `until` may not be before the start.
- `id` is optional and normally left out. The CLI derives a deterministic id from each item's content, so sending the same file again is recognised by the phone as "Already added" and does not duplicate anything. (Two identical items in one file get distinct ids.) Changing any field of an item makes it a new item.
- Times are read in the phone's time zone, not this Mac's. A local time that does not exist (the daylight-saving gap) is rejected for the whole batch.
- Up to 200 items go in one request; larger files are split into batches automatically. Each batch is all-or-nothing on the phone: one bad item rejects its whole batch, and the phone shows a banner naming the item.
- `label` (top level, optional): lowercase letters, digits and dashes, at most 32 characters (anything else is cleaned up). It is added to each item's notes as `%label`, so I can find the whole batch with Search in Stark. Always give a short, descriptive label.

## Sending

Run `stark-claude add <file>` (or `stark-claude add -` with the JSON on stdin). `--print-url` only prints the signed links and sends nothing; do not use it unless I ask.

## Reporting

The CLI cannot see whether the phone accepted anything: there is no return channel. After it finishes, report exactly:

> sent N of M batches

(using the numbers the CLI printed), and name the label to search for, for example "search `%spanish-practice` in Stark". Then ask me to glance at the "Added N items" banner in the app or at Search to confirm. Never say the items were "added", "created" or "saved"; say they were sent. If the CLI stopped partway, say how many batches were sent and which items it lists, and that running the same command again is safe because already-added items are skipped.
