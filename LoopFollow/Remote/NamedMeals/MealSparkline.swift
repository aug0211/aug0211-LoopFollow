// LoopFollow
// MealSparkline.swift

import SwiftUI

/// A small BG graph of the 4 hours after a meal: the target range as a band, a
/// tick where eating started, and one line per meal. With several curves, each
/// meal is a faint line and `emphasized` (the typical curve) is drawn on top.
struct MealSparkline: View {
    var curves: [[Int]]
    var emphasized: [Int]?
    var color: Color = .accentColor

    private let thresholds = UnitSettingsStore.shared.effectiveThresholds()

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = yScale
            ZStack {
                // Target range.
                let top = y(thresholds.high, scale: scale, height: size.height)
                let bottom = y(thresholds.low, scale: scale, height: size.height)
                Rectangle()
                    .fill(Color.green.opacity(0.12))
                    .frame(height: max(0, bottom - top))
                    .position(x: size.width / 2, y: (top + bottom) / 2)

                // Eating started.
                Path { path in
                    let startX = x(index: MealOutcome.curveMinutes.firstIndex(of: 0) ?? 0, width: size.width)
                    path.move(to: CGPoint(x: startX, y: 0))
                    path.addLine(to: CGPoint(x: startX, y: size.height))
                }
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                ForEach(Array(curves.enumerated()), id: \.offset) { _, curve in
                    line(curve, scale: scale, size: size)
                        .stroke(
                            emphasized == nil ? color : Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: emphasized == nil ? 1.5 : 1, lineCap: .round, lineJoin: .round)
                        )
                }
                if let emphasized {
                    line(emphasized, scale: scale, size: size)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// Lowest and highest BG shown: the target range plus every reading, padded.
    private var yScale: ClosedRange<Double> {
        let values = (curves + [emphasized ?? []]).flatMap { $0 }.filter { $0 > 0 }.map(Double.init)
        let low = min(values.min() ?? thresholds.low, thresholds.low) - 10
        let high = max(values.max() ?? thresholds.high, thresholds.high) + 10
        return max(0, low) ... high
    }

    private func x(index: Int, width: CGFloat) -> CGFloat {
        let count = max(MealOutcome.curveMinutes.count - 1, 1)
        return width * CGFloat(index) / CGFloat(count)
    }

    private func y(_ value: Double, scale: ClosedRange<Double>, height: CGFloat) -> CGFloat {
        let span = max(scale.upperBound - scale.lowerBound, 1)
        return height * CGFloat(1 - (value - scale.lowerBound) / span)
    }

    /// The curve as a path, broken where readings are missing.
    private func line(_ curve: [Int], scale: ClosedRange<Double>, size: CGSize) -> Path {
        Path { path in
            var drawing = false
            for (index, value) in curve.enumerated() {
                guard value > 0 else {
                    drawing = false
                    continue
                }
                let point = CGPoint(x: x(index: index, width: size.width), y: y(Double(value), scale: scale, height: size.height))
                if drawing {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    drawing = true
                }
            }
        }
    }
}

extension MealOutcome {
    /// Line color for one meal: red after a low, orange after 30+ minutes above range.
    var sparklineColor: Color {
        if hadLow { return .red }
        if minutesAboveRange >= 30 { return .orange }
        return .green
    }
}
