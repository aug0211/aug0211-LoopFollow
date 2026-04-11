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
        //
        // Layout strategy: the pie chart is the only flexible element —
        // it takes whatever height is left after the stats grid and
        // footer claim their intrinsic sizes, so on smaller watches it
        // shrinks automatically. Stats grid and footer have fixed sizes
        // tuned to match ContentView's gradient bar (16pt medium) and
        // freshness row (13pt) respectively.
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                pieChart(stats: stats)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxHeight: .infinity)
                    // Inset from each side so the pie doesn't dominate
                    // the page — especially important on smaller watches
                    // where the stats grid needs its share of the height.
                    .padding(.horizontal, 26)

                statsGrid(stats: stats)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)

            if let count = stats?.count {
                Text("Last 24h · \(count) readings")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 30)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func pieChart(stats: StatsResult?) -> some View {
        if let stats = stats, stats.count > 0 {
            if stats.countRange == stats.count {
                // 100% in range — celebrate with a shades emoji inside
                // a solid green ring (xdrip4ios-inspired). GeometryReader
                // sizes the emoji proportionally to the pie so it fills
                // the ring cleanly on every watch size.
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

    private func statsGrid(stats: StatsResult?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                StatCell(
                    label: "Low",
                    value: percentText(stats?.percentLow),
                    suffix: "<\(rangeEdgeDisplay(config.lowLine, delta: 1))"
                )
                StatCell(label: "In Range", value: percentText(stats?.percentRange))
                StatCell(
                    label: "High",
                    value: percentText(stats?.percentHigh),
                    suffix: ">\(rangeEdgeDisplay(config.highLine, delta: -1))"
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
        VStack(spacing: 2) {
            labelText
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    /// Label + optional threshold annotation, e.g. "Low (<70)". Heading
    /// and threshold share a line via Text concatenation so they scale
    /// together when space is tight. Every run on the stats page uses
    /// the same 14pt medium font for a uniform look.
    private var labelText: Text {
        let base = Text(label)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.secondary)
        guard let suffix = suffix else { return base }
        return base + Text(" (\(suffix))")
            .font(.system(size: 14, weight: .medium))
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
