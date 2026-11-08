// LoopFollow
// MealInsights.swift

import Foundation

/// How BG went in the 4 hours after eating started.
struct MealOutcome: Codable, Equatable {
    static let window: TimeInterval = 4 * 3600
    /// Readings needed (about 2 of the 4 hours) for an outcome to count.
    static let minimumReadings = 24

    let startBG: Int
    let peakBG: Int
    let minutesToPeak: Int
    let lowestBG: Int
    let hadLow: Bool
    /// Minutes above the high line.
    let minutesAboveRange: Int
    /// All insulin delivered from 30 minutes before the meal to 4 hours after eating
    /// started (boluses and SMBs), including any for other food in that time.
    let insulin: Double
    /// False when there were too few readings; such meals are left out of insights.
    let hasEnoughData: Bool
    /// True when another meal was entered in the same window, so the BG and insulin
    /// aren't this meal's alone. Nil on outcomes worked out before this was checked.
    var overlappedMeal: Bool? = nil
    /// BG every 5 minutes from 10 minutes before eating to 4 hours after
    /// (`curveMinutes`), 0 where there was no reading. Nil on older outcomes.
    var curve: [Int]? = nil

    static let curveMinutes = Array(stride(from: -10, through: 240, by: 5))

    var rise: Int { peakBG - startBG }

    /// Counts toward insights: enough readings and no other meal mixed in.
    var isUsable: Bool { hasEnoughData && overlappedMeal != true }

    /// Works out an outcome from the readings around a meal.
    /// `readings` may be in any order; only those from 10 minutes before eating to 4 hours after are used.
    static func compute(
        readings: [(date: Date, sgv: Int)],
        insulin: Double,
        eatingStart: Date,
        lowLine: Double,
        highLine: Double,
        overlappedMeal: Bool = false
    ) -> MealOutcome {
        let start = eatingStart
        let end = eatingStart.addingTimeInterval(window)
        let sorted = readings
            .filter { $0.sgv > 0 && $0.date >= start.addingTimeInterval(-600) && $0.date <= end }
            .sorted { $0.date < $1.date }
        let after = sorted.filter { $0.date >= start }
        let curve = curveMinutes.map { minute -> Int in
            let time = start.addingTimeInterval(Double(minute) * 60)
            guard let nearest = sorted.min(by: { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }),
                  abs(nearest.date.timeIntervalSince(time)) <= 240
            else { return 0 }
            return nearest.sgv
        }

        guard let startReading = sorted.min(by: { abs($0.date.timeIntervalSince(start)) < abs($1.date.timeIntervalSince(start)) }),
              let peak = after.max(by: { $0.sgv < $1.sgv }),
              let lowest = after.min(by: { $0.sgv < $1.sgv })
        else {
            return MealOutcome(startBG: 0, peakBG: 0, minutesToPeak: 0, lowestBG: 0, hadLow: false,
                               minutesAboveRange: 0, insulin: insulin, hasEnoughData: false,
                               overlappedMeal: overlappedMeal, curve: curve)
        }

        // Each reading stands for the time until the next one (at most 10 minutes).
        var minutesAbove = 0.0
        for (index, reading) in after.enumerated() where Double(reading.sgv) > highLine {
            let next = index + 1 < after.count ? after[index + 1].date : reading.date.addingTimeInterval(300)
            minutesAbove += min(next.timeIntervalSince(reading.date), 600) / 60
        }

        return MealOutcome(
            startBG: startReading.sgv,
            peakBG: peak.sgv,
            minutesToPeak: max(0, Int((peak.date.timeIntervalSince(start) / 60).rounded())),
            lowestBG: lowest.sgv,
            hadLow: Double(lowest.sgv) < lowLine,
            minutesAboveRange: Int(minutesAbove.rounded()),
            insulin: insulin,
            hasEnoughData: after.count >= minimumReadings,
            overlappedMeal: overlappedMeal,
            curve: curve
        )
    }

    /// Whether Nightscout `treatments` include a carb entry for another meal between
    /// `from` and `to`. Skips this meal's own entry (by Trio meal ID, else carbs within
    /// 10 minutes of its time) and Trio's fat/protein follow-on entries.
    static func hasOtherMeal(
        in treatments: [[String: Any]],
        trioMealID: String?,
        mealTime: Date,
        carbs: Int,
        from: Date,
        to: Date
    ) -> Bool {
        treatments.contains { treatment in
            guard let amount = (treatment["carbs"] as? NSNumber)?.doubleValue, amount > 0,
                  let date = parseDate(treatment["created_at"] as? String),
                  date >= from, date <= to
            else { return false }
            let id = treatment["id"] as? String
            if let id, let fpuID = treatment["fpuID"] as? String, id == fpuID { return false }
            if let trioMealID, id == trioMealID { return false }
            if abs(date.timeIntervalSince(mealTime)) <= 600, Int(amount.rounded()) == carbs { return false }
            return true
        }
    }

