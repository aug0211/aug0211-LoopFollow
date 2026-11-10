// LoopFollow
// NamedMealTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct NamedMealTests {
    private func meal(_ name: String, _ carbs: Int, _ fat: Int, _ protein: Int) -> NamedMeal {
        NamedMeal(id: name, name: name, carbs: carbs, fat: fat, protein: protein, createdAt: Date(), nightscoutID: nil)
    }

    private func occurrence(_ id: String, at date: Date, _ carbs: Int, _ fat: Int, _ protein: Int) -> MealOccurrence {
        MealOccurrence(id: id, sentAt: date, mealTime: date, carbs: carbs, fat: fat, protein: protein)
    }

    @Test("Each of carbs, fat and protein must be within the tolerance")
    func toleranceAppliesToEachMacro() {
        let meals = [meal("Sandwich", 45, 10, 12)]
        #expect(NamedMealMatcher.matches(carbs: 50, fat: 15, protein: 7, in: meals, tolerance: 5).count == 1)
        #expect(NamedMealMatcher.matches(carbs: 51, fat: 10, protein: 12, in: meals, tolerance: 5).isEmpty)
        #expect(NamedMealMatcher.matches(carbs: 45, fat: 10, protein: 18, in: meals, tolerance: 5).isEmpty)
    }

    @Test("A tolerance of 0 matches only identical meals")
    func zeroToleranceIsExact() {
        let meals = [meal("Sandwich", 45, 10, 12)]
        #expect(NamedMealMatcher.matches(carbs: 45, fat: 10, protein: 12, in: meals, tolerance: 0).count == 1)
        #expect(NamedMealMatcher.matches(carbs: 46, fat: 10, protein: 12, in: meals, tolerance: 0).isEmpty)
    }

    @Test("Matches are listed closest first")
    func closestFirst() {
        let meals = [meal("Far", 40, 10, 12), meal("Near", 44, 10, 12), meal("Exact", 45, 10, 12)]
        let names = NamedMealMatcher.matches(carbs: 45, fat: 10, protein: 12, in: meals, tolerance: 5).map(\.name)
        #expect(names == ["Exact", "Near", "Far"])
    }

    @Test("A loop meal entry finds the sent meal within 10 minutes, preferring identical macros")
    func occurrenceLookup() {
        let now = Date()
        let occurrences = [
            occurrence("other", at: now.addingTimeInterval(-60), 30, 0, 0),
            occurrence("sent", at: now.addingTimeInterval(-120), 45, 10, 12),
        ]
        #expect(NamedMealMatcher.occurrence(for: now, carbs: 45, fat: 10, protein: 12, in: occurrences)?.id == "sent")
        // An edited meal (new macros) still finds the closest sent meal in time.
        #expect(NamedMealMatcher.occurrence(for: now, carbs: 50, fat: 10, protein: 12, in: occurrences)?.id == "other")
        #expect(NamedMealMatcher.occurrence(for: now.addingTimeInterval(3600), carbs: 45, fat: 10, protein: 12, in: occurrences) == nil)
    }

    @Test("Pre-bolus accepts empty, before and after, and rejects out-of-range values")
    func prebolusParsing() {
        #expect(NamedMealFormat.parsePrebolus("", negative: false) == .empty)
        #expect(NamedMealFormat.parsePrebolus("13", negative: false) == .minutes(13))
        #expect(NamedMealFormat.parsePrebolus("5", negative: true) == .minutes(-5))
        #expect(NamedMealFormat.parsePrebolus("0", negative: true) == .minutes(0))
        #expect(NamedMealFormat.parsePrebolus("91", negative: false) == .invalid)
        #expect(NamedMealFormat.parsePrebolus("61", negative: true) == .invalid)
        #expect(NamedMealFormat.parsePrebolus("abc", negative: false) == .invalid)
    }

    @Test("A linked Trio meal ID wins over a nearby meal")
    func trioIDLink() {
        let now = Date()
        var linked = occurrence("linked", at: now.addingTimeInterval(-3600), 45, 10, 12)
        linked.trioMealID = "TRIO-1"
        let nearby = occurrence("nearby", at: now, 45, 10, 12)
        #expect(NamedMealMatcher.occurrence(trioMealID: "TRIO-1", for: now, carbs: 45, fat: 10, protein: 12, in: [nearby, linked])?.id == "linked")
        #expect(NamedMealMatcher.occurrence(trioMealID: "TRIO-2", for: now, carbs: 45, fat: 10, protein: 12, in: [nearby, linked])?.id == "nearby")
    }

    private func readings(from start: Date, values: [Int]) -> [(date: Date, sgv: Int)] {
        values.enumerated().map { (start.addingTimeInterval(Double($0.offset) * 300), $0.element) }
    }

    @Test("Outcome: start, peak, time to peak, lows and time above range")
    func outcomeCompute() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        // 37 readings over 3 hours: rises to 250 at 30 min, then falls to 65.
        var values = [100, 120, 150, 180, 200, 230, 250, 240, 220, 200, 190, 185, 170]
        values += Array(repeating: 150, count: 18) + [120, 100, 90, 80, 70, 65]
        let outcome = MealOutcome.compute(
            readings: readings(from: start, values: values),
            insulin: 4.5,
            eatingStart: start,
            lowLine: 70,
            highLine: 180
        )
        #expect(outcome.hasEnoughData)
        #expect(outcome.startBG == 100)
        #expect(outcome.peakBG == 250)
        #expect(outcome.minutesToPeak == 30)
        #expect(outcome.rise == 150)
        #expect(outcome.lowestBG == 65)
        #expect(outcome.hadLow)
        #expect(outcome.minutesAboveRange == 40) // 8 readings above 180 (200 … 185), 5 minutes each
        #expect(outcome.insulin == 4.5)
        #expect(outcome.measuredMinutes == 180)
        #expect(outcome.overlappedMeal == false)
    }

    @Test("The next meal ends the stretch; under 90 minutes is too soon to count")
    func outcomeCutShort() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let values = (0 ..< 37).map { 100 + $0 * 2 }
        func compute(nextMealAfter minutes: Double) -> MealOutcome {
            MealOutcome.compute(readings: readings(from: start, values: values), insulin: 2, eatingStart: start,
                                lowLine: 70, highLine: 180, nextMeal: start.addingTimeInterval(minutes * 60))
        }

        let tooSoon = compute(nextMealAfter: 60)
        #expect(tooSoon.overlappedMeal == true)
        #expect(tooSoon.measuredMinutes == 60)
        #expect(!tooSoon.isUsable)

        let cut = compute(nextMealAfter: 100)
        #expect(cut.isUsable)
        #expect(cut.measuredMinutes == 100)
        #expect(cut.peakBG == 140) // the reading at 100 min; later ones belong to the next meal
        let curve = try #require(cut.curve)
        #expect(curve.last == 0)
    }

    @Test("Outcome needs about 2 hours of readings")
    func outcomeNeedsData() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let outcome = MealOutcome.compute(readings: readings(from: start, values: [100, 150, 200]), insulin: 1, eatingStart: start, lowLine: 70, highLine: 180)
        #expect(!outcome.hasEnoughData)
    }

    private func measured(_ id: String, daysAgo: Double, prebolus: Int?, peak: Int, low: Bool = false) -> MealOccurrence {
        var item = occurrence(id, at: Date().addingTimeInterval(-daysAgo * 86400), 45, 10, 12)
        item.mealID = "meal"
        item.prebolusMinutes = prebolus
        item.outcome = MealOutcome(startBG: 100, peakBG: peak, minutesToPeak: 60, lowestBG: low ? 60 : 90, hadLow: low,
                                   minutesAboveRange: 30, insulin: 4, hasEnoughData: true)
        return item
    }

    @Test("A meal whose next meal came too soon is left out of insights")
    func overlappedMealsExcluded() {
        var overlapped = measured("c", daysAgo: 1, prebolus: 5, peak: 300)
        overlapped.outcome = MealOutcome(startBG: 100, peakBG: 300, minutesToPeak: 40, lowestBG: 90, hadLow: false,
                                         minutesAboveRange: 20, insulin: 4, hasEnoughData: false,
                                         overlappedMeal: true, measuredMinutes: 50)
        let insights = MealInsights.summarize([
            measured("a", daysAgo: 3, prebolus: 5, peak: 200),
            measured("b", daysAgo: 2, prebolus: 5, peak: 210),
            overlapped,
        ])
        #expect(insights.timesEaten == 3)
        #expect(insights.measured == 2)
        #expect(!insights.hasSummary)
    }

    @Test("The next meal is the first real carb entry; this meal, FPU entries and low treatments don't count")
    func nextMealDetection() {
        let mealTime = Date(timeIntervalSince1970: 1_800_000_000)
        let iso = ISO8601DateFormatter()
        func carbs(_ grams: Double, minutes: Double, id: String? = nil, fpuID: String? = nil) -> [String: Any] {
            var entry: [String: Any] = ["carbs": NSNumber(value: grams), "created_at": iso.string(from: mealTime.addingTimeInterval(minutes * 60))]
            if let id { entry["id"] = id }
            if let fpuID { entry["fpuID"] = fpuID }
            return entry
        }
        func next(_ treatments: [[String: Any]], trioID: String? = nil) -> Double? {
            MealOutcome.nextMealStart(in: treatments, trioMealID: trioID, mealTime: mealTime, carbs: 30,
                                      eatingStart: mealTime, to: mealTime.addingTimeInterval(3 * 3600))
                .map { $0.timeIntervalSince(mealTime) / 60 }
        }

        #expect(next([carbs(30, minutes: 1)]) == nil) // this meal, matched by carbs and time
        #expect(next([carbs(30, minutes: 0, id: "T1")], trioID: "T1") == nil) // this meal, by Trio ID
        #expect(next([carbs(21, minutes: 90, id: "F", fpuID: "F")]) == nil) // fat/protein follow-on
        #expect(next([carbs(4, minutes: 70)]) == nil) // low treatment
        #expect(next([["insulin": NSNumber(value: 2), "created_at": iso.string(from: mealTime)]]) == nil) // bolus only
        #expect(next([carbs(45, minutes: 120), carbs(60, minutes: 75)]) == 75) // the first one
        #expect(next([carbs(45, minutes: -20)]) == nil) // before this meal
        #expect(next([carbs(45, minutes: 4 * 60)]) == nil) // after the stretch
    }

    @Test("Insulin counts only up to the end of the stretch")
    func insulinWindow() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let iso = ISO8601DateFormatter()
        let treatments: [[String: Any]] = [
            ["insulin": NSNumber(value: 3), "created_at": iso.string(from: start)],
            ["insulin": NSNumber(value: 0.5), "created_at": iso.string(from: start.addingTimeInterval(3600))],
            ["insulin": NSNumber(value: 5), "created_at": iso.string(from: start.addingTimeInterval(2 * 3600))],
        ]
        #expect(MealOutcome.insulin(in: treatments, from: start.addingTimeInterval(-1800), to: start.addingTimeInterval(90 * 60)) == 3.5)
    }

    @Test("Outcome keeps a 5-minute BG curve with gaps where readings are missing")
    func outcomeCurve() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let values = (0 ..< 37).map { 100 + $0 }
        let outcome = MealOutcome.compute(readings: readings(from: start, values: values), insulin: 1, eatingStart: start, lowLine: 70, highLine: 180)
        let curve = try #require(outcome.curve)
        #expect(curve.count == MealOutcome.curveMinutes.count)
        #expect(curve[0] == 0) // 10 minutes before eating: no reading
        #expect(curve[MealOutcome.curveMinutes.firstIndex(of: 0)!] == 100)
        #expect(curve.last == 136) // 3 hours after eating
    }

    @Test("Typical curve is the point-by-point median, ignoring gaps")
    func typicalCurve() {
        #expect(MealInsights.medianCurve([[100, 0, 200], [120, 150, 0], [110, 0, 220]]) == [110, 150, 210])
        #expect(MealInsights.medianCurve([]) == nil)
    }

    private func outcome(peak: Int, low: Bool = false, above: Int = 0, toPeak: Int = 60) -> MealOutcome {
        MealOutcome(startBG: 100, peakBG: peak, minutesToPeak: toPeak, lowestBG: low ? 55 : 90, hadLow: low,
                    minutesAboveRange: above, insulin: 3, hasEnoughData: true, overlappedMeal: false)
    }

    private func patterns(_ outcomes: [MealOutcome], prebolus: [Int?]? = nil) -> Set<MealPattern.Kind> {
        let meals = outcomes.enumerated().map { index, outcome -> MealOccurrence in
            var item = occurrence("p\(index)", at: Date().addingTimeInterval(Double(index - outcomes.count) * 86400), 45, 10, 12)
            item.mealID = "meal"
            item.prebolusMinutes = prebolus?[index]
            item.outcome = outcome
            return item
        }
        return Set(MealInsights.summarize(meals).patterns.map(\.kind))
    }

    @Test("Patterns: repeated lows, repeated highs, late peaks")
    func patternBasics() {
        #expect(patterns([outcome(peak: 150), outcome(peak: 160)]).isEmpty) // too few meals
        #expect(patterns([outcome(peak: 150, low: true), outcome(peak: 160, low: true), outcome(peak: 150)]) == [.lows])
        #expect(patterns([outcome(peak: 230, above: 60), outcome(peak: 240, above: 45), outcome(peak: 170)]) == [.highs])
        #expect(patterns([outcome(peak: 170, toPeak: 150), outcome(peak: 170, toPeak: 130), outcome(peak: 170, toPeak: 140)]) == [.latePeak])
    }

    @Test("Patterns: pre-bolus difference and rising peaks")
    func patternComparisons() {
        let prebolus = patterns(
            [outcome(peak: 220), outcome(peak: 230), outcome(peak: 170), outcome(peak: 180)],
            prebolus: [2, 4, 15, 18]
        )
        #expect(prebolus.contains(.prebolusHelps))

        let rising = patterns([150, 150, 150, 200, 210, 200].map { outcome(peak: $0) })
        #expect(rising.contains(.rising))
    }

    @Test("Insights need 3 measured meals and group pre-bolus times")
    func insightsSummary() {
        let two = MealInsights.summarize([measured("a", daysAgo: 2, prebolus: 5, peak: 250), measured("b", daysAgo: 1, prebolus: 6, peak: 230)])
        #expect(!two.hasSummary)

        let meals = [
            measured("a", daysAgo: 6, prebolus: 5, peak: 260),
            measured("b", daysAgo: 5, prebolus: 8, peak: 250, low: true),
            measured("c", daysAgo: 4, prebolus: 15, peak: 210),
            measured("d", daysAgo: 3, prebolus: 18, peak: 200),
            measured("e", daysAgo: 2, prebolus: -5, peak: 280),
            measured("f", daysAgo: 1, prebolus: nil, peak: 190),
        ]
        let insights = MealInsights.summarize(meals)
        #expect(insights.hasSummary)
        #expect(insights.measured == 6)
        #expect(insights.medianPeak == 230)
        #expect(insights.peakRange == 190 ... 280)
        #expect(insights.mealsWithLow == 1)
        #expect(insights.prebolusGroups.map(\.label) == ["0–9 min before", "10–19 min before"])
        #expect(insights.prebolusGroups.first?.medianPeak == 255)
        #expect(insights.trend?.earlier == 250)
        #expect(insights.trend?.later == 200)
    }

    @Test("Search ranks name start, word start, contains, letters in order, then typos")
    func searchRanking() {
        #expect(NamedMealSearch.score("piz", name: "Pizza") == 5)
        #expect(NamedMealSearch.score("pro", name: "Vanilla Protein") == 4)
        #expect(NamedMealSearch.score("nill", name: "Vanilla Protein") == 3)
        #expect(NamedMealSearch.score("vprot", name: "Vanilla Protein") == 2)
        #expect(NamedMealSearch.score("vanulla prot", name: "Vanilla Protein") == 1)
        #expect(NamedMealSearch.score("PIZZA", name: "pizza") == 5)
        #expect(NamedMealSearch.score("creme", name: "Crème brûlée") == 5)
        #expect(NamedMealSearch.score("taco", name: "Pizza") == nil)
    }

    @Test("Search ties go to the most eaten meal")
    func searchUsageOrder() {
        let meals = [meal("Pasta salad", 40, 10, 8), meal("Pasta", 60, 12, 14)]
        let usage = ["Pasta salad": NamedMealSearch.Usage(count: 5, lastEaten: Date())]
        #expect(NamedMealSearch.search("pas", in: meals, usage: usage).map(\.name) == ["Pasta salad", "Pasta"])
        #expect(NamedMealSearch.search("pasta s", in: meals, usage: [:]).map(\.name) == ["Pasta salad"])
    }

    @Test("A picked meal keeps its name only within the tolerance")
    func stillMatchesRule() {
        let pizza = meal("Pizza", 60, 20, 18)
        #expect(pizza.stillMatches(carbs: 64, fat: 20, protein: 18, tolerance: 5, includeFatProtein: true))
        #expect(!pizza.stillMatches(carbs: 90, fat: 20, protein: 18, tolerance: 5, includeFatProtein: true))
        #expect(!pizza.stillMatches(carbs: 60, fat: 30, protein: 18, tolerance: 5, includeFatProtein: true))
        // Carbs-only meals ignore fat and protein.
        #expect(pizza.stillMatches(carbs: 62, fat: 0, protein: 0, tolerance: 5, includeFatProtein: false))
    }

    @Test("Pre-bolus wording")
    func prebolusWording() {
        #expect(NamedMealFormat.prebolus(13) == "Pre-bolus 13 min")
        #expect(NamedMealFormat.prebolus(0) == "Bolused at meal start")
        #expect(NamedMealFormat.prebolus(-5) == "Post-bolus 5 min")
    }
}
