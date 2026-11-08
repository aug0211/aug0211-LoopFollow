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
        // 49 readings over 4 hours: rises to 250 at 30 min, then falls to 65.
        var values = [100, 120, 150, 180, 200, 230, 250, 240, 220, 200, 190, 185, 170]
        values += Array(repeating: 150, count: 30) + [120, 100, 90, 80, 70, 65]
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
