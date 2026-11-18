# Conference join links and event time zone (short design, 2026-11-18, issue #120)

## Why
Two items of #120's wishlist that fit the current app: "Conference-call join links detected and shown" and "Time zone card on events". The owner said "then #120" without asking, so the calls below are mine and reversible. Both are read-only presentation of data Apple already holds; no network, no new permission, no privacy change (links are opened only when tapped).

## Done when
- `cd ios && swift test` green with new tests first (red, then green), also under Honolulu, New York and Tokyo.
- Simulator (iPhone 17): an event whose URL, location or notes holds a Zoom/Meet/Teams/Webex/FaceTime link shows a "Join" button on the event detail (and a video glyph on its agenda row); an event in another time zone shows a card "Tokyo · 9:00 AM–10:00 AM JST (your time 7:00 PM–8:00 PM)"; same-zone and all-day events show neither. Screenshots read.
- FAQ (app and web) and feature notes mention both (web test first, anchored phrases); CLAUDE.md log.
- NOT done: dial-in numbers, creating meetings, editing the time zone (Edit keeps the zone untouched), time zones for reminders, attachments, any network fetch of the link.

## Approaches (picked: 1, my call)
1. **Pure Kit detectors over data already fetched, rendered in the existing read-only detail (picked).** `ConferenceLink.detect(url:location:notes:)` returns the first supported https link; `EventTimeZoneCard.make(...)` returns the card text. `AppleCalendarEvent` gains `timeZoneID: String?` (default nil; nil for floating and all-day events), filled from `EKEvent.timeZone`.
2. Ask the system (`NSDataDetector` links, conference APIs): the detector cannot take a fixed context in tests and finds any URL, not conference ones.
3. Show every URL as a button: noisy.

## Design
- **Providers** (host match on the parsed URL, https only, case-insensitive, trailing punctuation trimmed): `zoom.us`/`*.zoom.us` (paths `/j/`, `/my/`, `/s/`, `/w/`), `meet.google.com`, `teams.microsoft.com` (`/l/meetup-join`, `/meet/`) and `teams.live.com/meet`, `*.webex.com`, `facetime.apple.com/join`. The link is searched in `url`, then `location`, then `notes`; the first supported one wins. Anything else (including http, other schemes, a bare "zoom.us") is not a join link.
- **Detail:** a "Join" row with the provider name ("Join Zoom") opening the URL via `openURL` on tap only; VoiceOver "Join Zoom meeting". **Agenda row:** a small video glyph after the time for events with a link (not for all-day chips).
- **Time zone card:** shown only when the event's zone differs from the phone's current zone at the event's start (offset compared at that instant, so DST differences count) and the event is timed; lines: the zone's city/short name and the event's start-end in its zone, then the same in the phone's zone. Formatting through `DateFormatter` with the zones set; 12/24-hour follows the locale.

## Non-goals
No parsing of phone numbers or meeting IDs, no calendar-provider API, no zone editing, no weather-style fetch.

## Left to the builder
Exact card wording within the examples, glyph choice, row layout.
