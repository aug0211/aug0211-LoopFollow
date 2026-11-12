// LoopFollow
// AnalyticsEngineTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct AnalyticsEngineTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// A Monday at midnight UTC.
    private let base = Date(timeIntervalSince1970: 1_798_934_400)

    private func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3600) }

    /// Readings every 5 minutes from `from` to `to` (hours after base), BG from `value(minutesFromStart)`.
    private func readings(from: Double, to: Double, _ value: (Double) -> Int) -> [AnalyticsReading] {
        stride(from: from * 60, to: to * 60, by: 5).map { minute in
            AnalyticsReading(date: base.addingTimeInterval(minute * 60), sgv: value(minute - from * 60))
        }
    }

    private func dataset(
        days: Double,
        readings: [AnalyticsReading],
        carbs: [AnalyticsCarb] = [],
        doses: [AnalyticsDose] = [],
        temps: [AnalyticsTempBasal] = [],
        overrides: [AnalyticsOverride] = [],
        basal: Double = 1,
        carbRatio: Double = 10
    ) -> AnalyticsDataset {
        AnalyticsDataset(
            start: base, end: at(days * 24), readings: readings, carbs: carbs, doses: doses, tempBasals: temps,
            overrides: overrides, siteChanges: [],
            profiles: [AnalyticsProfile(
                start: base.addingTimeInterval(-86400),
                basal: AnalyticsSchedule(entries: [.init(seconds: 0, value: basal)]),
                carbRatio: AnalyticsSchedule(entries: [.init(seconds: 0, value: carbRatio)])
            )],
            timeZone: utc
        )
    }

    @Test("A low needs 2 readings under the line; lows within 30 minutes merge")
    func lowDetection() {
        let values = [100, 65, 100, 64, 62, 90, 66, 63, 85, 120]
        let list = values.enumerated().map { AnalyticsReading(date: at(Double($0.offset) * 5 / 60), sgv: $0.element) }
        let lows = AnalyticsEngine.Context.findLows(list, lowLine: 70)
        #expect(lows.count == 1) // the single 65 doesn't count; the two later dips merge
        #expect(lows.first?.nadir == 62)
    }

    @Test("Delivered insulin counts temp basals, scheduled basal where none ran, and every dose")
    func deliveredInsulin() {
        let data = dataset(
            days: 1, readings: [],
            doses: [AnalyticsDose(date: at(0.5), units: 0.2, isAutomatic: true)],
            temps: [AnalyticsTempBasal(start: at(0), minutes: 30, rate: 0)]
        )
        let context = AnalyticsEngine.Context(data: data, lowLine: 70, highLine: 180)
        #expect(abs(context.scheduledBasal(from: at(0), to: at(1)) - 1) < 0.001)
        // 30 min at 0 U/h, 30 min scheduled 1 U/h, plus a 0.2 U SMB.
        #expect(abs(context.delivered(from: at(0), to: at(1)) - 0.7) < 0.001)
    }

    @Test("An override started for a low isn't blamed for that low, only for a new one after recovery")
    func overrideNewLows() {
        // Six "Post Low" uses a day apart, each starting at a low that recovers to 110.
        var list: [AnalyticsReading] = []
        var overrides: [AnalyticsOverride] = []
        for day in 0 ..< 6 {
            let start = Double(day) * 24 + 12
            overrides.append(AnalyticsOverride(start: at(start), end: at(start + 1), name: "Post Low"))
            // Minutes count from an hour before the override.
            list += readings(from: start - 1, to: start + 4) { minute in
                if minute < 60 { return 110 }
                if minute < 75 { return 62 } // the low the override was started for
                if day < 5, minute >= 150, minute < 170 { return 58 } // a new low on 5 of 6 days
                return 110
            }
        }
        // Each override starts with its low (an hour into that day's readings).
        let report = AnalyticsEngine.analyze(dataset(days: 7, readings: list, overrides: overrides), lowLine: 70, highLine: 180)
        let finding = report.findings.first { $0.kind == .overrideLows }
        #expect(finding?.count == 5)
        #expect(finding?.total == 6)
        #expect(report.overrides.first?.newLows == 5)
    }

    @Test("Meal factors count overrides set up to 3h after the meal, never ones started because of a low")
    func mealFactorsExcludeConsequences() {
        var list: [AnalyticsReading] = []
        var carbs: [AnalyticsCarb] = []
        var overrides: [AnalyticsOverride] = []
        for day in 0 ..< 8 {
            let dinner = Double(day) * 24 + 18
            carbs.append(AnalyticsCarb(date: at(dinner), carbs: 60, fat: 25, protein: 30, isFPUChild: false))
            let withFPU = day % 2 == 0 && day < 6 // High FPU on 3 of 8 dinners
            if withFPU {
                // Set 2 hours in, as a slow fatty meal starts to rise: still part of the meal.
                overrides.append(AnalyticsOverride(start: at(dinner + 2), end: at(dinner + 5), name: "High FPU"))
            }
            let lowAt = 120.0 // minutes after dinner
            if !withFPU {
                // A Post Low started after the low: a consequence, not a cause.
                overrides.append(AnalyticsOverride(start: at(dinner + lowAt / 60 + 0.25), end: at(dinner + 3.5), name: "Post Low"))
            }
            list += readings(from: dinner - 0.5, to: dinner + 5) { minute in
                if !withFPU, minute >= 30 + lowAt, minute < 30 + lowAt + 20 { return 60 }
                return 130
            }
        }
        let report = AnalyticsEngine.analyze(dataset(days: 8, readings: list, carbs: carbs, overrides: overrides), lowLine: 70, highLine: 180)
        let finding = report.findings.first { $0.kind == .mealLows }
        #expect(finding?.count == 5)
        #expect(finding?.comparisons.contains { $0.hasPrefix("With High FPU: 0 of 3") } == true)
        #expect(finding?.comparisons.contains { $0.contains("Post Low") } == false)
    }

    @Test("A finding needs the pattern in at least 60% and at least 5 instances")
    func patternBar() {
        #expect(AnalyticsEngine.isPattern(5, of: 8))
        #expect(!AnalyticsEngine.isPattern(4, of: 8)) // half isn't a pattern
        #expect(!AnalyticsEngine.isPattern(4, of: 5)) // too few
        #expect(!AnalyticsEngine.isPattern(14, of: 31))
    }

    @Test("A factor is reported only with 3+ in each group and a clear gap")
    func factorRules() {
        let rows = [true, true, true, false, false, false]
        let outcome: (Bool) -> Bool = { $0 }
        #expect(AnalyticsEngine.compare(rows, outcome, "X") { $0 }?.text == "X: 3 of 3. Otherwise: 0 of 3.")
        #expect(AnalyticsEngine.compare([true, true, false, false], outcome, "X") { $0 } == nil) // groups too small
        let mixed = [true, false, true, false, true, false, true, false]
        #expect(AnalyticsEngine.compare(mixed, { _ in true }, "X") { $0 } == nil) // no difference
    }

    @Test("A fast drop and quick recovery with no carbs is treated as sensor compression")
    func compression() {
        let values = [120, 118, 116, 85, 55, 54, 90, 115, 118, 120]
        let list = values.enumerated().map { AnalyticsReading(date: at(3 + Double($0.offset) * 5 / 60), sgv: $0.element) }
        let context = AnalyticsEngine.Context(data: dataset(days: 1, readings: list), lowLine: 70, highLine: 180)
        let low = try? #require(context.lows.first)
        #expect(low.map(context.isCompressionLike) == true)
    }

    @Test("Hour labels")
    func hourText() {
        #expect(AnalyticsEngine.hourText(0) == "12 AM")
        #expect(AnalyticsEngine.hourText(6) == "6 AM")
        #expect(AnalyticsEngine.hourText(13) == "1 PM")
    }
}

