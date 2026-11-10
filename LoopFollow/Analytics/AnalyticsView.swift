// LoopFollow
// AnalyticsView.swift

import Charts
import SwiftUI

/// Patterns worth a look, from weeks of Nightscout data: what happened, how often,
/// what differs when it happens, and the evidence. For information only.
struct AnalyticsView: View {
    @ObservedObject private var store = AnalyticsStore.shared
    var onDismiss: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AnalyticsHero(store: store)

                switch store.state {
                case let .loading(message):
                    AnalyticsLoadingCard(message: message, progress: store.progress)
                case let .failed(message):
                    AnalyticsMessageCard(symbol: "wifi.exclamationmark", tint: .orange, title: "Couldn't load", message: message) {
                        store.refresh()
                    }
                case .idle, .ready:
                    EmptyView()
                }

                if let report = store.report {
                    content(report)
                        .opacity(isLoading ? 0.45 : 1)
                        .animation(.easeInOut(duration: 0.25), value: isLoading)
                }

                Text("Analytics shows patterns in past data so they can be discussed with your care team. It's not medical advice and never changes settings. Patterns use the settings in effect at the time of each instance.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDismiss {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done", action: onDismiss)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh analytics")
            }
        }
        .onAppear { store.refreshIfStale() }
    }

    private var isLoading: Bool {
        if case .loading = store.state { return true }
        return false
    }

    @ViewBuilder
    private func content(_ report: AnalyticsReport) -> some View {
        if report.findings.isEmpty {
            AnalyticsMessageCard(
                symbol: "checkmark.seal.fill", tint: .green, title: "Nothing stood out",
                message: "No pattern came up often enough to flag in this period. The sections below still show how things went."
            )
        } else {
            AnalyticsSectionHeader(title: "Worth a look", subtitle: "\(report.findings.count) pattern\(report.findings.count == 1 ? "" : "s"), strongest first")
            VStack(spacing: 12) {
                ForEach(report.findings) { finding in
                    NavigationLink(destination: AnalyticsFindingDetailView(finding: finding, report: report)) {
                        AnalyticsFindingCard(finding: finding, report: report)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }

        if !report.overrides.isEmpty {
            AnalyticsSectionHeader(title: "Overrides at a glance", subtitle: "Each override's typical BG from when it started")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(report.overrides) { summary in
                        AnalyticsOverrideTile(summary: summary, report: report)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
        }

        if !report.overnight.isEmpty {
            AnalyticsSectionHeader(title: "Overnight delivery", subtitle: "What Trio delivered vs scheduled basal, on \(report.cleanNights) nights with no food")
            AnalyticsOvernightCard(bars: report.overnight)
                .padding(.horizontal)
        }

        if report.siteDays.count >= 2 {
            AnalyticsSectionHeader(title: "By day of site", subtitle: "Mean BG on each day after a site change")
            AnalyticsGroupCard(groups: report.siteDays, tint: .teal, convert: true)
                .padding(.horizontal)
        }
    }
}

// MARK: - Hero

private struct AnalyticsHero: View {
    @ObservedObject var store: AnalyticsStore

    private var report: AnalyticsReport? { store.report }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analytics")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.white)
                    Text(periodText)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
            }

            if let report {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(report.findings.count)")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                    Text(report.findings.count == 1 ? "pattern worth a look" : "patterns worth a look")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))
                }
                HStack(spacing: 8) {
                    AnalyticsHeroPill(symbol: "target", text: "\(AnalyticsEngine.percent(report.timeInRange)) in range")
                    AnalyticsHeroPill(symbol: "waveform.path.ecg", text: "\(AnalyticsEngine.percent(report.coverage)) CGM data")
                    if report.cleanNights > 0 {
                        AnalyticsHeroPill(symbol: "moon.fill", text: "\(report.cleanNights) clean nights")
                    }
                }
            }

            Picker("Period", selection: $store.weeks) {
                Text("2 weeks").tag(2)
                Text("4 weeks").tag(4)
                Text("8 weeks").tag(8)
            }
            .pickerStyle(.segmented)
            .onChange(of: store.weeks) { _ in store.refresh() }
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(colors: [Color(red: 0.29, green: 0.20, blue: 0.75), Color(red: 0.55, green: 0.24, blue: 0.80), Color(red: 0.93, green: 0.36, blue: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 220, height: 220)
                    .offset(x: 140, y: -90)
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 160, height: 160)
                    .offset(x: -150, y: 80)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.purple.opacity(0.35), radius: 16, y: 8)
        .padding(.horizontal)
    }

    private var periodText: String {
        guard let report else { return "Patterns from the last \(store.weeks) weeks" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(formatter.string(from: report.start)) – \(formatter.string(from: report.end)) · \(report.readingCount.formatted()) readings"
    }
}

private struct AnalyticsHeroPill: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.18)))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Finding card

