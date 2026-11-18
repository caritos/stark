# Weather in the agenda (short design, 2026-11-18, issue #120)

## Why
Fantastical shows a forecast glyph and temperatures on days. The owner said "go to weather next" and earlier "no need to ask", so the calls below are mine and reversible.

## Done when
- `cd ios && swift test` green with new tests first (red, then green), also under Honolulu, New York and Tokyo.
- Simulator (iPhone 17): with Weather switched on in Settings and a simulated location, the next days' agenda headers show a glyph and high/low; switched off shows nothing and makes no request. Screenshots read.
- Privacy page, web FAQ, in-app FAQ, README, `NSLocationWhenInUseUsageDescription` and `PrivacyInfo.xcprivacy` updated; web tests extended first. Website deploy needs no go.
- NOT done: App Store review (never), App Store Connect privacy-label edit (owner step, listed in the report), widgets, weather on Week/Month/Day views, hourly detail, alerts, severe-weather.

## Privacy stance (this is the first network call Stark makes)
Opt-in, OFF by default; nothing is requested and no location prompt appears until the owner turns it on. Only an approximate position (reduced accuracy, rounded to 0.1 degree, about 11 km) is sent, with nothing else (no identifiers, no calendar data), to MET Norway's public forecast service (api.met.no). The forecast is cached on the device. Never stored with items, never logged.

## Approaches (picked: 1, my call)
1. **MET Norway Locationforecast + CoreLocation reduced accuracy (picked).** Free, global, commercial use allowed with attribution (CC BY 4.0) and an identifying User-Agent; no key, no signing change, fully testable with a fake transport.
2. WeatherKit: Apple first party, but needs the capability on the App ID and a provisioning change, and cannot be verified on the simulator without it. Revisit if MET Norway proves poor.
3. Open-Meteo: easiest, but its free tier is non-commercial and Stark is a paid app.

## Design
- **Kit (testable):** `DayWeather { day: Date (start of the local day), high: Double, low: Double (Celsius), symbol: WeatherSymbol }`; `WeatherSymbol` (clear, partlyCloudy, cloudy, fog, rain, snow, sleet, thunder) with `systemImageName` and an accessibility word; `METNorwayForecast.parse(_ data: Data, calendar: Calendar) throws -> [DayWeather]` (hourly `timeseries` grouped by LOCAL day in the given calendar, high/low from `air_temperature`, symbol from the most frequent daytime `symbol_code` prefix such as `partlycloudy_day`, ignoring `_day/_night/_polartwilight` suffixes); `WeatherCoordinate.rounded(lat:lon:)` to 0.1; `WeatherFormat.temperature(_:locale:)` ("12°" in Celsius or "54°" for the US, by locale measurement system); `WeatherRequest.url(lat:lon:)` (https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=..&lon=..) and the fixed User-Agent string `Stark-iOS https://stark.caritos.com`; `WeatherModelState` logic (stale after 1 hour or when the rounded location changes; fetch only when enabled).
- **App:** a `WeatherModel` (`@MainActor @Observable`) using a transport protocol (URLSession in the app, a fake in tests) and a `LocationProvider` (`CLLocationManager`, `kCLLocationAccuracyReduced`, one-shot, requested only after the toggle is on and status is not determined/authorized); Settings gets a "Weather" section with a toggle, a footer explaining the data and "Forecast data from MET Norway"; agenda day headers show glyph + high/low for days that have a forecast (about 9 days); VoiceOver reads "Rain, high 12, low 6".
- Failure is silent: no location, offline or a bad response shows nothing (no banner); a toggle-on with denied location shows a one-line message in the Settings footer.

## Non-goals
No WeatherKit, no hourly, no other views, no background refresh, no storing the location, no tracking.

## Left to the builder
Exact glyph mapping table, header layout, caching details.
