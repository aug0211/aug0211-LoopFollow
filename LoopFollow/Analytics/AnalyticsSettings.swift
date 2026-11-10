// LoopFollow
// AnalyticsSettings.swift

import Foundation

/// How settings (basal, carb ratio, ISF) were changed over a period, and how BG
/// went with them.
struct AnalyticsSettingsHistory {
    /// Profile saves in the period, and the editing sittings they were made in
    /// (saves within 2 hours of each other).
    let saves: Int
    let sittings: Int
    /// Share of changes that reversed the direction of the change before.
    let reversalShare: Double
    /// Sittings by hour of day they started (24 values).
    let sittingsByHour: [Int]
    let beforeAfter: BeforeAfter?
    let tracks: [Track]
    let steady: [SteadyGroup]
    let weekly: [Week]

    /// Time in range in the 48 hours before and after each sitting, against the
    /// same at times spread evenly through the period.
    struct BeforeAfter {
        let editBefore: Double
        let editAfter: Double
        let baselineBefore: Double
        let baselineAfter: Double
        let improved: Int
        let total: Int
    }

    enum Kind: String, CaseIterable {
        case basal, carbRatio, sensitivity

        var title: String {
            switch self {
            case .basal: return "Basal"
            case .carbRatio: return "Carb ratio"
            case .sensitivity: return "ISF"
            }
        }

        var unit: String {
            switch self {
            case .basal: return "U/h"
            case .carbRatio: return "g/U"
            case .sensitivity: return "mg/dL/U"
            }
        }
    }

    /// One setting's values over the period, by time-of-day slot.
    struct Track: Identifiable {
        var id: String { kind.rawValue }
        let kind: Kind
        let slots: [Slot]
    }

    struct Slot: Identifiable {
        var id: String { label }
        /// "9 AM–2 PM".
        let label: String
        let points: [Point]
        let changes: Int
        /// Changes that went back to the value before the previous change.
        let returns: Int
        /// Of those, within 3 days.
        let quickReturns: Int
    }

    struct Point: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    /// Stretches of 5+ days where a setting stayed the same for a part of the day,
    /// with how BG went in those hours.
    struct SteadyGroup: Identifiable {
        var id: String { block + kind.rawValue }
        let block: String
        let kind: Kind
        let stretches: [Stretch]
    }

    struct Stretch: Identifiable {
        var id: Date { start }
        let start: Date
        let days: Int
        let value: Double
        let timeInRange: Double
        let low: Double
        let high: Double
        var best = false
    }

    struct Week: Identifiable {
        var id: Date { start }
        let start: Date
        let timeInRange: Double
        let low: Double
    }
}

enum AnalyticsSettingsEngine {
    static let sittingGap: TimeInterval = 2 * 3600
    static let steadyDays = 5
    static let blocks: [(label: String, from: Int, to: Int)] = [
        ("Overnight 12–7 AM", 0, 7), ("Morning 7–11 AM", 7, 11), ("Midday 11 AM–3 PM", 11, 15),
        ("Afternoon 3–6 PM", 15, 18), ("Evening 6 PM–12 AM", 18, 24),
    ]

    static func analyze(_ c: AnalyticsEngine.Context) -> AnalyticsSettingsHistory? {
        let data = c.data
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = data.timeZone

        // Distinct versions: a save that changes nothing isn't a change.
        var versions: [AnalyticsProfile] = []
        for profile in data.profiles {
            if let last = versions.last, last.basal == profile.basal, last.carbRatio == profile.carbRatio, last.sensitivity == profile.sensitivity { continue }
            versions.append(profile)
        }
        let inPeriod = versions.filter { $0.start >= data.start && $0.start <= data.end }
        guard let opening = versions.last(where: { $0.start < data.start }) ?? inPeriod.first else { return nil }

        var sittings: [[Date]] = []
        for version in inPeriod {
            if let last = sittings.last?.last, version.start.timeIntervalSince(last) <= sittingGap {
                sittings[sittings.count - 1].append(version.start)
            } else {
                sittings.append([version.start])
            }
        }
        var byHour = Array(repeating: 0, count: 24)
        for sitting in sittings { if let first = sitting.first { byHour[calendar.component(.hour, from: first)] += 1 } }

        let timeline = [opening] + inPeriod.filter { $0.start > opening.start }
        var flips = 0
        var flipChances = 0
        let tracks: [AnalyticsSettingsHistory.Track] = AnalyticsSettingsHistory.Kind.allCases.compactMap { kind in
            let slots = slotsFor(kind, timeline: timeline, periodStart: data.start, calendar: calendar)
            for slot in slots {
                let values = slot.points.map(\.value)
                let directions = zip(values, values.dropFirst()).map { $1 > $0 }
                flips += zip(directions, directions.dropFirst()).filter { $0 != $1 }.count
                flipChances += max(directions.count - 1, 0)
            }
            return slots.isEmpty ? nil : AnalyticsSettingsHistory.Track(kind: kind, slots: slots)
        }

        return AnalyticsSettingsHistory(
            saves: inPeriod.count,
            sittings: sittings.count,
            reversalShare: flipChances > 0 ? Double(flips) / Double(flipChances) : 0,
            sittingsByHour: byHour,
            beforeAfter: beforeAfter(c, sittings: sittings),
            tracks: tracks,
            steady: steadyStretches(c, calendar: calendar),
            weekly: weekly(c)
        )
    }

