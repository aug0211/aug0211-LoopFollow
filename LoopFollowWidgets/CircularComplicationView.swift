// LoopFollow
// CircularComplicationView.swift
//
// Round complication for modular watch faces (accessoryCircular).
// Shows BG prominently in the center with delta, trend arrow, and
// staleness around it.

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
                // Background gauge ring — shows staleness visually
                // Full ring = fresh (< 1 min), depletes as reading ages
                AccessoryWidgetBackground()

                VStack(spacing: 0) {
                    // BG value — prominent
                    Text(bgText(data))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(bgColor(data))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    // Delta + trend arrow
                    HStack(spacing: 1) {
                        if let d = data.delta {
                            Text(deltaText(d, units: data.units))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                        }
                        Text(data.direction)
                            .font(.system(size: 9))
                    }
                    .foregroundColor(useColor ? .white.opacity(0.9) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    // Staleness
                    Text(stalenessText(data, displayDate: entry.displayDate))
                        .font(.system(size: 8, weight: .regular, design: .rounded))
                        .foregroundColor(stalenessColor(data, displayDate: entry.displayDate))
                        .lineLimit(1)
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Text("--")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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

    private func bgColor(_ data: WidgetData) -> Color {
        guard useColor else { return .primary }
        let bg = data.bgValue
        if bg < 70 || bg > 180 { return .red }
        if bg < 80 || bg > 170 { return .yellow }
        return .green
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
        guard useColor else { return .secondary }
        let minutes = Int(displayDate.timeIntervalSince(data.bgTimestamp) / 60)
        if minutes > 10 { return .red }
        if minutes > 5 { return .yellow }
        return .secondary
    }
}