private extension AnalyticsFinding {
    var tint: Color {
        switch kind {
        case .overrideLows, .mealLows, .overnightLows: return Color(red: 0.93, green: 0.27, blue: 0.38)
        case .overrideHighs, .mealHighs, .stuckHigh: return .orange
        case .overrideLowThenHigh, .treatedLowRebound: return .purple
        case .overnightBasal: return .indigo
        case .siteAge: return .teal
        case .weekday: return .blue
        }
    }

    var severityText: String {
        switch severity {
        case .warning: return "Look at this"
        case .watch: return "Keep an eye on"
        case .info: return "Good to know"
        }
    }
}

private struct AnalyticsFindingCard: View {
    let finding: AnalyticsFinding
    let report: AnalyticsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(finding.tint.opacity(0.16))
                    Image(systemName: finding.symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(finding.tint)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.severityText.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(0.6)
                        .foregroundColor(finding.tint)
                    Text(finding.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finding.observation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            visual

            if let first = finding.comparisons.first {
                Label {
                    Text(first)
                        .font(.footnote)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundColor(finding.tint)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(finding.tint.opacity(0.08)))
            }

            if finding.total > 0 {
                AnalyticsStrengthBar(finding: finding)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(finding.tint.opacity(0.25), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var visual: some View {
        if !finding.hourly.isEmpty, finding.kind == .overnightBasal {
            AnalyticsHourlyChart(bars: finding.hourly, tint: finding.tint, compact: true)
                .frame(height: 70)
        } else if !finding.groups.isEmpty {
            AnalyticsGroupBars(groups: finding.groups, tint: finding.tint, convert: finding.kind == .siteAge)
                .frame(height: 64)
        } else {
            let flagged = finding.instances.filter(\.flagged).prefix(12).map(\.curve)
            if !flagged.isEmpty {
                AnalyticsSparkline(curves: Array(flagged), emphasized: AnalyticsEngine.medianCurve(Array(flagged)), tint: finding.tint,
                                   lowLine: report.lowLine, highLine: report.highLine)
                    .frame(height: 64)
            }
        }
    }
}

private struct AnalyticsStrengthBar: View {
    let finding: AnalyticsFinding

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [finding.tint.opacity(0.7), finding.tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geometry.size.width * finding.share))
                }
            }
            .frame(height: 6)
            Text("\(finding.count) of \(finding.total)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundColor(.secondary)
            Text(finding.strength)
                .font(.caption2.weight(.bold))
                .foregroundColor(finding.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(finding.tint.opacity(0.14)))
        }
    }
}

// MARK: - Override tile

