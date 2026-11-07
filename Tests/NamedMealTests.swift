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

    @Test("Pre-bolus wording")
    func prebolusWording() {
        #expect(NamedMealFormat.prebolus(13) == "Pre-bolus 13 min")
        #expect(NamedMealFormat.prebolus(0) == "Bolused at meal start")
        #expect(NamedMealFormat.prebolus(-5) == "Bolused 5 min after starting")
    }
}
