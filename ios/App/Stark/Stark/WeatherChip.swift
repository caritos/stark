//
//  WeatherChip.swift
//  Stark
//
//  A forecast glyph with high/low, shown in an agenda day header for days that have one. A day
//  without a symbol shows the temperatures only. At accessibility text sizes the glyph and the
//  numbers stack so the header keeps its weekday and date.
//

import StarkKit
import SwiftUI

struct WeatherChip: View {
    let weather: DayWeather
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var glyphSize: CGFloat = 14

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 2))
            : AnyLayout(HStackLayout(spacing: Spacing.xs))
        layout {
            if let symbol = weather.symbol {
                Image(systemName: symbol.systemImageName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: glyphSize))
            }
            Text("\(WeatherFormat.temperature(weather.high, locale: locale))/\(WeatherFormat.temperature(weather.low, locale: locale))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Colors.textSecondary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weather forecast, \(WeatherFormat.spoken(weather, locale: locale))")
    }
}