private struct AnalyticsOverrideTile: View {
    let summary: AnalyticsOverrideSummary
    let report: AnalyticsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(summary.uses) uses · ~\(summary.medianMinutes) min")
                .font(.caption)
                .foregroundColor(.secondary)
            AnalyticsSparkline(curves: summary.curves, emphasized: summary.typical, tint: .accentColor,
                               lowLine: report.lowLine, highLine: report.highLine)
                .frame(height: 54)
            HStack(spacing: 6) {
                AnalyticsChip(text: "Lows \(AnalyticsEngine.percent(Double(summary.newLows) / Double(max(summary.uses, 1))))",
                              tint: Double(summary.newLows) / Double(max(summary.uses, 1)) >= 0.4 ? .red : .secondary)
                AnalyticsChip(text: "Highs \(AnalyticsEngine.percent(Double(summary.highs) / Double(max(summary.uses, 1))))",
                              tint: Double(summary.highs) / Double(max(summary.uses, 1)) >= 0.4 ? .orange : .secondary)
            }
            Text("Peak ~\(Localizer.toDisplayUnits(String(summary.medianPeak)))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: 190, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct AnalyticsChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(tint == .secondary ? .secondary : tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill((tint == .secondary ? Color.secondary : tint).opacity(0.12)))
    }
}

// MARK: - Overnight

private struct AnalyticsOvernightCard: View {
    let bars: [AnalyticsHourBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AnalyticsHourlyChart(bars: bars, tint: .indigo, compact: false)
                .frame(height: 170)
            HStack(spacing: 14) {
                legend(color: .indigo, text: "More than scheduled")
                legend(color: .cyan, text: "Less than scheduled")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

private struct AnalyticsHourlyChart: View {
    let bars: [AnalyticsHourBar]
    let tint: Color
    let compact: Bool

    var body: some View {
        if compact {
            chart
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        } else {
            chart
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) { Text("\(Int(number))%") }
                        }
                    }
                }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Hour", AnalyticsEngine.hourText(bar.hour)),
                    y: .value("Delivered", bar.ratio * 100)
                )
                .foregroundStyle(bar.ratio >= 1 ? tint.gradient : Color.cyan.gradient)
                .cornerRadius(5)
                .annotation(position: .top) {
                    if !compact {
                        Text(AnalyticsEngine.percent(bar.ratio))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            RuleMark(y: .value("Scheduled", 100))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.secondary)
                .annotation(position: .top, alignment: .leading) {
                    if !compact {
                        Text("Scheduled")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
        }
    }
}

// MARK: - Groups

private struct AnalyticsGroupCard: View {
    let groups: [AnalyticsGroupBar]
    let tint: Color
    let convert: Bool

