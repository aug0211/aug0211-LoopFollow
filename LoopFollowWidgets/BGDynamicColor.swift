// LoopFollow
// BGDynamicColor.swift
//
// Maps a BG value (mg/dL) to a color on the ROYGBIV spectrum.
// Red = 55 and below, Green = 80-110 (in range), Violet = 250+.

import SwiftUI

/// Returns a ROYGBIV-spectrum color for a given BG value in mg/dL.
/// Smoothly interpolates between anchor points:
///   ≤55 Red → 70 Orange → 80 Yellow/Green → 80-110 Green → 150 Blue → 200 Indigo → ≥250 Violet
func bgDynamicColor(_ bg: Double) -> Color {
    // Anchor colors (RGB)
    let red:    (r: Double, g: Double, b: Double) = (1.0,  0.2,  0.15)
    let orange: (r: Double, g: Double, b: Double) = (1.0,  0.6,  0.15)
    let yellow: (r: Double, g: Double, b: Double) = (0.9,  0.85, 0.1)
    let green:  (r: Double, g: Double, b: Double) = (0.2,  0.85, 0.3)
    let blue:   (r: Double, g: Double, b: Double) = (0.15, 0.55, 1.0)
    let indigo: (r: Double, g: Double, b: Double) = (0.35, 0.25, 0.85)
    let violet: (r: Double, g: Double, b: Double) = (0.6,  0.2,  0.85)

    func lerp(_ a: (r: Double, g: Double, b: Double),
              _ b: (r: Double, g: Double, b: Double),
              _ t: Double) -> Color {
        let t = min(max(t, 0), 1)
        return Color(
            red:   a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue:  a.b + (b.b - a.b) * t
        )
    }

    switch bg {
    case ...55:
        return lerp(red, red, 0)
    case 55..<70:
        return lerp(red, orange, (bg - 55) / 15)
    case 70..<80:
        return lerp(orange, green, (bg - 70) / 10)
    case 80...110:
        return lerp(green, green, 0)
    case 110..<150:
        return lerp(green, blue, (bg - 110) / 40)
    case 150..<200:
        return lerp(blue, indigo, (bg - 150) / 50)
    case 200..<250:
        return lerp(indigo, violet, (bg - 200) / 50)
    default:
        return lerp(violet, violet, 0)
    }
}
