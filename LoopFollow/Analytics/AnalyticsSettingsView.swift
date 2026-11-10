// LoopFollow
// AnalyticsSettingsView.swift

import Charts
import SwiftUI

/// Settings history: how often and when settings were edited, whether edits were
/// followed by better BG than ordinary times, each setting's values over the
/// period, and how BG went during steady stretches at each value.
struct AnalyticsSettingsSection: View {
    let history: AnalyticsSettingsHistory

    @State private var trackKind: AnalyticsSettingsHistory.Kind = .basal

    var body: some View {
        VStack(spacing: 12) {
            editingCard
            if let beforeAfter = history.beforeAfter {
                beforeAfterCard(beforeAfter)
            }
            if !history.tracks.isEmpty {
                tracksCard
            }
            if !history.steady.isEmpty {
                steadyCard
            }
        }
        .padding(.horizontal)
    }

    // MARK: Editing

    private var editingCard: some View {
        SettingsCard(title: "Editing", subtitle: "Saves within 2 hours of each other count as one sitting") {
            HStack(spacing: 10) {
                SettingsStat(value: "\(history.saves)", label: "saves")
                SettingsStat(value: "\(history.sittings)", label: "sittings")
                SettingsStat(value: AnalyticsEngine.percent(history.reversalShare), label: "reversed the change before")
            }
            Chart {
                ForEach(Array(history.sittingsByHour.enumerated()), id: \.offset) { hour, count in
                    BarMark(x: .value("Hour", hour), y: .value("Sittings", count))
                        .foregroundStyle(Color.purple.gradient)
                        .cornerRadius(2)
                }
            }
            .chartXScale(domain: 0 ... 23)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) { Text(AnalyticsEngine.hourText(hour)) }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 70)
            Text(reversalText)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reversalText: String {
        let busiest = history.sittingsByHour.enumerated().max { $0.element < $1.element }?.offset
        var text = busiest.map { "Most sittings start around \(AnalyticsEngine.hourText($0)). " } ?? ""
        if history.reversalShare >= 0.4 {
            text += "Many changes undo the direction of the one before, which can mean chasing day-to-day variation the loop would absorb anyway."
        } else {
            text += "Most changes keep going in the same direction as the one before."
        }
        return text
    }

    // MARK: Before and after

