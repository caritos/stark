//
//  WeatherMiniChip.swift
//  Stark
//
//  Compact forecast for the Week column headers (glyph beside the high) and the Month cells
//  (glyph only). Both are one accessibility element whose label starts "Weather forecast".
//  Callers hide them at accessibility text sizes and when a column is too narrow.
//

import StarkKit
import SwiftUI

struct WeatherMiniChip: View {
    let weather: DayWeather
    /// Month cells show the glyph only; Week headers add the high.
    var showsHigh: Bool = true
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 2) {
            if let symbol = weather.symbol {
                Image(systemName: symbol.systemImageName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: showsHigh ? 11 : 10))
            }
            if showsHigh || weather.symbol == nil {
                Text(WeatherFormat.temperature(weather.high, locale: locale))
                    .font(Fonts.mono(10, weight: .medium))
                    .foregroundStyle(Colors.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weather forecast, \(WeatherFormat.spoken(weather, locale: locale))")
    }
}
