// LoopFollow
// MealTextParserTests.swift

@testable import LoopFollow
import Testing

struct MealTextParserTests {
    private func meal(_ carbs: Int, _ fat: Int, _ protein: Int) -> MealTextParser.Meal {
        MealTextParser.Meal(carbs: carbs, fat: fat, protein: protein)
    }

    @Test("Unlabeled numbers are carbs, fat, protein in order")
    func unlabeled() {
        #expect(MealTextParser.parse("Trio: 103, 53, 45") == meal(103, 53, 45))
        #expect(MealTextParser.parse("103, 53, 45") == meal(103, 53, 45))
        #expect(MealTextParser.parse("103/53/45") == meal(103, 53, 45))
        #expect(MealTextParser.parse("103-53-45") == meal(103, 53, 45))
        #expect(MealTextParser.parse("Trio: 40") == meal(40, 0, 0))
        #expect(MealTextParser.parse("Trio: 40.6, 10") == meal(41, 10, 0))
    }

    @Test("Labeled numbers match by label, before or after, in any order")
    func labeled() {
        #expect(MealTextParser.parse("103 carbs 53 fat 45 protein") == meal(103, 53, 45))
        #expect(MealTextParser.parse("45 protein, 103 carbs, 53 fat") == meal(103, 53, 45))
        #expect(MealTextParser.parse("c103 f53 p45") == meal(103, 53, 45))
        #expect(MealTextParser.parse("Carbs: 103, Fat: 53, Protein: 45") == meal(103, 53, 45))
        #expect(MealTextParser.parse("Trio: 103g carbs, 53g fat") == meal(103, 53, 0))
        #expect(MealTextParser.parse("P 30 C 20") == meal(20, 0, 30))
    }

    @Test("Unclear text is not guessed")
    func unclear() {
        #expect(MealTextParser.parse("Trio") == nil)
        #expect(MealTextParser.parse("") == nil)
        #expect(MealTextParser.parse("10, 20, 30, 40") == nil) // too many numbers
        #expect(MealTextParser.parse("12 lunch 40 carbs") == nil) // a stray number among labeled ones
        #expect(MealTextParser.parse("40 carbs 20 carbs") == nil) // same macro twice
        #expect(MealTextParser.parse("0, 0, 0") == nil)
        #expect(MealTextParser.parse("1200, 10, 10") == nil)
    }
}
