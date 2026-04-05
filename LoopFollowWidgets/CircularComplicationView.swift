// LoopFollow
// CircularComplicationView.swift
//
// Round complication for modular watch faces (accessoryCircular).
// Dark tinted background (green/red/yellow based on BG range), all white text.
// Layout: staleness on top, BG center, delta + trend below.

import SwiftUI
import WidgetKit

struct CircularComplicationView: View {
    let entry: BGEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    private var useColor: Bool {
        renderingMode == .fullColor
    }

    var body: some View {
        if let data = entry.data {
            ZStack {
                if useColor {
                    // Dark tinted circle background
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    bgRangeColorLight(for: data.bgValue),
                                    bgRangeColor(for: data.bgValue)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                } else {
                    AccessoryWidgetBackground()
                }

                VStack(spacing: -4) {
                    // Staleness — top
                    Text(stalenessText(data, displayDate: entry.displayDate))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(stalenessColor(data, displayDate: entry.displayDate))
                        .lineLimit(1)

                    // BG value — center, biggest
                    Text(bgText(data))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(useColor ? .white : .primary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    // Trend arrow + delta — bottom
                    HStack(spacing: 1) {
                        Text(data.direction)
                        if let d = data.delta {
                            Text(deltaText(d, units: data.units))
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(useColor ? .white.opacity(0.9) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Text("--")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func bgText(_ data: WidgetData) -> String {
        if data.units == "mmol/L" {
            return String(format: "%.1f", Double(data.bgValue) * 0.0555)
        }
        return "\(data.bgValue)"
    }

    private func deltaText(_ delta: Int, units: String) -> String {
        if units == "mmol/L" {
            let mmol = Double(delta) * 0.0555
            return String(format: "%+.1f", mmol)
        }
        return String(format: "%+d", delta)
    }

    private func stalenessText(_ data: WidgetData, displayDate: Date) -> String {
        let minutes = Int(displayDate.timeIntervalSince(data.bgTimestamp) / 60)
        if minutes < 1 { return "now" }
        return "\(minutes)m"
    }

    private func stalenessColor(_ data: WidgetData, displayDate: Date) -> Color {
        let minutes = Int(displayDate.timeIntervalSince(data.bgTimestamp) / 60)
        if useColor {
            if minutes >= 16 { return .white.opacity(0.5) }
            if minutes >= 6 { return .white.opacity(0.7) }
            return .white
        } else {
            if minutes >= 16 { return .red }
            if minutes >= 6 { return .secondary }
            return .primary
        }
    }
}