    private static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Summary of a saved meal's history.
struct MealInsights: Equatable {
    static let minimumMeals = 3
    static let minimumPerGroup = 2

    struct PrebolusGroup: Equatable {
        let label: String
        let count: Int
        let medianPeak: Int
        let medianRise: Int
    }

    /// Meals eaten under this name.
    let timesEaten: Int
    /// Meals with a usable outcome (enough readings, no other meal mixed in).
    let measured: Int
    let medianPeak: Int?
    let peakRange: ClosedRange<Int>?
    let medianRise: Int?
    let medianMinutesToPeak: Int?
    let mealsWithLow: Int
    let medianMinutesAboveRange: Int?
    let medianInsulin: Double?
    let prebolusGroups: [PrebolusGroup]
    /// Median peak of the earlier and the later half, once there are 6 or more meals.
    let trend: (earlier: Int, later: Int)?
    /// Median BG at each point of `MealOutcome.curveMinutes`, 0 where unknown.
    var typicalCurve: [Int]? = nil
    /// Things that keep happening with this meal, once there are enough meals.
    var patterns: [MealPattern] = []

    var hasWarning: Bool { patterns.contains { $0.isWarning } }

    var hasSummary: Bool { measured >= Self.minimumMeals }

    static func == (lhs: MealInsights, rhs: MealInsights) -> Bool {
        lhs.timesEaten == rhs.timesEaten && lhs.measured == rhs.measured && lhs.medianPeak == rhs.medianPeak
            && lhs.peakRange == rhs.peakRange && lhs.medianRise == rhs.medianRise
            && lhs.medianMinutesToPeak == rhs.medianMinutesToPeak && lhs.mealsWithLow == rhs.mealsWithLow
            && lhs.medianMinutesAboveRange == rhs.medianMinutesAboveRange && lhs.medianInsulin == rhs.medianInsulin
            && lhs.prebolusGroups == rhs.prebolusGroups
            && lhs.trend?.earlier == rhs.trend?.earlier && lhs.trend?.later == rhs.trend?.later
            && lhs.typicalCurve == rhs.typicalCurve && lhs.patterns == rhs.patterns
    }

    static func summarize(_ occurrences: [MealOccurrence]) -> MealInsights {
        let measuredMeals = occurrences
            .filter { $0.outcome?.isUsable == true }
            .sorted { $0.mealTime < $1.mealTime }
        let outcomes = measuredMeals.compactMap(\.outcome)
        let peaks = outcomes.map(\.peakBG)

        var groups: [PrebolusGroup] = []
        let buckets: [(String, ClosedRange<Int>)] = [
            ("After starting", -60 ... -1),
            ("0–9 min before", 0 ... 9),
            ("10–19 min before", 10 ... 19),
            ("20+ min before", 20 ... 90),
        ]
        for (label, range) in buckets {
            let inGroup = measuredMeals.filter { meal in
                guard let minutes = meal.prebolusMinutes else { return false }
                return range.contains(minutes)
            }.compactMap(\.outcome)
            guard inGroup.count >= minimumPerGroup,
                  let peak = median(inGroup.map(\.peakBG)),
                  let rise = median(inGroup.map(\.rise))
            else { continue }
            groups.append(PrebolusGroup(label: label, count: inGroup.count, medianPeak: peak, medianRise: rise))
        }

        var trend: (earlier: Int, later: Int)?
        if peaks.count >= 6 {
            let half = peaks.count / 2
            if let earlier = median(Array(peaks.prefix(half))), let later = median(Array(peaks.suffix(peaks.count - half))) {
                trend = (earlier, later)
            }
        }

        var insights = MealInsights(
            timesEaten: occurrences.count,
            measured: outcomes.count,
            medianPeak: median(peaks),
            peakRange: peaks.min().flatMap { low in peaks.max().map { low ... $0 } },
            medianRise: median(outcomes.map(\.rise)),
            medianMinutesToPeak: median(outcomes.map(\.minutesToPeak)),
            mealsWithLow: outcomes.filter(\.hadLow).count,
            medianMinutesAboveRange: median(outcomes.map(\.minutesAboveRange)),
            medianInsulin: medianDouble(outcomes.map(\.insulin)),
            prebolusGroups: groups,
            trend: trend
        )
        insights.typicalCurve = medianCurve(outcomes.compactMap(\.curve))
        insights.patterns = MealPattern.find(in: insights, outcomes: outcomes)
        return insights
    }