    var body: some View {
        AnalyticsGroupBars(groups: groups, tint: tint, convert: convert)
            .frame(height: 150)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct AnalyticsGroupBars: View {
    let groups: [AnalyticsGroupBar]
    let tint: Color
    /// Values are mg/dL to show in the user's units; otherwise plain numbers (percent).
    let convert: Bool

    var body: some View {
        Chart(groups) { group in
            BarMark(
                x: .value("Group", group.label),
                y: .value("Value", convert ? UnitSettingsStore.shared.convertMgdlToDisplay(group.value) : group.value)
            )
            .foregroundStyle(tint.gradient)
            .cornerRadius(6)
            .annotation(position: .top) {
                Text(convert ? Localizer.toDisplayUnits(String(Int(group.value.rounded()))) : "\(Int(group.value.rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
        .chartYAxis(.hidden)
    }
}

// MARK: - Sparkline

/// Many faint BG curves with a bold typical one, the target range as a band, and a
/// tick at the moment the curves line up on (30 minutes in).
struct AnalyticsSparkline: View {
    let curves: [[Int]]
    var emphasized: [Int]?
    var tint: Color
    var lowLine: Double
    var highLine: Double

    private var anchorIndex: Int { -AnalyticsInstance.curveStartMinutes / 5 }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = yScale
            ZStack {
                let top = y(highLine, scale, size.height)
                let bottom = y(lowLine, scale, size.height)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green.opacity(0.12))
                    .frame(height: max(0, bottom - top))
                    .position(x: size.width / 2, y: (top + bottom) / 2)
                Path { path in
                    let x = xPosition(anchorIndex, size.width)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                ForEach(Array(curves.enumerated()), id: \.offset) { _, curve in
                    line(curve, scale, size)
                        .stroke(tint.opacity(emphasized == nil ? 0.9 : 0.22), style: StrokeStyle(lineWidth: emphasized == nil ? 1.6 : 1, lineCap: .round, lineJoin: .round))
                }
                if let emphasized {
                    line(emphasized, scale, size)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        .shadow(color: tint.opacity(0.35), radius: 3)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var yScale: ClosedRange<Double> {
        let values = (curves + [emphasized ?? []]).flatMap { $0 }.filter { $0 > 0 }.map(Double.init)
        let low = min(values.min() ?? lowLine, lowLine) - 10
        let high = max(values.max() ?? highLine, highLine) + 10
        return max(0, low) ... high
    }

    private func xPosition(_ index: Int, _ width: CGFloat) -> CGFloat {
        let count = (AnalyticsInstance.curveEndMinutes - AnalyticsInstance.curveStartMinutes) / 5
        return width * CGFloat(index) / CGFloat(max(count, 1))
    }

    private func y(_ value: Double, _ scale: ClosedRange<Double>, _ height: CGFloat) -> CGFloat {
        height * CGFloat(1 - (value - scale.lowerBound) / max(scale.upperBound - scale.lowerBound, 1))
    }

    private func line(_ curve: [Int], _ scale: ClosedRange<Double>, _ size: CGSize) -> Path {
        Path { path in
            var drawing = false
            for (index, value) in curve.enumerated() {
                guard value > 0 else { drawing = false; continue }
                let point = CGPoint(x: xPosition(index, size.width), y: y(Double(value), scale, size.height))
                if drawing { path.addLine(to: point) } else { path.move(to: point); drawing = true }
            }
        }
    }
}

// MARK: - Shared pieces

private struct AnalyticsSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

private struct AnalyticsLoadingCard: View {
    let message: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                Text(message)
                    .font(.subheadline.weight(.medium))
            }
            ProgressView(value: progress)
                .tint(.purple)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .padding(.horizontal)
    }
}

private struct AnalyticsMessageCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(tint.gradient)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .padding(.horizontal)
    }
}

// MARK: - Detail

struct AnalyticsFindingDetailView: View {
    let finding: AnalyticsFinding
    let report: AnalyticsReport

    @State private var showAll = false

    private var flagged: [AnalyticsInstance] { finding.instances.filter(\.flagged) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !finding.instances.isEmpty {
                    card(title: "Every time, lined up", subtitle: "From 30 minutes before to 4 hours after. Colored lines showed the pattern; the bold one is typical.") {
                        AnalyticsOverlayChart(instances: finding.instances, tint: finding.tint, lowLine: report.lowLine, highLine: report.highLine)
                            .frame(height: 220)
                    }
                }
                if !finding.hourly.isEmpty {
                    card(title: "Overnight delivery", subtitle: "Trio's delivery vs scheduled basal, by hour") {
                        AnalyticsHourlyChart(bars: finding.hourly, tint: .indigo, compact: false)
                            .frame(height: 170)
                    }
                }
                if !finding.groups.isEmpty {
                    card(title: "Compared", subtitle: nil) {
                        AnalyticsGroupBars(groups: finding.groups, tint: finding.tint, convert: finding.kind == .siteAge)
                            .frame(height: 150)
                    }
                }
                if !finding.comparisons.isEmpty {
                    card(title: "What's different when it happens", subtitle: "Factors that clearly differ between the times it happened and the times it didn't") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(finding.comparisons, id: \.self) { text in
                                Label {
                                    Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: "arrow.left.arrow.right.circle.fill").foregroundColor(finding.tint)
                                }
                            }
                        }
                    }
                }
                if !finding.considerations.isEmpty {
                    card(title: "Things that could explain it", subtitle: "Worth discussing with your care team") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(finding.considerations.enumerated()), id: \.offset) { index, text in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(finding.tint))
                                    Text(text)
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                if !finding.instances.isEmpty {
                    instancesCard
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(finding.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.2))
                    Image(systemName: finding.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.severityText.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(0.6)
                        .foregroundColor(.white.opacity(0.85))
                    Text(finding.title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(finding.observation)
                .font(.body)
                .foregroundColor(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
            if finding.total > 0 {
                HStack(spacing: 8) {
                    AnalyticsHeroPill(symbol: "number", text: "\(finding.count) of \(finding.total)")
                    AnalyticsHeroPill(symbol: "chart.bar.fill", text: finding.strength)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [finding.tint, finding.tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: finding.tint.opacity(0.3), radius: 12, y: 6)
    }

    private var instancesCard: some View {
        let list = showAll ? finding.instances : Array(finding.instances.prefix(12))
        return card(title: "Each time", subtitle: "\(flagged.count) showed the pattern, \(finding.instances.count - flagged.count) didn't") {
            VStack(spacing: 0) {
                ForEach(list) { instance in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(instance.flagged ? finding.tint : Color.secondary.opacity(0.35))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(instance.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                .font(.subheadline)
                            Text(instance.label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        AnalyticsSparkline(curves: [instance.curve], tint: instance.flagged ? finding.tint : .secondary,
                                           lowLine: report.lowLine, highLine: report.highLine)
                            .frame(width: 96, height: 34)
                    }
                    .padding(.vertical, 8)
                    if instance.id != list.last?.id { Divider() }
                }
                if finding.instances.count > 12 {
                    Button(showAll ? "Show fewer" : "Show all \(finding.instances.count)") {
                        withAnimation { showAll.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 10)
                }
            }
        }
    }

    private func card<Content: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// Every instance's BG lined up on its start, with the typical curve bold and the target range shaded.
private struct AnalyticsOverlayChart: View {
    let instances: [AnalyticsInstance]
    let tint: Color
    let lowLine: Double
    let highLine: Double

    private struct Point: Identifiable {
        let id: String
        let series: String
        let minute: Int
        let value: Double
        let flagged: Bool
    }

    private var points: [Point] {
        instances.prefix(40).flatMap { instance in
            instance.curve.enumerated().compactMap { index, value -> Point? in
                guard value > 0 else { return nil }
                let minute = AnalyticsInstance.curveStartMinutes + index * 5
                return Point(id: instance.id + "-\(index)", series: instance.id, minute: minute,
                             value: UnitSettingsStore.shared.convertMgdlToDisplay(Double(value)), flagged: instance.flagged)
            }
        }
    }

    private var typical: [(minute: Int, value: Double)] {
        let curves = instances.filter(\.flagged).map(\.curve)
        guard let median = AnalyticsEngine.medianCurve(curves.isEmpty ? instances.map(\.curve) : curves) else { return [] }
        return median.enumerated().compactMap { index, value -> (minute: Int, value: Double)? in
            guard value > 0 else { return nil }
            return (minute: AnalyticsInstance.curveStartMinutes + index * 5, value: UnitSettingsStore.shared.convertMgdlToDisplay(Double(value)))
        }
    }

    var body: some View {
        Chart {
            RectangleMark(
                xStart: .value("Start", AnalyticsInstance.curveStartMinutes),
                xEnd: .value("End", AnalyticsInstance.curveEndMinutes),
                yStart: .value("Low", UnitSettingsStore.shared.convertMgdlToDisplay(lowLine)),
                yEnd: .value("High", UnitSettingsStore.shared.convertMgdlToDisplay(highLine))
            )
            .foregroundStyle(Color.green.opacity(0.1))

            ForEach(points) { point in
                LineMark(x: .value("Minutes", point.minute), y: .value("BG", point.value), series: .value("Time", point.series))
                    .foregroundStyle(point.flagged ? tint.opacity(0.35) : Color.secondary.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(Array(typical.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Minutes", point.minute), y: .value("BG", point.value), series: .value("Time", "typical"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            RuleMark(x: .value("Start", 0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.6))
        }
        .chartXScale(domain: AnalyticsInstance.curveStartMinutes ... AnalyticsInstance.curveEndMinutes)
        .chartXAxis {
            AxisMarks(values: [0, 60, 120, 180, 240]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minute = value.as(Int.self) { Text(minute == 0 ? "Start" : "\(minute / 60)h") }
                }
            }
        }
        .chartLegend(.hidden)
    }
}
