//
//  WeatherChip.swift
//  Stark
//
//  A forecast glyph with high/low, shown in an agenda day header for days that have one.
//

import StarkKit
import SwiftUI

struct WeatherChip: View {
    let weather: DayWeather
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: weather.symbol.systemImageName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
            Text("\(WeatherFormat.temperature(weather.high, locale: locale))/\(WeatherFormat.temperature(weather.low, locale: locale))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Colors.textSecondary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WeatherFormat.spoken(weather, locale: locale))
    }
}
