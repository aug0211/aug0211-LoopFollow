// LoopFollow
// StatsView.swift
//
// Third watch page (swipe right from Remote). Mirrors the iPhone
// LoopFollow stats block: pie chart for Low / In Range / High
// distribution, plus Avg BG, Est A1C, and Std Dev. Computed over the
// last 24 hours of the bgHistory cache that BGFetcher already holds
// for the chart (~300 readings ≈ 25h from Nightscout or Dexcom Share).
//
// Formulas match LoopFollow/Controllers/Stats.swift exactly:
//   - Low/High thresholds are inclusive (<= lowLine, >= highLine)
//   - Population standard deviation (divide by N, not N-1)
//   - NGSP A1C: (avgBG + 46.7) / 28.7
// IFCC A1C and per-user alt formulas live on the iPhone via
// Storage.useIFCC; we default to NGSP here to keep WatchConfig small.

import Charts
import SwiftUI

struct StatsView: View {
    @ObservedObject var bgFetcher: BGFetcher
    let config: WatchConfig

    var body: some View {
        let stats = StatsCompute.compute(
            history: bgFetcher.bgHistory,
            lowLine: config.lowLine,
            highLine: config.highLine
        )

        // Mirrors ContentView: .edgesIgnoringSafeArea(.vertical) at the
        // TabView level extends the page over both safe areas, then
        // .padding(.top, 30) clears the status bar and .padding(.bottom, 10)
        // lands the footer just above the page-indicator dots.
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                pieChart(stats: stats)
                statsGrid(stats: stats)
            }
            .padding(.horizontal, 6)

            Spacer(minLength: 8)

            if let count = stats?.count {
                Text("Last 24h · \(count) readings")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 30)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func pieChart(stats: StatsResult?) -> some View {
        // Both dimensions must be fixed — Chart/SectorMark inside a
        // ScrollView treats a single-axis .frame as a hint and will
        // otherwise stretch vertically, crowding the stats grid.
        Group {
            if let stats = stats, stats.count > 0 {
                if stats.countRange == stats.count {
                    // 100% in range — celebrate with a shades emoji inside
                    // a solid green ring (xdrip4ios-inspired).
                    ZStack {
                        Circle()
                            .strokeBorder(Color.green, lineWidth: 4)
                        Text("\u{1F60E}") // 😎
                            .font(.system(size: 44))
                    }
                } else {
                    let slices: [PieSlice] = [
                        PieSlice(name: "Low", count: stats.countLow, color: .red),
                        PieSlice(name: "In Range", count: stats.countRange, color: .green),
                        PieSlice(name: "High", count: stats.countHigh, color: .yellow),
                    ]
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Count", slice.count),
                            innerRadius: .ratio(0),
                            angularInset: 0
                        )
                        .foregroundStyle(slice.color)
                    }
                    .chartLegend(.hidden)
                }
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 2)
            }
        }
        .frame(width: 78, height: 78)
    }

    private func statsGrid(stats: StatsResult?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                StatCell(
                    label: "Low",
                    value: percentText(stats?.percentLow),
                    suffix: rangeEdgeDisplay(config.lowLine, delta: 1)
                )
                StatCell(label: "In Range", value: percentText(stats?.percentRange))
                StatCell(
                    label: "High",
                    value: percentText(stats?.percentHigh),
                    suffix: rangeEdgeDisplay(config.highLine, delta: -1)
                )
            }
            HStack(spacing: 4) {
                StatCell(label: "Avg BG", value: avgBGText(stats?.avgBG))
                StatCell(label: "Est A1C", value: a1cText(stats?.a1c))
                StatCell(label: "Std Dev", value: stdDevText(stats?.stdDev))
            }
        }
    }

    // MARK: - Formatting

    private func percentText(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func avgBGText(_ mgdl: Double?) -> String {
        guard let mgdl = mgdl else { return "—" }
        if config.units == "mmol/L" {
            return String(format: "%.1f", mgdl / 18.0182)
        }
        return "\(Int(mgdl.rounded()))"
    }

    private func a1cText(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func stdDevText(_ mgdl: Double?) -> String {
        guard let mgdl = mgdl else { return "—" }
        if config.units == "mmol/L" {
            return String(format: "%.2f", mgdl / 18.0182)
        }
        return String(format: "%.2f", mgdl)
    }

    /// Display the first in-range value on either side of a threshold,
    /// nudged by `delta` mg/dL (±1 for Low/High labels). E.g. with
    /// lowLine=69 and delta=+1 this yields "70"; with highLine=181 and
    /// delta=-1 it yields "180". mmol/L users get a 0.1 mmol nudge.
    private func rangeEdgeDisplay(_ mgdl: Double, delta: Int) -> String {
        if config.units == "mmol/L" {
            let mmol = mgdl / 18.0182 + 0.1 * Double(delta)
            return String(format: "%.1f", mmol)
        }
        return "\(Int(mgdl.rounded()) + delta)"
    }
}

// MARK: - Stat cell

private struct StatCell: View {
    let label: String
    let value: String
    let suffix: String?

    init(label: String, value: String, suffix: String? = nil) {
        self.label = label
        self.value = value
        self.suffix = suffix
    }

    var body: some View {
        VStack(spacing: 1) {
            labelText
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    /// Label + optional threshold annotation, e.g. "Low (<70)".
    /// Rendered via Text concatenation so the two runs share one line and
    /// scale together when space is tight.
    private var labelText: Text {
        let base = Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
        guard let suffix = suffix else { return base }
        return base + Text(" (\(suffix))")
            .font(.system(size: 9))
            .foregroundColor(.secondary)
    }
}

// MARK: - Pie slice model

private struct PieSlice: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let color: Color
}

// MARK: - Stats compute

struct StatsResult {
    let countLow: Int
    let countRange: Int
    let countHigh: Int
    let count: Int
    let percentLow: Double
    let percentRange: Double
    let percentHigh: Double
    let avgBG: Double   // always mg/dL; convert at display time
    let stdDev: Double  // always mg/dL; convert at display time
    let a1c: Double     // percent (NGSP)
}

enum StatsCompute {
    /// Compute 24h distribution / averages from an in-memory BG history.
    /// Matches LoopFollow/Controllers/Stats.swift formulas exactly.
    /// Returns nil when the 24h window is empty.
    static func compute(
        history: [BGReading],
        lowLine: Double,
        highLine: Double
    ) -> StatsResult? {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let window = history.filter { $0.timestamp >= cutoff }
        guard !window.isEmpty else { return nil }

        var countLow = 0
        var countRange = 0
        var countHigh = 0
        var totalGlucose = 0
        for reading in window {
            let bg = Double(reading.bgValue)
            totalGlucose += reading.bgValue
            if bg <= lowLine {
                countLow += 1
            } else if bg >= highLine {
                countHigh += 1
            } else {
                countRange += 1
            }
        }

        let count = window.count
        let avgBG = Double(totalGlucose) / Double(count)

        var partialSum: Double = 0
        for reading in window {
            let diff = Double(reading.bgValue) - avgBG
            partialSum += diff * diff
        }
        let stdDev = sqrt(partialSum / Double(count))

        let a1c = (avgBG + 46.7) / 28.7

        return StatsResult(
            countLow: countLow,
            countRange: countRange,
            countHigh: countHigh,
            count: count,
            percentLow: Double(countLow) / Double(count) * 100,
            percentRange: Double(countRange) / Double(count) * 100,
            percentHigh: Double(countHigh) / Double(count) * 100,
            avgBG: avgBG,
            stdDev: stdDev,
            a1c: a1c
        )
    }
}
