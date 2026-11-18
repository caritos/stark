# Weather in Day, Week and Month (short design, 2026-11-18, issue #120)

## Why
The owner said "finish the weather". The agenda day headers show an opt-in forecast chip (v2.0.40). Fantastical also shows it in the Day, Week and Month views. Same data, same opt-in, same privacy as before; no new network call, permission or copy about data.

## Done when
- `cd ios && swift test` green with any new Kit tests first (red, then green), also under Honolulu, New York and Tokyo.
- Simulator (iPhone 17, Weather on): the Day view shows the day's chip beside the title; the Week view shows a glyph and high under each day column header; the Month grid shows a small glyph in each day cell that has a forecast; with Weather off none of them shows anything. Screenshots read (light; dark and AX5 where feasible).
- FAQ (app and web) and feature notes name the views where weather appears; web test updated first.
- NOT done: Quarter and Year (too dense), weather on events with a place, hourly detail, any new data sent.

## Approaches (picked: 1, my call)
1. **Reuse `WeatherModel.forecast` and the existing chip pieces in each view (picked).** Day: `WeatherChip` in the header. Week: a compact glyph+high (`WeatherMiniChip`) under each column header. Month: a glyph only in the cell's corner, hidden at accessibility sizes and when the cell is too small.
2. A separate weather strip view: more UI, no gain.

## Design
- Day key: the views already compute the day (`startOfDay` in their Gregorian calendar); look up `weather.forecast[day]` with the SAME key `AgendaView` uses (the model's Gregorian start-of-day keys); add a Kit helper `WeatherDayKey`-style lookup only if the views' calendars could differ (check; a test that the keys match is required).
- Week/Month use temperatures through `WeatherFormat`; VoiceOver labels start "Weather forecast".
- Nothing is shown when Weather is off or no forecast exists for the day; layouts must not shift when it is absent.

## Non-goals
No new settings, no Quarter/Year, no network or privacy change.
