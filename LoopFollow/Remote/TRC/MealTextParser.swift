// LoopFollow
// MealTextParser.swift

import Foundation

/// Reads carbs, fat and protein from text someone typed, such as a message:
/// "Trio: 103, 53, 45", "103/53/45", "103 carbs 53 fat 45 protein" or "c103 f53 p45".
///
/// Labeled numbers are matched by label, in any order. Unlabeled numbers are read
/// as carbs, fat, protein in that order. Anything unclear returns nil rather than
/// a guess.
enum MealTextParser {
    struct Meal: Equatable {
        let carbs: Int
        let fat: Int
        let protein: Int
    }

    private enum Macro { case carbs, fat, protein }

    private enum Token: Equatable {
        case number(Double)
        case word(String)
    }

    static func parse(_ text: String) -> Meal? {
        let tokens = tokenize(text)
        let numberCount = tokens.filter { if case .number = $0 { return true } else { return false } }.count
        guard numberCount > 0 else { return nil }

        // Which way labels attach: "c103" / "carbs: 103" (before) or "103 carbs" (after),
        // decided by whichever comes first in the text.
        let firstLabel = tokens.firstIndex { if case let .word(word) = $0 { return macro(for: word) != nil } else { return false } }
        let firstNumber = tokens.firstIndex { if case .number = $0 { return true } else { return false } }

        var values: [Macro: Double] = [:]
        if let firstLabel, let firstNumber {
            let labelsBefore = firstLabel < firstNumber
            for (index, token) in tokens.enumerated() {
                guard case let .number(value) = token else { continue }
                let neighbor = labelsBefore ? index - 1 : index + 1
                guard tokens.indices.contains(neighbor),
                      case let .word(word) = tokens[neighbor],
                      let macro = macro(for: word)
                else { return nil } // a number without a label next to labeled ones
                guard values[macro] == nil else { return nil } // same macro twice
                values[macro] = value
            }
        } else {
            let numbers = tokens.compactMap { token -> Double? in
                if case let .number(value) = token { return value }
                return nil
            }
            guard numbers.count <= 3 else { return nil }
            let order: [Macro] = [.carbs, .fat, .protein]
            for (index, value) in numbers.enumerated() {
                values[order[index]] = value
            }
        }

        let meal = Meal(
            carbs: Int((values[.carbs] ?? 0).rounded()),
            fat: Int((values[.fat] ?? 0).rounded()),
            protein: Int((values[.protein] ?? 0).rounded())
        )
        guard meal.carbs > 0 || meal.fat > 0 || meal.protein > 0,
              [meal.carbs, meal.fat, meal.protein].allSatisfy({ $0 <= 999 })
        else { return nil }
        return meal
    }

    private static func macro(for word: String) -> Macro? {
        switch word {
        case "c", "carb", "carbs", "carbohydrate", "carbohydrates", "cho": return .carbs
        case "f", "fat", "fats": return .fat
        case "p", "pro", "prot", "protein", "proteins": return .protein
        default: return nil
        }
    }

    /// Numbers and lowercase words; "g"/"grams" units and punctuation are dropped.
    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var isNumber = false

        func flush() {
            guard !current.isEmpty else { return }
            if isNumber {
                if let value = Double(current) { tokens.append(.number(value)) }
            } else {
                let word = current.lowercased()
                if !["g", "gr", "gram", "grams"].contains(word) { tokens.append(.word(word)) }
            }
            current = ""
        }

        for character in text {
            if character.isASCII, character.isNumber || (character == "." && isNumber && !current.contains(".")) {
                if !isNumber { flush(); isNumber = true }
                current.append(character)
            } else if character.isLetter {
                if isNumber { flush(); isNumber = false }
                current.append(character)
            } else {
                flush()
                isNumber = false
            }
        }
        flush()
        return tokens
    }
}