    static func schedule(_ kind: AnalyticsSettingsHistory.Kind, _ profile: AnalyticsProfile) -> AnalyticsSchedule {
        switch kind {
        case .basal: return profile.basal
        case .carbRatio: return profile.carbRatio
        case .sensitivity: return profile.sensitivity
        }
    }

    /// Value history for each time-of-day boundary any version used, merging
    /// neighbouring boundaries that always had the same values.
    static func slotsFor(_ kind: AnalyticsSettingsHistory.Kind, timeline: [AnalyticsProfile], periodStart: Date, calendar: Calendar) -> [AnalyticsSettingsHistory.Slot] {
        let boundaries = Array(Set(timeline.flatMap { schedule(kind, $0).entries.map(\.seconds) })).sorted()
        guard !boundaries.isEmpty else { return [] }
        let histories: [(seconds: Int, points: [AnalyticsSettingsHistory.Point])] = boundaries.map { seconds in
            var points: [AnalyticsSettingsHistory.Point] = []
            for (index, version) in timeline.enumerated() {
                let value = schedule(kind, version).value(atSecondsFromMidnight: seconds)
                if points.last?.value != value {
                    points.append(.init(date: index == 0 ? periodStart : version.start, value: value))
                }
            }
            return (seconds, points)
        }
        // Merge neighbours with identical histories into one slot.
        var merged: [(from: Int, to: Int, points: [AnalyticsSettingsHistory.Point])] = []
        for (index, history) in histories.enumerated() {
            let end = index + 1 < histories.count ? histories[index + 1].seconds : 86400
            if let last = merged.last, last.points.map(\.value) == history.points.map(\.value) {
                merged[merged.count - 1].to = end
            } else {
                merged.append((history.seconds, end, history.points))
            }
        }
        return merged.compactMap { slot in
            let values = slot.points.map(\.value)
            guard values.count >= 2 else { return nil }
            var returns = 0
            var quick = 0
            if values.count >= 3 {
                for index in 2 ..< values.count where values[index] == values[index - 2] {
                    returns += 1
                    if slot.points[index].date.timeIntervalSince(slot.points[index - 1].date) < 3 * 86400 { quick += 1 }
                }
            }
            return AnalyticsSettingsHistory.Slot(
                label: "\(timeText(slot.from))–\(timeText(slot.to))",
                points: slot.points,
                changes: values.count - 1,
                returns: returns,
                quickReturns: quick
            )
        }
        .sorted { $0.changes > $1.changes }
    }

    /// Time in range between two times, when at least 70% of readings are there.
    private static func timeInRange(_ c: AnalyticsEngine.Context, from: Date, to: Date) -> Double? {
        let readings = c.readings(from: from, to: to)
        let expected = to.timeIntervalSince(from) / 300
        guard expected > 0, Double(readings.count) >= expected * 0.7 else { return nil }
        let inRange = readings.filter { Double($0.sgv) >= c.lowLine && Double($0.sgv) <= c.highLine }.count
        return Double(inRange) / Double(readings.count)
    }

    private static func beforeAfter(_ c: AnalyticsEngine.Context, sittings: [[Date]]) -> AnalyticsSettingsHistory.BeforeAfter? {
        let window: TimeInterval = 48 * 3600
        var before: [Double] = []
        var after: [Double] = []
        for sitting in sittings {
            guard let first = sitting.first, let last = sitting.last,
                  let b = timeInRange(c, from: first.addingTimeInterval(-window), to: first),
                  let a = timeInRange(c, from: last, to: last.addingTimeInterval(window))
            else { continue }
            before.append(b)
            after.append(a)
        }
        guard before.count >= 3 else { return nil }
        // Baseline: the same comparison every 6 hours through the period.
        var baseBefore: [Double] = []
        var baseAfter: [Double] = []
        var cursor = c.data.start.addingTimeInterval(window)
        while cursor.addingTimeInterval(window) <= c.data.end {
            if let b = timeInRange(c, from: cursor.addingTimeInterval(-window), to: cursor),
               let a = timeInRange(c, from: cursor, to: cursor.addingTimeInterval(window))
            {
                baseBefore.append(b)
                baseAfter.append(a)
            }
            cursor = cursor.addingTimeInterval(6 * 3600)
        }
        func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        return .init(
            editBefore: mean(before), editAfter: mean(after),
            baselineBefore: mean(baseBefore), baselineAfter: mean(baseAfter),
            improved: zip(before, after).filter { $1 > $0 }.count, total: before.count
        )
    }

