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

struct SharedQuickPickTests {
    private func occurrence(_ carbs: Int, at date: Date, named: Bool = true) -> MealOccurrence {
        var o = MealOccurrence(id: UUID().uuidString, sentAt: date, mealTime: date, carbs: carbs, fat: 10, protein: 5)
        if named { o.mealID = "m\(carbs)" }
        return o
    }

    @Test("Named meals from other devices join this device's history; duplicates count once")
    func combinedHistory() {
        let now = Date()
        let local = [RemoteMealHistoryEntry(carbs: 40, bolus: 2, date: now)]
        let shared = [
            occurrence(40, at: now.addingTimeInterval(120)), // same meal, sent here
            occurrence(60, at: now.addingTimeInterval(-3600)), // from another device
            occurrence(30, at: now, named: false), // unnamed: stays local to its device
        ]
        let history = QuickPickMealsManager.combinedHistory(local: local, shared: shared)
        #expect(history.map(\.carbs).sorted() == [40, 60])
        #expect(history.first { $0.carbs == 40 }?.bolus == 2)
    }

    @Test("A meal from another device shows only around the time it's usually eaten")
    func sharedMealsFollowTimeOfDay() {
        let now = Date()
        let shared = [
            occurrence(45, at: now.addingTimeInterval(-7 * 86400)), // same time last week
            occurrence(80, at: now.addingTimeInterval(-7 * 86400 + 12 * 3600)), // 12 hours off
        ]
        let history = QuickPickMealsManager.combinedHistory(local: [], shared: shared)
        let picks = QuickPickMealsManager.computeQuickPickMeals(
            from: history, now: now, carbStep: 1, maxCarbs: 200, includeFatProtein: true
        )
        #expect(picks.map(\.carbs) == [45])
    }
}
