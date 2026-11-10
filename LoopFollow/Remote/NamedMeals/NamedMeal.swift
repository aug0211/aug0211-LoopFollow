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

/// One meal eaten (sent from LoopFollow, the Watch or entered in Trio), with the
/// name and pre-bolus time added afterwards.
struct MealOccurrence: Codable, Equatable, Identifiable {
    let id: String
    let sentAt: Date
    /// The meal time in the loop (when it was entered, or its scheduled time).
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
    /// Trio's meal ID, linking this to the loop's carb entry.
    var trioMealID: String?
    /// How BG went after the meal, worked out once 3 hours have passed.
    var outcome: MealOutcome?

    /// When eating started: the meal time plus the pre-bolus.
    var eatingStart: Date {
        mealTime.addingTimeInterval(Double(prebolusMinutes ?? 0) * 60)
    }

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

    /// Saved meals a meal being entered probably is, best first:
    /// - no name typed: every saved meal with carbs, fat and protein each within
    ///   `tolerance` grams (fat and protein ignored when meals are carbs only);
    /// - a new name typed: saved meals with the same items in a different order, case
    ///   or accents, within the same tolerance. None when the name already matches a
    ///   saved meal exactly, since that one is used.
    /// Closest macros first, then most eaten. Nothing until a macro is entered.
    static func suggestions(
        name: String,
        carbs: Int,
        fat: Int,
        protein: Int,
        in meals: [NamedMeal],
        usage: [String: NamedMealSearch.Usage],
        tolerance: Int,
        includeFatProtein: Bool
    ) -> [NamedMeal] {
        guard carbs > 0 || fat > 0 || protein > 0 else { return [] }
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = meals.filter {
            $0.stillMatches(carbs: carbs, fat: fat, protein: protein, tolerance: max(0, tolerance), includeFatProtein: includeFatProtein)
        }
        if !typed.isEmpty {
            let nameKey = NamedMealFormat.nameKey(typed)
            guard !meals.contains(where: { NamedMealFormat.nameKey($0.name) == nameKey }) else { return [] }
            let key = NamedMealFormat.itemsKey(typed)
            candidates = candidates.filter { NamedMealFormat.itemsKey($0.name) == key }
        }
        func gap(_ meal: NamedMeal) -> Int {
            abs(meal.carbs - carbs) + (includeFatProtein ? abs(meal.fat - fat) + abs(meal.protein - protein) : 0)
        }
        return candidates.sorted { lhs, rhs in
            if gap(lhs) != gap(rhs) { return gap(lhs) < gap(rhs) }
            let lhsCount = usage[lhs.id]?.count ?? 0, rhsCount = usage[rhs.id]?.count ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Whether giving an entry a new name should rename its saved meal in place
    /// (keeping the meal's ID) rather than move the entry to another saved meal: only
    /// when that saved meal is this entry's alone, and no saved meal already has the
    /// new name (then the entry joins that one).
    static func renamesInPlace(
        _ meal: NamedMeal,
        to newName: String,
        for occurrence: MealOccurrence,
        meals: [NamedMeal],
        occurrences: [MealOccurrence]
    ) -> Bool {
        let key = NamedMealFormat.nameKey(newName)
        guard !key.isEmpty, occurrence.mealID == meal.id, NamedMealFormat.nameKey(meal.name) != key else { return false }
        guard !meals.contains(where: { NamedMealFormat.nameKey($0.name) == key }) else { return false }
        return !occurrences.contains { $0.mealID == meal.id && $0.id != occurrence.id }
    }

    private static func distance(_ meal: NamedMeal, carbs: Int, fat: Int, protein: Int) -> Int {
        abs(meal.carbs - carbs) + abs(meal.fat - fat) + abs(meal.protein - protein)
    }

    /// The recorded meal for a loop meal entry: the one linked to Trio's meal ID,
    /// else (just after a send, or after an edit gave the meal a new ID) one within
    /// 10 minutes, preferring identical macros, then the closest time.
    static func occurrence(
        trioMealID: String? = nil,
        for mealDate: Date,
        carbs: Int,
        fat: Int,
        protein: Int,
        in occurrences: [MealOccurrence]
    ) -> MealOccurrence? {
        if let trioMealID, let linked = occurrences.first(where: { $0.trioMealID == trioMealID }) {
            return linked
        }
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

    /// "C57 • F24 • P25", or "C57" when meals are carbs only.
    static func macros(carbs: Int, fat: Int, protein: Int, includeFatProtein: Bool = true) -> String {
        includeFatProtein ? "C\(carbs) • F\(fat) • P\(protein)" : "C\(carbs)"
    }

    /// "Pre-bolus" for a bolus before eating, "Post-bolus" for one after.
    static func bolusTimingLabel(negative: Bool) -> String {
        negative ? "Post-bolus" : "Pre-bolus"
    }

    /// "Pre-bolus 13 min", "Bolused at meal start" or "Post-bolus 5 min".
    static func prebolus(_ minutes: Int) -> String {
        if minutes > 0 { return "Pre-bolus \(minutes) min" }
        if minutes == 0 { return "Bolused at meal start" }
        return "Post-bolus \(-minutes) min"
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

    /// The items in a meal name, ignoring order, case and accents, to spot the same
    /// meal saved twice: "Bobo, P3, Grapes" and "bobo, grapes, p3" match.
    static func itemsKey(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: ",;+&/"))
            .map { NamedMealSearch.normalize($0) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "|")
    }

    /// Normalized form used to recognize the same name typed twice.
    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Finds saved meals by name as you type, forgiving case, accents, missing
/// letters and small typos.
enum NamedMealSearch {
    struct Usage {
        let count: Int
        let lastEaten: Date
    }

    /// How well `query` matches `name`, higher is better; nil when it doesn't match.
    /// 5: name starts with it · 4: a word starts with it · 3: contains it ·
    /// 2: its letters appear in order · 1: one typo per word of 4+ letters.
    static func score(_ query: String, name: String) -> Int? {
        let q = normalize(query)
        let n = normalize(name)
        guard !q.isEmpty, !n.isEmpty else { return nil }
        let words = n.split(separator: " ").map(String.init)

        if n.hasPrefix(q) { return 5 }
        if words.contains(where: { $0.hasPrefix(q) }) { return 4 }
        if n.contains(q) { return 3 }
        if isSubsequence(q.replacingOccurrences(of: " ", with: ""), of: n.replacingOccurrences(of: " ", with: "")) { return 2 }

        let queryWords = q.split(separator: " ").map(String.init)
        let typoMatch = queryWords.allSatisfy { queryWord in
            words.contains { word in
                if word.hasPrefix(queryWord) { return true }
                guard queryWord.count >= 4 else { return false }
                let prefix = String(word.prefix(queryWord.count))
                return editDistance(queryWord, prefix) <= 1 || editDistance(queryWord, word) <= 1
            }
        }
        return typoMatch ? 1 : nil
    }

    /// Matching meals, best match first, then most eaten, then most recent, then by name.
    static func search(_ query: String, in meals: [NamedMeal], usage: [String: Usage]) -> [NamedMeal] {
        meals
            .compactMap { meal in score(query, name: meal.name).map { (meal, $0) } }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                let lhsUsage = usage[lhs.0.id]
                let rhsUsage = usage[rhs.0.id]
                if (lhsUsage?.count ?? 0) != (rhsUsage?.count ?? 0) { return (lhsUsage?.count ?? 0) > (rhsUsage?.count ?? 0) }
                if lhsUsage?.lastEaten != rhsUsage?.lastEaten {
                    return (lhsUsage?.lastEaten ?? .distantPast) > (rhsUsage?.lastEaten ?? .distantPast)
                }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .map { $0.0 }
    }

    static func usage(from occurrences: [MealOccurrence]) -> [String: Usage] {
        var result: [String: Usage] = [:]
        for occurrence in occurrences {
            guard let mealID = occurrence.mealID else { continue }
            let current = result[mealID]
            result[mealID] = Usage(
                count: (current?.count ?? 0) + 1,
                lastEaten: max(current?.lastEaten ?? .distantPast, occurrence.mealTime)
            )
        }
        return result
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var index = haystack.startIndex
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return false }
            index = haystack.index(after: found)
        }
        return true
    }

    /// Levenshtein distance.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0 ... b.count)
        for i in 1 ... a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1 ... b.count {
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[b.count]
    }
}

extension NamedMeal {
    /// Rule for keeping a meal's name at send time: every macro still within the
    /// match tolerance (fat and protein ignored when meals are carbs only).
    func stillMatches(carbs: Int, fat: Int, protein: Int, tolerance: Int, includeFatProtein: Bool) -> Bool {
        guard abs(self.carbs - carbs) <= tolerance else { return false }
        guard includeFatProtein else { return true }
        return abs(self.fat - fat) <= tolerance && abs(self.protein - protein) <= tolerance
    }
}
