// LoopFollow
// MealBolusPolicyTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct MealBolusPolicyTests {
    @Test("A recommendation alone does not select insulin")
    func zeroSelection() {
        #expect(MealBolusPolicy.amountToSend(enteredAmount: 0, isScheduling: false, mealWithBolus: true) == 0)
        #expect(MealBolusPolicy.commandBolus(enteredAmount: 0, scheduledTime: nil) == nil)
    }

    @Test("Explicit calculator, manual, and Quick-Pick selections retain their exact amount")
    func explicitSelection() {
        for amount in [0.05, 1.5, 2.15, 3.25] {
            #expect(MealBolusPolicy.amountToSend(enteredAmount: amount, isScheduling: false, mealWithBolus: true) == amount)
            #expect(MealBolusPolicy.commandBolus(enteredAmount: amount, scheduledTime: nil) == Decimal(amount))
        }
    }

    @Test("Scheduling and disabled meal boluses override any stale or saved positive amount")
    func schedulingDisablesInsulin() {
        #expect(MealBolusPolicy.amountToSend(enteredAmount: 2.15, isScheduling: true, mealWithBolus: true) == 0)
        #expect(MealBolusPolicy.amountToSend(enteredAmount: 2.15, isScheduling: false, mealWithBolus: false) == 0)
        #expect(MealBolusPolicy.commandBolus(enteredAmount: 2.15, scheduledTime: Date()) == nil)
        #expect(MealBolusPolicy.commandBolus(enteredAmount: 2.15, scheduledTime: Date().addingTimeInterval(3600)) == nil)
    }

    @Test("Scheduled meal payload omits bolus_amount even when supplied a positive amount")
    func scheduledPayload() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = CommandPayload(
            user: "Test", commandType: .meal, timestamp: 1_799_999_000,
            bolusAmount: MealBolusPolicy.commandBolus(enteredAmount: 2.15, scheduledTime: date),
            carbs: 45, protein: 20, fat: 12, scheduledTime: date.timeIntervalSince1970
        )
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        #expect(json["bolus_amount"] == nil)
        #expect(json["carbs"] as? Int == 45)
        #expect(json["scheduled_time"] as? Double == date.timeIntervalSince1970)
    }

    @Test("Invalid amounts cannot become a command")
    func invalidAmounts() {
        for amount in [-1, Double.nan, Double.infinity] {
            #expect(MealBolusPolicy.commandBolus(enteredAmount: amount, scheduledTime: nil) == nil)
        }
    }
}
