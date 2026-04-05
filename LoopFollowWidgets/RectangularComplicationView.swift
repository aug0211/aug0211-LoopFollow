// LoopFollow
// RectangularComplicationView.swift
//
// Reusable BG display view for both accessoryRectangular complication and
// future Live Activity usage. Text overlays the left side of a full-width
// filled-area sparkline graph that fades in from left to right.

import SwiftUI
import WidgetKit

// MARK: - Public Complication View (used by Widget + future Live Activity)

/// Full-width filled-area sparkline with text stats overlaid on the left.
/// The graph fades from transparent (left, behind text) to opaque (right).
struct BGComplicationContent: View {
    let data: WidgetData
    let displayDate: Date
    let useColor: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            // Full-width sparkline — fades in from left to right
            SparklineView(
                history: data.history,
                displayDate: displayDate,
                useColor: useColor
            )
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.45)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            // Text overlay on the left
            StatsPanel(data: data, displayDate: displayDate, useColor: useColor)
                .padding(.leading, 2)
        }
        .padding(.horizontal, 2)
    }
}

/// Thin wrapper that reads `BGEntry` and the widget rendering mode, then delegates
/// to `BGComplicationContent`. Kept separate so `BGComplicationContent` can also be
/// used directly in a Live Activity without any WidgetKit dependency.
struct RectangularComplicationView: View {
    let entry: BGEntry
    @Environment(\.widgetRenderingMode) var renderingMode

    private var useColor: Bool {
        renderingMode == .fullColor
    }

    var body: some View {
        if let data = entry.data {
            BGComplicationContent(
                data: data,
                displayDate: entry.displayDate,
                useColor: useColor
            )
        } else {
            Text("No Data")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sparkline Graph (filled-area style)

private struct SparklineView: View {
    let history: [WidgetBGPoint]
    let displayDate: Date
    let useColor: Bool

    // Graph Y-axis range
    private let yMin: Double = 40
    private let yMax: Double = 300

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sorted = history.sorted { $0.timestamp < $1.timestamp }
            let threeHoursAgo = displayDate.addingTimeInterval(-3 * 3600)

            if sorted.count >= 2 {
                // Build line path through BG points
                let linePath = buildLinePath(points: sorted, start: threeHoursAgo, width: w, height: h)

                // Filled area: close the line path down to the bottom
                let fillPath = buildFillPath(points: sorted, start: threeHoursAgo, width: w, height: h)

                ZStack {
                    // Filled area with gradient
                    fillPath
                        .fill(
                            LinearGradient(
                                colors: useColor
                                    ? [Color.green.opacity(0.4), Color.green.opacity(0.05)]
                                    : [Color.primary.opacity(0.3), Color.primary.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Line on top
                    linePath
                        .stroke(
                            useColor ? Color.green : Color.primary,
                            style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)
                        )
                }
            }
        }
    }

    private func buildLinePath(points: [WidgetBGPoint], start: Date, width: Double, height: Double) -> Path {
        Path { path in
            for (i, point) in points.enumerated() {
                let x = xPosition(for: point.timestamp, start: start, end: displayDate, width: width)
                let y = yPosition(for: Double(point.value), height: height)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func buildFillPath(points: [WidgetBGPoint], start: Date, width: Double, height: Double) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }

            let firstX = xPosition(for: first.timestamp, start: start, end: displayDate, width: width)
            let firstY = yPosition(for: Double(first.value), height: height)
            path.move(to: CGPoint(x: firstX, y: firstY))

            for i in 1..<points.count {
                let x = xPosition(for: points[i].timestamp, start: start, end: displayDate, width: width)
                let y = yPosition(for: Double(points[i].value), height: height)
                path.addLine(to: CGPoint(x: x, y: y))
            }

            // Close down to bottom edge and back
            let lastX = xPosition(for: last.timestamp, start: start, end: displayDate, width: width)
            path.addLine(to: CGPoint(x: lastX, y: height))
            path.addLine(to: CGPoint(x: firstX, y: height))
            path.closeSubpath()
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
        return height * (1 - fraction)
    }
}

// MARK: - Stats Panel (overlays left side of graph)

private struct StatsPanel: View {
    let data: WidgetData
    let displayDate: Date
    let useColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Line 1: BG value + trend arrow
            HStack(spacing: 2) {
                Text(bgText)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(bgColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(data.direction)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(bgColor)
            }

            // Line 2: Delta + staleness
            HStack(spacing: 3) {
                if let d = data.delta {
                    Text(deltaText(d))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(useColor ? .white : .primary)
                }
                Text(stalenessText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(stalenessColor)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            // Line 3: IOB / COB
            HStack(spacing: 3) {
                if let iob = data.iob {
                    Text(String(format: "%.1fU", iob))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(useColor ? .cyan : .primary)
                }
                if let cob = data.cob {
                    Text(String(format: "%.0fg", cob))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(useColor ? basalColor(diff: diff) : .primary)
                    if abs(diff) >= 0.005 {
                        Text(String(format: "%+.2f", diff))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
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
        let minutes = Int(displayDate.timeIntervalSince(data.bgTimestamp) / 60)
        if minutes < 1 { return "now" }
        return "\(minutes)m"
    }

    private var stalenessColor: Color {
        let minutes = Int(displayDate.timeIntervalSince(data.bgTimestamp) / 60)
        if minutes >= 16 { return .red }
        if minutes >= 6 { return .secondary }
        return useColor ? .white : .primary
    }

    private func basalColor(diff: Double) -> Color {
        if diff > 0.005 { return .orange }
        if diff < -0.005 { return .blue }
        return .green
    }
}
