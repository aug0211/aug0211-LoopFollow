// LoopFollow
// NamedMeal.swift

import Foundation

/// A meal saved under a name, identified by its carbs, fat and protein.
struct NamedMeal: Codable, Equatable, Identifiable {
    /// LoopFollow's own ID, shared across devices through Nightscout.
    let id: String
    var name: String
    let carbs: Int
    let fat: Int
    let protein: Int
    let createdAt: Date
    /// Nightscout `_id` of the matching food record, once uploaded.
    var nightscoutID: String?

    var macroSummary: String {
        NamedMealFormat.macros(carbs: carbs, fat: fat, protein: protein)
    }
}

/// One meal sent from LoopFollow, with the name and pre-bolus time added afterwards.
struct MealOccurrence: Codable, Equatable, Identifiable {
    let id: String
    let sentAt: Date
    /// The meal time sent to the loop (the scheduled time, or when it was sent).
    let mealTime: Date
    let carbs: Int
    let fat: Int
    let protein: Int
    var mealID: String?
    var mealName: String?
    /// Minutes from the bolus to the start of eating; negative when the bolus came after.
    var prebolusMinutes: Int?
    /// Nightscout `_id` of the note recording this meal, once uploaded.
    var nightscoutID: String?

    var isMissingName: Bool { mealName?.isEmpty ?? true }
    var isMissingPrebolus: Bool { prebolusMinutes == nil }
    var needsDetails: Bool { isMissingName || isMissingPrebolus }
}

enum NamedMealMatcher {
    /// Saved meals whose carbs, fat and protein are each within `tolerance` grams, closest first.
    static func matches(carbs: Int, fat: Int, protein: Int, in meals: [NamedMeal], tolerance: Int) -> [NamedMeal] {
        let limit = max(0, tolerance)
        return meals
            .filter {
                abs($0.carbs - carbs) <= limit
                    && abs($0.fat - fat) <= limit
                    && abs($0.protein - protein) <= limit
            }
            .sorted {
                let lhs = distance($0, carbs: carbs, fat: fat, protein: protein)
                let rhs = distance($1, carbs: carbs, fat: fat, protein: protein)
                return lhs == rhs ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : lhs < rhs
            }
    }

    private static func distance(_ meal: NamedMeal, carbs: Int, fat: Int, protein: Int) -> Int {
        abs(meal.carbs - carbs) + abs(meal.fat - fat) + abs(meal.protein - protein)
    }

    /// The sent meal recorded for a loop meal entry: entries within 10 minutes,
    /// preferring identical macros (a later edit can change them), then the closest time.
    static func occurrence(
        for mealDate: Date,
        carbs: Int,
        fat: Int,
        protein: Int,
        in occurrences: [MealOccurrence]
    ) -> MealOccurrence? {
        let window: TimeInterval = 10 * 60
        let candidates = occurrences.filter { abs($0.mealTime.timeIntervalSince(mealDate)) <= window }
        if let exact = candidates
            .filter({ $0.carbs == carbs && $0.fat == fat && $0.protein == protein })
            .min(by: { abs($0.mealTime.timeIntervalSince(mealDate)) < abs($1.mealTime.timeIntervalSince(mealDate)) })
        {
            return exact
        }
        return candidates.min { abs($0.mealTime.timeIntervalSince(mealDate)) < abs($1.mealTime.timeIntervalSince(mealDate)) }
    }
}

enum NamedMealFormat {
    static let prebolusRange = -60 ... 90
    static let toleranceRange = 0 ... 15

    static func macros(carbs: Int, fat: Int, protein: Int) -> String {
        "\(carbs)g carbs · \(fat)g fat · \(protein)g protein"
    }

    /// "Pre-bolus 13 min", "Bolused at meal start" or "Bolused 5 min after starting".
    static func prebolus(_ minutes: Int) -> String {
        if minutes > 0 { return "Pre-bolus \(minutes) min" }
        if minutes == 0 { return "Bolused at meal start" }
        return "Bolused \(-minutes) min after starting"
    }

    /// Parses a typed pre-bolus. Empty means unknown (nil); out of range or not a number is invalid.
    static func parsePrebolus(_ text: String, negative: Bool) -> PrebolusInput {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        guard let value = Int(trimmed), value >= 0 else { return .invalid }
        let minutes = negative ? -value : value
        return prebolusRange.contains(minutes) ? .minutes(minutes) : .invalid
    }

    enum PrebolusInput: Equatable {
        case empty
        case minutes(Int)
        case invalid
    }

    /// Normalized form used to recognize the same name typed twice.
    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
