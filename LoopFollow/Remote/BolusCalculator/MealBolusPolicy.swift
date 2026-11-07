// LoopFollow
// MealBolusPolicy.swift

import Foundation

/// The selected amount is the only source of insulin for a meal command.
enum MealBolusPolicy {
    static func commandBolus(enteredAmount: Double, scheduledTime: Date?) -> Decimal? {
        let amount = amountToSend(enteredAmount: enteredAmount, isScheduling: scheduledTime != nil, mealWithBolus: true)
        return amount > 0 ? Decimal(amount) : nil
    }

    static func amountToSend(enteredAmount: Double, isScheduling: Bool, mealWithBolus: Bool) -> Double {
        guard !isScheduling, mealWithBolus, enteredAmount.isFinite, enteredAmount > 0 else { return 0 }
        return enteredAmount
    }
}