    private func beforeAfterCard(_ value: AnalyticsSettingsHistory.BeforeAfter) -> some View {
        let editChange = value.editAfter - value.editBefore
        let baseChange = value.baselineAfter - value.baselineBefore
        let difference = editChange - baseChange
        let verdict: String
        if abs(difference) < 0.02 {
            verdict = "No clear effect: the 48 hours after an edit look about like any other 48 hours."
        } else if difference > 0 {
            verdict = "Time in range was \(points(difference)) better after edits than at ordinary times. Edits also tend to follow worse stretches, which recover on their own, so part of this would have happened anyway."
        } else {
            verdict = "Time in range was \(points(-difference)) worse after edits than at ordinary times."
        }
        return SettingsCard(title: "Before and after edits", subtitle: "Time in range in the 48 hours before and after each sitting, against the same at ordinary times") {
            Chart {
                ForEach([("After an edit", value.editBefore, value.editAfter), ("Ordinary times", value.baselineBefore, value.baselineAfter)], id: \.0) { group in
                    BarMark(x: .value("When", group.0), y: .value("TIR", group.1 * 100))
                        .foregroundStyle(by: .value("Window", "48h before"))
                        .position(by: .value("Window", "48h before"))
                        .cornerRadius(4)
                    BarMark(x: .value("When", group.0), y: .value("TIR", group.2 * 100))
                        .foregroundStyle(by: .value("Window", "48h after"))
                        .position(by: .value("Window", "48h after"))
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            Text(AnalyticsEngine.percent(group.2))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                }
            }
            .chartForegroundStyleScale(["48h before": Color.gray.opacity(0.5), "48h after": Color.purple])
            .chartYScale(domain: max(0, min(value.editBefore, value.baselineBefore, value.editAfter, value.baselineAfter) * 100 - 10) ... 100)
            .frame(height: 150)
            Text("\(verdict) Followed by better time in range after \(value.improved) of \(value.total) sittings.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func points(_ value: Double) -> String {
        "\(String(format: "%.1f", value * 100)) points"
    }

    // MARK: Tracks

    private var selectedTrack: AnalyticsSettingsHistory.Track? {
        history.tracks.first { $0.kind == trackKind } ?? history.tracks.first
    }

    private var tracksCard: some View {
        SettingsCard(title: "Values over time", subtitle: "Each line is a time of day; the most-changed are shown") {
            Picker("Setting", selection: $trackKind) {
                ForEach(history.tracks) { track in
                    Text(track.kind.title).tag(track.kind)
                }
            }
            .pickerStyle(.segmented)

            if let track = selectedTrack {
                let slots = Array(track.slots.prefix(5))
                Chart {
                    ForEach(slots) { slot in
                        ForEach(stepPoints(slot)) { point in
                            LineMark(x: .value("Date", point.date), y: .value(track.kind.title, point.value), series: .value("Time", slot.label))
                                .foregroundStyle(by: .value("Time", slot.label))
                                .interpolationMethod(.stepEnd)
                                .lineStyle(StrokeStyle(lineWidth: 2.2))
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 190)

                VStack(spacing: 0) {
                    ForEach(slots) { slot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.label).font(.subheadline)
                                Text("\(slot.changes) changes" + (slot.returns > 0 ? " · back to an earlier value \(slot.returns)×" + (slot.quickReturns > 0 ? " (\(slot.quickReturns) within 3 days)" : "") : ""))
                                    .font(.caption)
                                    .foregroundColor(slot.returns >= 3 ? .orange : .secondary)
                            }
                            Spacer()
                            if let first = slot.points.first, let last = slot.points.last {
                                Text("\(format(first.value)) → \(format(last.value)) \(track.kind.unit)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        if slot.id != slots.last?.id { Divider() }
                    }
                }
            }

            if history.weekly.count >= 2 {
                Text("Weekly time in range")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                Chart(history.weekly) { week in
                    AreaMark(x: .value("Week", week.start), y: .value("TIR", week.timeInRange * 100))
                        .foregroundStyle(LinearGradient(colors: [Color.green.opacity(0.35), Color.green.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Week", week.start), y: .value("TIR", week.timeInRange * 100))
                        .foregroundStyle(Color.green)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Week", week.start), y: .value("TIR", week.timeInRange * 100))
                        .foregroundStyle(Color.green)
                        .annotation(position: .top) {
                            Text(AnalyticsEngine.percent(week.timeInRange))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                }
                .chartYScale(domain: max(0, (history.weekly.map(\.timeInRange).min() ?? 0) * 100 - 10) ... 100)
                .chartYAxis(.hidden)
                .frame(height: 80)
            }
        }
    }

    /// Points for a step line: each value, plus "now" so the last value reaches the end.
    private func stepPoints(_ slot: AnalyticsSettingsHistory.Slot) -> [AnalyticsSettingsHistory.Point] {
        guard let last = slot.points.last else { return [] }
        return slot.points + [.init(date: max(Date(), last.date.addingTimeInterval(60)), value: last.value)]
    }

    /// "1.2", "0.65", "16".
    private func format(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: Steady stretches

    private var steadyCard: some View {
        SettingsCard(title: "Steady stretches", subtitle: "5+ days at one value for that part of the day, and how BG went in those hours") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(history.steady) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(group.block) · \(group.kind.title)")
                            .font(.subheadline.weight(.semibold))
                        ForEach(group.stretches) { stretch in
                            StretchRow(stretch: stretch, unit: group.kind.unit, format: format)
                        }
                    }
                }
                Label {
                    Text("Settings were often changed because of how BG had been going, and school, activity or illness change things too. Treat the best stretch as a lead to discuss, not proof that value is right.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct StretchRow: View {
    let stretch: AnalyticsSettingsHistory.Stretch
    let unit: String
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("\(format(stretch.value)) \(unit)")
                        .font(.subheadline.monospacedDigit().weight(stretch.best ? .bold : .regular))
                    if stretch.best {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .accessibilityLabel("Best time in range")
                    }
                }
                Text("\(stretch.days) days from \(stretch.start.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 118, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(stretch.best ? Color.green.gradient : Color.green.opacity(0.55).gradient)
                        .frame(width: geometry.size.width * stretch.timeInRange)
                }
            }
            .frame(height: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(AnalyticsEngine.percent(stretch.timeInRange))
                    .font(.caption.weight(.semibold).monospacedDigit())
                Text("\(String(format: "%.1f", stretch.low * 100))% low")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(stretch.low >= 0.04 ? .red : .secondary)
            }
            .frame(width: 58, alignment: .trailing)
        }
    }
}

private struct SettingsStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.purple.opacity(0.08)))
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundColor(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
