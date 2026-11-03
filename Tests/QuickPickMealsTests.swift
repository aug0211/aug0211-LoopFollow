// LoopFollow
// QuickPickMealsTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct QuickPickMealsTests {
    @Test("Missing or null bolus preserves meal history and produces a zero-bolus Quick-Pick", arguments: [false, true])
    func missingBolusDefaultsToZero(useNull: Bool) throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let meal = RemoteMealHistoryEntry(carbs: 30, fat: 8, protein: 12, date: now)
        let mealWithBolus = RemoteMealHistoryEntry(carbs: 45, bolus: 2.15, date: now)
        let encoded = try JSONEncoder().encode([meal, mealWithBolus])
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        if useNull {
            json[0]["bolus"] = NSNull()
        } else {
            json[0].removeValue(forKey: "bolus")
        }

        let decoded = try JSONDecoder().decode(
            [RemoteMealHistoryEntry].self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        #expect(decoded == [meal, mealWithBolus])

        let picks = QuickPickMealsManager.computeQuickPickMeals(
            from: decoded, now: now, carbStep: 1, maxCarbs: 100, includeFatProtein: true
        )
        let zeroBolusPick = try #require(picks.first { $0.carbs == 30 })
        #expect(zeroBolusPick.bolus == 0)
        #expect(zeroBolusPick.fat == 8)
        #expect(zeroBolusPick.protein == 12)
        let positiveBolusPick = try #require(picks.first { $0.carbs == 45 })
        #expect(positiveBolusPick.bolus == 2.15)
    }

    @Test("Saved zero and positive boluses survive a history round trip", arguments: [0.0, 2.15])
    func savedBolusRoundTrip(bolus: Double) throws {
        let meal = RemoteMealHistoryEntry(
            carbs: 30, fat: 8, protein: 12, bolus: bolus,
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let decoded = try JSONDecoder().decode(RemoteMealHistoryEntry.self, from: JSONEncoder().encode(meal))
        #expect(decoded == meal)
    }
}
