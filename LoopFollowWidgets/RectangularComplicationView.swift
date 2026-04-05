// LoopFollow
// RectangularComplicationView.swift
//
// Reusable BG display view for both accessoryRectangular complication and
// future Live Activity usage. Dark tinted background (green/red/yellow based
// on BG range) with white text and sparkline overlaid.

import SwiftUI
import WidgetKit

// MARK: - Shared BG range color palette (very dark, muted tints)

/// Returns a very dark, muted color based on BG range.
/// Near-black with a subtle color tint — not vibrant.
func bgRangeColor(for bg: Int) -> Color {
    if bg < 70 { return Color(red: 0.18, green: 0.04, blue: 0.04) }
    if bg > 180 { return Color(red: 0.16, green: 0.14, blue: 0.02) }
    return Color(red: 0.04, green: 0.14, blue: 0.04)
}

/// Slightly lighter variant for gradient top edge.
func bgRangeColorLight(for bg: Int) -> Color {
    if bg < 70 { return Color(red: 0.24, green: 0.06, blue: 0.06) }
    if bg > 180 { return Color(red: 0.22, green: 0.18, blue: 0.04) }
    return Color(red: 0.06, green: 0.20, blue: 0.06)
}

// MARK: - Public Complication View (used by Widget + future Live Activity)

/// Full-width filled-area sparkline with text stats overlaid on the left.
/// In color mode: dark tinted background, all content white.
struct BGComplicationContent: View {
    let data: WidgetData
    let displayDate: Date
    let useColor: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            // Dark tinted background (color mode only)
            if useColor {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                bgRangeColorLight(for: data.bgValue),
                                bgRangeColor(for: data.bgValue)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

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
                        .init(color: .white, location: 0.55)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            // Text overlay on the left
            StatsPanel(data: data, displayDate: displayDate, useColor: useColor)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 2)
    }
}

/// Thin wrapper that reads `BGEntry` and the widget rendering mode, then delegates
/// to `BGComplicationContent`.
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

// MARK: - Sparkline Graph (filled area with Catmull-Rom curves)

private struct SparklineView: View {
    let history: [WidgetBGPoint]
    let displayDate: Date
    let useColor: Bool

    // Graph Y-axis range
    private let yMin: Double = 40
    private let yMax: Double = 300

    /// Generate Y-axis ticks every 20 mg/dL across the displayable range.
    private var yTicks: [Int] {
        stride(from: 60, through: 280, by: 20).map { $0 }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sorted = history.sorted { $0.timestamp < $1.timestamp }
            let threeHoursAgo = displayDate.addingTimeInterval(-3 * 3600)

            // Convert BG points to screen coordinates
            let screenPoints: [CGPoint] = sorted.map { point in
                CGPoint(
                    x: xPosition(for: point.timestamp, start: threeHoursAgo, end: displayDate, width: w),
                    y: yPosition(for: Double(point.value), height: h)
                )
            }

            let lineColor: Color = useColor ? .white.opacity(0.15) : .secondary.opacity(0.15)
            let labelColor: Color = useColor ? .white.opacity(0.5) : .secondary.opacity(0.7)

            ZStack {
                // Dotted horizontal reference lines + Y-axis labels
                ForEach(yTicks, id: \.self) { value in
                    let y = yPosition(for: Double(value), height: h)

                    // Dotted line across full width
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundColor(lineColor)

                    // Label on right edge
                    Text("\(value)")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(labelColor)
                        .frame(width: 22, alignment: .trailing)
                        .position(x: w - 13, y: y)
                }

                if screenPoints.count >= 2 {
                    // Filled area with gradient
                    buildFillPath(points: screenPoints, height: h)
                        .fill(
                            LinearGradient(
                                colors: useColor
                                    ? [Color.white.opacity(0.25), Color.white.opacity(0.03)]
                                    : [Color.primary.opacity(0.25), Color.primary.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Smooth line on top
                    buildCurvePath(points: screenPoints)
                        .stroke(
                            useColor ? Color.white : Color.primary,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
    }

    // MARK: - Catmull-Rom curve path

    private func buildCurvePath(points: [CGPoint]) -> Path {
        Path { path in
            guard points.count >= 2 else { return }
            path.move(to: points[0])

            if points.count == 2 {
                path.addLine(to: points[1])
                return
            }

            for i in 0..<(points.count - 1) {
                let p0 = points[max(i - 1, 0)]
                let p1 = points[i]
                let p2 = points[min(i + 1, points.count - 1)]
                let p3 = points[min(i + 2, points.count - 1)]

                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6.0,
                    y: p1.y + (p2.y - p0.y) / 6.0
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6.0,
                    y: p2.y - (p3.y - p1.y) / 6.0
                )

                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        }
    }

    private func buildFillPath(points: [CGPoint], height: Double) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: first)

            if points.count == 2 {
                path.addLine(to: last)
            } else {
                for i in 0..<(points.count - 1) {
                    let p0 = points[max(i - 1, 0)]
                    let p1 = points[i]
                    let p2 = points[min(i + 1, points.count - 1)]
                    let p3 = points[min(i + 2, points.count - 1)]

                    let cp1 = CGPoint(
                        x: p1.x + (p2.x - p0.x) / 6.0,
                        y: p1.y + (p2.y - p0.y) / 6.0
                    )
                    let cp2 = CGPoint(
                        x: p2.x - (p3.x - p1.x) / 6.0,
                        y: p2.y - (p3.y - p1.y) / 6.0
                    )

                    path.addCurve(to: p2, control1: cp1, control2: cp2)
                }
            }

            path.addLine(to: CGPoint(x: last.x, y: height))
            path.addLine(to: CGPoint(x: first.x, y: height))
            path.closeSubpath()
        }
    }

    // MARK: - Coordinate helpers

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
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(useColor ? .white : .primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(data.direction)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(useColor ? .white : .primary)
            }

            // Line 2: Delta + staleness
            HStack(spacing: 3) {
                if let d = data.delta {
                    Text(deltaText(d))
                        .font(.system(size: 14, weight: .semibold))
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(useColor ? .white : .primary)
                }
                if let cob = data.cob {
                    Text(String(format: "%.0fg", cob))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(useColor ? .white : .primary)
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(useColor ? .white : .primary)
                    if abs(diff) >= 0.005 {
                        Text(String(format: "%+.2f", diff))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(useColor ? .white.opacity(0.7) : .secondary)
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
        if minutes >= 16 { return useColor ? .white.opacity(0.5) : .red }
        if minutes >= 6 { return useColor ? .white.opacity(0.7) : .secondary }
        return useColor ? .white : .primary
    }
}
