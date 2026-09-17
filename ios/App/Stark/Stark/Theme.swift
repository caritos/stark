// ios/App/Stark/Stark/Theme.swift
import SwiftUI

// Braun/Bauhaus: hard edges, no rounded corners, one accent color, flat geometry.
// Values match mobile/src/theme.ts exactly, so Stark's native app looks identical
// to the Expo app it replaces.
enum Colors {
    static let background = Color(hex: 0x1A1A1A)
    static let accent = Color(hex: 0xE8461A)
    static let text = Color(hex: 0xF0F0F0)
    static let textSecondary = Color(hex: 0x888888)
    static let separator = Color(hex: 0x333333)
    static let checkboxBorder = Color(hex: 0x555555)
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