    /// Point-by-point median of the curves, ignoring gaps (0).
    static func medianCurve(_ curves: [[Int]]) -> [Int]? {
        guard !curves.isEmpty else { return nil }
        let length = curves.map(\.count).max() ?? 0
        return (0 ..< length).map { index in
            median(curves.compactMap { index < $0.count && $0[index] > 0 ? $0[index] : nil }) ?? 0
        }
    }

    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return Int((Double(sorted[middle - 1] + sorted[middle]) / 2).rounded())
    }

    static func medianDouble(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// One-line summary for match lists, e.g. "Eaten 6× · peak ~248 · 1 low".
    var shortSummary: String {
        var parts = ["Eaten \(timesEaten)×"]
        if hasSummary, let medianPeak {
            parts.append("peak ~\(Localizer.toDisplayUnits(String(medianPeak)))")
            parts.append(mealsWithLow == 1 ? "1 low" : "\(mealsWithLow) lows")
        }
        return parts.joined(separator: " · ")
    }
}

/// Something that keeps happening with a meal, worth a look.
struct MealPattern: Equatable {
    enum Kind: String {
        case lows, highs, latePeak, prebolusHelps, rising, falling, variable
    }

    let kind: Kind
    let text: String

    var isWarning: Bool { [.lows, .highs, .rising].contains(kind) }

    var symbol: String {
        switch kind {
        case .lows: return "arrow.down.circle.fill"
        case .highs: return "arrow.up.circle.fill"
        case .latePeak: return "clock.fill"
        case .prebolusHelps: return "timer"
        case .rising: return "chart.line.uptrend.xyaxis"
        case .falling: return "chart.line.downtrend.xyaxis"
        case .variable: return "waveform.path"
        }
    }

    /// Patterns over meals with a usable outcome; needs `MealInsights.minimumMeals`.
    static func find(in insights: MealInsights, outcomes: [MealOutcome]) -> [MealPattern] {
        let count = outcomes.count
        guard count >= MealInsights.minimumMeals else { return [] }
        var patterns: [MealPattern] = []
        func bg(_ value: Int) -> String { Localizer.toDisplayUnits(String(value)) }
        func duration(_ minutes: Int) -> String { minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m" }

        // At least 2 meals and a third of them.
        let lows = outcomes.filter(\.hadLow).count
        if lows >= 2, lows * 3 >= count {
            patterns.append(MealPattern(kind: .lows, text: "Went low after \(lows) of \(count) times"))
        }

        // Two thirds of meals spent 30+ minutes above range.
        let highs = outcomes.filter { $0.minutesAboveRange >= 30 }.count
        if highs * 3 >= count * 2 {
            let typical = insights.medianMinutesAboveRange.map { ", typically \(duration($0)) above" } ?? ""
            patterns.append(MealPattern(kind: .highs, text: "Went above range after \(highs) of \(count) times\(typical)"))
        }

        if let minutes = insights.medianMinutesToPeak, minutes >= 120 {
            patterns.append(MealPattern(kind: .latePeak, text: "Peaks late, typically \(duration(minutes)) after eating"))
        }

        // Best pre-bolus group peaks at least 30 lower than the worst.
        if insights.prebolusGroups.count >= 2,
           let best = insights.prebolusGroups.min(by: { $0.medianPeak < $1.medianPeak }),
           let worst = insights.prebolusGroups.max(by: { $0.medianPeak < $1.medianPeak }),
           worst.medianPeak - best.medianPeak >= 30
        {
            patterns.append(MealPattern(
                kind: .prebolusHelps,
                text: "\(best.label): peak ~\(bg(best.medianPeak)), \(bg(worst.medianPeak - best.medianPeak)) lower than \(worst.label.lowercased())"
            ))
        }

        if let trend = insights.trend {
            let change = trend.later - trend.earlier
            if change >= 30 {
                patterns.append(MealPattern(kind: .rising, text: "Peaks are rising lately (~\(bg(trend.earlier)) → ~\(bg(trend.later)))"))
            } else if change <= -30 {
                patterns.append(MealPattern(kind: .falling, text: "Peaks are falling lately (~\(bg(trend.earlier)) → ~\(bg(trend.later)))"))
            }
        }

        if let range = insights.peakRange, range.upperBound - range.lowerBound >= 100 {
            patterns.append(MealPattern(kind: .variable, text: "Varies a lot: peaks from \(bg(range.lowerBound)) to \(bg(range.upperBound))"))
        }
        return patterns
    }
}
