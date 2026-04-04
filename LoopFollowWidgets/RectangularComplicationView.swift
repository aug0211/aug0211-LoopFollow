// LoopFollow
// RectangularComplicationView.swift

import SwiftUI
import WidgetKit

struct RectangularComplicationView: View {
    let entry: BGEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    private var useColor: Bool {
        renderingMode == .fullColor
    }

    var body: some View {
        if let data = entry.data {
            HStack(spacing: 3) {
                // Left ~65%: Sparkline graph
                SparklineView(history: data.history, useColor: useColor)
                    .frame(maxWidth: .infinity)

                // Right ~35%: Stats panel
                StatsPanel(data: data, useColor: useColor)
                    .frame(width: 52)
            }
            .padding(.horizontal, 2)
        } else {
            Text("No Data")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sparkline Graph

private struct SparklineView: View {
    let history: [WidgetBGPoint]
    let useColor: Bool

    // BG range thresholds (mg/dL)
    private let lowUrgent = 55
    private let low = 70
    private let lowWarn = 80
    private let highWarn = 170
    private let high = 180
    private let highUrgent = 250

    // Graph Y-axis range
    private let yMin: Double = 40
    private let yMax: Double = 300

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sorted = history.sorted { $0.timestamp < $1.timestamp }
            let now = Date()
            let threeHoursAgo = now.addingTimeInterval(-3 * 3600)

            ZStack {
                // Dashed reference lines at 70 and 180
                let y70 = yPosition(for: 70, height: h)
                let y180 = yPosition(for: 180, height: h)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: y70))
                    path.addLine(to: CGPoint(x: w, y: y70))
                }
                .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                .foregroundColor(useColor ? .yellow.opacity(0.5) : .secondary.opacity(0.4))

                Path { path in
                    path.move(to: CGPoint(x: 0, y: y180))
                    path.addLine(to: CGPoint(x: w, y: y180))
                }
                .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                .foregroundColor(useColor ? .yellow.opacity(0.5) : .secondary.opacity(0.4))

                // BG dots
                ForEach(sorted, id: \.timestamp) { point in
                    let x = xPosition(for: point.timestamp, start: threeHoursAgo, end: now, width: w)
                    let y = yPosition(for: Double(point.value), height: h)
                    Circle()
                        .fill(dotColor(for: point.value))
                        .frame(width: 3.5, height: 3.5)
                        .position(x: x, y: y)
                }
            }
        }
    }

    private func xPosition(for date: Date, start: Date, end: Date, width: Double) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        return max(0, min(width, (elapsed / total) * width))
    }

    private func yPosition(for value: Double, height: Double) -> Double {
        let clamped = min(max(value, yMin), yMax)
        let fraction = (clamped - yMin) / (yMax - yMin)
        return height * (1 - fraction) // invert: higher BG = higher on screen
    }

    private func dotColor(for bg: Int) -> Color {
        guard useColor else { return .primary }
        if bg < low || bg > high { return .red }
        if bg < lowWarn || bg > highWarn { return .yellow }
        return .green
    }
}

// MARK: - Stats Panel

private struct StatsPanel: View {
    let data: WidgetData
    let useColor: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            // Line 1: BG value + trend arrow
            HStack(spacing: 1) {
                Text(bgText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(bgColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(data.direction)
                    .font(.system(size: 11))
                    .foregroundColor(bgColor)
            }

            // Line 2: Delta + staleness
            HStack(spacing: 2) {
                if let d = data.delta {
                    Text(deltaText(d))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(useColor ? .white : .primary)
                }
                Text(stalenessText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            // Line 3: IOB / COB
            HStack(spacing: 3) {
                if let iob = data.iob {
                    Text(String(format: "%.1fU", iob))
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(useColor ? .cyan : .primary)
                }
                if let cob = data.cob {
                    Text(String(format: "%.0fg", cob))
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(useColor ? .yellow : .primary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            // Line 4: Basal
            if let rate = data.basalRate {
                let scheduled = data.scheduledBasal ?? rate
                let diff = rate - scheduled
                HStack(spacing: 1) {
                    Text(String(format: "%.2fU", rate))
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(useColor ? basalColor(diff: diff) : .primary)
                    if abs(diff) >= 0.005 {
                        Text(String(format: "%+.2f", diff))
                            .font(.system(size: 8, design: .rounded))
                            .foregroundColor(useColor ? basalColor(diff: diff) : .secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
        }
    }

    private var bgText: String {
        if data.units == "mmol/L" {
            return String(format: "%.1f", Double(data.bgValue) * 0.0555)
        }
        return "\(data.bgValue)"
    }

    private var bgColor: Color {
        guard useColor else { return .primary }
        let bg = data.bgValue
        if bg < 70 || bg > 180 { return .red }
        if bg < 80 || bg > 170 { return .yellow }
        return .green
    }

    private func deltaText(_ delta: Int) -> String {
        if data.units == "mmol/L" {
            let mmol = Double(delta) * 0.0555
            return String(format: "%+.1f", mmol)
        }
        return String(format: "%+d", delta)
    }

    private var stalenessText: String {
        let minutes = Int(Date().timeIntervalSince(data.bgTimestamp) / 60)
        if minutes < 1 { return "now" }
        if minutes <= 5 { return "\(minutes)m" }
        return "\(minutes)m"
    }

    private func basalColor(diff: Double) -> Color {
        if diff > 0.005 { return .orange }
        if diff < -0.005 { return .blue }
        return .green
    }
}
