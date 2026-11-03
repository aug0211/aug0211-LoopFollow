// LoopFollow
// StatsDisplayView.swift

import Charts
import SwiftUI

struct StatsDisplayView: View {
    @ObservedObject var model: StatsDisplayModel
    var onTap: (() -> Void)?

    var body: some View {
        HStack {
            StatsPieChartView(
                pieLow: model.pieLow,
                pieRange: model.pieRange,
                pieHigh: model.pieHigh,
                displayedInRangePercent: model.inRangePercent
            )
            .frame(width: 80, height: 80)
            .padding(.leading, 8)

            VStack(spacing: 10) {
                HStack {
                    statColumn(title: "Low:", value: model.lowPercent)
                    statColumn(title: "In Range:", value: model.inRangePercent)
                    statColumn(title: "High:", value: model.highPercent)
                }
                HStack {
                    statColumn(title: "Avg BG:", value: model.avgBG)
                    statColumn(title: model.estA1CTitle, value: model.estA1C)
                    statColumn(title: model.stdDevTitle, value: model.stdDev)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 100)
        .background(Color(.secondarySystemBackground))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack {
            Text(title)
                .font(.system(size: 15))
            Text(value)
                .font(.system(size: 15))
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatsPieChartView: View {
    var pieLow: Double
    var pieRange: Double
    var pieHigh: Double
    var displayedInRangePercent: String

    private struct Slice: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    private var slices: [Slice] {
        [
            Slice(id: "low", value: max(pieLow, 0.1), color: .red),
            Slice(id: "range", value: max(pieRange, 0.1), color: .green),
            Slice(id: "high", value: max(pieHigh, 0.1), color: .yellow),
        ]
    }

    var body: some View {
        Group {
            // Celebrate whenever the percentage shown to the user is 100%.
            if displayedInRangePercent == String(format: "%.1f%%", 100.0) {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    ZStack {
                        Circle()
                            .strokeBorder(Color.green, lineWidth: max(3, side * 0.05))
                        Text("\u{1F60E}") // 😎
                            .font(.system(size: side * 0.55))
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("100% in range")
            } else {
                Chart(slices) { slice in
                    SectorMark(angle: .value("share", slice.value))
                        .foregroundStyle(slice.color)
                }
                .chartLegend(.hidden)
            }
        }
        .allowsHitTesting(false)
    }
}
