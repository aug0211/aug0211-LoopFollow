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
    /// Insulin delivered from 30 minutes before the meal to 4 hours after eating started (boluses and SMBs).
    let insulin: Double
    /// False when there were too few readings; such meals are left out of insights.
    let hasEnoughData: Bool

    var rise: Int { peakBG - startBG }

    /// Works out an outcome from the readings around a meal.
    /// `readings` may be in any order; only those from 10 minutes before eating to 4 hours after are used.
    static func compute(
        readings: [(date: Date, sgv: Int)],
        insulin: Double,
        eatingStart: Date,
        lowLine: Double,
        highLine: Double
    ) -> MealOutcome {
        let start = eatingStart
        let end = eatingStart.addingTimeInterval(window)
        let sorted = readings
            .filter { $0.sgv > 0 && $0.date >= start.addingTimeInterval(-600) && $0.date <= end }
            .sorted { $0.date < $1.date }
        let after = sorted.filter { $0.date >= start }

        guard let startReading = sorted.min(by: { abs($0.date.timeIntervalSince(start)) < abs($1.date.timeIntervalSince(start)) }),
              let peak = after.max(by: { $0.sgv < $1.sgv }),
              let lowest = after.min(by: { $0.sgv < $1.sgv })
        else {
            return MealOutcome(startBG: 0, peakBG: 0, minutesToPeak: 0, lowestBG: 0, hadLow: false,
                               minutesAboveRange: 0, insulin: insulin, hasEnoughData: false)
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
            hasEnoughData: after.count >= minimumReadings
        )
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
    /// Meals with a usable outcome.
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

    var hasSummary: Bool { measured >= Self.minimumMeals }

    static func == (lhs: MealInsights, rhs: MealInsights) -> Bool {
        lhs.timesEaten == rhs.timesEaten && lhs.measured == rhs.measured && lhs.medianPeak == rhs.medianPeak
            && lhs.peakRange == rhs.peakRange && lhs.medianRise == rhs.medianRise
            && lhs.medianMinutesToPeak == rhs.medianMinutesToPeak && lhs.mealsWithLow == rhs.mealsWithLow
            && lhs.medianMinutesAboveRange == rhs.medianMinutesAboveRange && lhs.medianInsulin == rhs.medianInsulin
            && lhs.prebolusGroups == rhs.prebolusGroups
            && lhs.trend?.earlier == rhs.trend?.earlier && lhs.trend?.later == rhs.trend?.later
    }

    static func summarize(_ occurrences: [MealOccurrence]) -> MealInsights {
        let measuredMeals = occurrences
            .filter { $0.outcome?.hasEnoughData == true }
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

        return MealInsights(
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