    /// For each part of the day and setting, stretches of 5+ days at one value.
    private static func steadyStretches(_ c: AnalyticsEngine.Context, calendar: Calendar) -> [AnalyticsSettingsHistory.SteadyGroup] {
        var groups: [AnalyticsSettingsHistory.SteadyGroup] = []
        var days: [Date] = []
        var day = calendar.startOfDay(for: c.data.start)
        while day < c.data.end {
            if day >= c.data.start.addingTimeInterval(-3600) { days.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        for block in blocks {
            for kind in AnalyticsSettingsHistory.Kind.allCases {
                // Per day: the block's average setting and its readings.
                var perDay: [(day: Date, value: Double, readings: [AnalyticsReading])] = []
                for day in days {
                    let from = day.addingTimeInterval(Double(block.from) * 3600)
                    let to = day.addingTimeInterval(Double(block.to) * 3600)
                    guard to <= c.data.end else { continue }
                    var samples: [Double] = []
                    var time = from
                    while time < to {
                        if let profile = c.profile(at: time) {
                            samples.append(schedule(kind, profile).value(atSecondsFromMidnight: c.secondsFromMidnight(time)))
                        }
                        time = time.addingTimeInterval(1800)
                    }
                    let readings = Array(c.readings(from: from, to: to))
                    guard !samples.isEmpty, Double(readings.count) >= Double(block.to - block.from) * 12 * 0.7 else { continue }
                    let average = (samples.reduce(0, +) / Double(samples.count) * 100).rounded() / 100
                    perDay.append((day, average, readings))
                }
                // Consecutive days at the same value.
                var stretches: [AnalyticsSettingsHistory.Stretch] = []
                var run: [(day: Date, value: Double, readings: [AnalyticsReading])] = []
                func close() {
                    guard run.count >= steadyDays, let first = run.first else { run = []; return }
                    let all = run.flatMap(\.readings)
                    let count = Double(max(all.count, 1))
                    stretches.append(.init(
                        start: first.day, days: run.count, value: first.value,
                        timeInRange: Double(all.filter { Double($0.sgv) >= c.lowLine && Double($0.sgv) <= c.highLine }.count) / count,
                        low: Double(all.filter { Double($0.sgv) < c.lowLine }.count) / count,
                        high: Double(all.filter { Double($0.sgv) > c.highLine }.count) / count
                    ))
                    run = []
                }
                for entry in perDay {
                    // One day missing (too little CGM data) doesn't end a stretch.
                    if let last = run.last, last.value != entry.value || entry.day.timeIntervalSince(last.day) > 2.5 * 86400 { close() }
                    run.append(entry)
                }
                close()
                guard stretches.count >= 2, Set(stretches.map(\.value)).count >= 2 else { continue }
                if let best = stretches.indices.max(by: { lhs, rhs in
                    let a = stretches[lhs], b = stretches[rhs]
                    return a.timeInRange != b.timeInRange ? a.timeInRange < b.timeInRange : a.low > b.low
                }) {
                    stretches[best].best = true
                }
                groups.append(.init(block: block.label, kind: kind, stretches: stretches))
            }
        }
        return groups
    }

    private static func weekly(_ c: AnalyticsEngine.Context) -> [AnalyticsSettingsHistory.Week] {
        var weeks: [AnalyticsSettingsHistory.Week] = []
        var start = c.data.start
        while start < c.data.end {
            let end = min(start.addingTimeInterval(7 * 86400), c.data.end)
            let readings = c.readings(from: start, to: end)
            if readings.count > 500 {
                let count = Double(readings.count)
                weeks.append(.init(
                    start: start,
                    timeInRange: Double(readings.filter { Double($0.sgv) >= c.lowLine && Double($0.sgv) <= c.highLine }.count) / count,
                    low: Double(readings.filter { Double($0.sgv) < c.lowLine }.count) / count
                ))
            }
            start = end
        }
        return weeks
    }

    static func timeText(_ seconds: Int) -> String {
        let hour = (seconds / 3600) % 24
        let minute = (seconds % 3600) / 60
        let base = AnalyticsEngine.hourText(hour)
        guard minute > 0 else { return base }
        let parts = base.split(separator: " ")
        return "\(parts[0]):\(String(format: "%02d", minute)) \(parts.count > 1 ? String(parts[1]) : "")"
    }
}