struct AnalyticsSettingsTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let base = Date(timeIntervalSince1970: 1_798_934_400)
    private func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3600) }

    private func profile(_ hours: Double, basal: [(Int, Double)], carbRatio: Double = 10) -> AnalyticsProfile {
        AnalyticsProfile(
            start: at(hours),
            basal: AnalyticsSchedule(entries: basal.map { .init(seconds: $0.0 * 3600, value: $0.1) }),
            carbRatio: AnalyticsSchedule(entries: [.init(seconds: 0, value: carbRatio)])
        )
    }

    @Test("Changes, returns to an earlier value, and merged time-of-day slots")
    func slots() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let timeline = [
            profile(-24, basal: [(0, 1.0), (6, 0.5)]),
            profile(10, basal: [(0, 1.2), (6, 0.5)]),
            profile(30, basal: [(0, 1.0), (3, 1.0), (6, 0.5)]), // back within 3 days; a new boundary with the same values
            profile(300, basal: [(0, 0.8), (3, 0.8), (6, 0.6)]),
        ]
        let slots = AnalyticsSettingsEngine.slotsFor(.basal, timeline: timeline, periodStart: base, calendar: calendar)
        let night = slots.first { $0.label == "12 AM–6 AM" }
        #expect(night?.changes == 3) // 1.0 → 1.2 → 1.0 → 0.8 (12–3 and 3–6 merged)
        #expect(night?.returns == 1)
        #expect(night?.quickReturns == 1)
        #expect(slots.first { $0.label == "6 AM–12 AM" }?.changes == 1)
    }

    @Test("Saves within 2 hours are one sitting; steady stretches need 5 days at one value")
    func sittingsAndStretches() {
        var readings: [AnalyticsReading] = []
        for minute in stride(from: 0.0, to: 21 * 24 * 60, by: 5) {
            let date = base.addingTimeInterval(minute * 60)
            let day = Int(minute / 1440)
            readings.append(AnalyticsReading(date: date, sgv: day < 10 ? 120 : (Int(minute) % 120 < 30 ? 60 : 120)))
        }
        let data = AnalyticsDataset(
            start: base, end: at(21 * 24), readings: readings, carbs: [], doses: [], tempBasals: [], overrides: [], siteChanges: [],
            profiles: [
                profile(-48, basal: [(0, 1.0)]),
                profile(10 * 24, basal: [(0, 0.9)]),
                profile(10 * 24 + 1, basal: [(0, 0.8)]), // same sitting
            ],
            timeZone: utc
        )
        let history = AnalyticsEngine.analyze(data, lowLine: 70, highLine: 180).settings
        #expect(history?.saves == 2)
        #expect(history?.sittings == 1)
        let overnight = history?.steady.first { $0.kind == .basal && $0.block.hasPrefix("Overnight") }
        #expect(overnight?.stretches.map(\.value) == [1.0, 0.8])
        #expect(overnight?.stretches.first?.best == true) // no lows at 1.0
    }
}
