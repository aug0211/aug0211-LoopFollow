// LoopFollow
// BolusCalculatorAdjustmentTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct BolusCalculatorAdjustmentTests {
    @Test("Default modes use Trio's compound reduction and scheduled-basal addition")
    func trioSemantics() {
        #expect(recommendation(mode: .standard) == 2.15)
        #expect(recommendation(mode: .reduced) == 1.50)
        #expect(recommendation(mode: .superBolus) == 2.95)
    }

    @Test("100 percent standard preserves the unchanged watch result and Loop passthrough")
    func unchangedBaseline() {
        var settings = BolusCalculatorSettings()
        settings.recommendedPercentage = 100
        #expect(BolusCalculatorAdjustment.recommendation(
            base: 2.65, fullBolus: 2.693, scheduledBasal: 0.8,
            mode: .standard, settings: settings, maxBolus: 10
        ) == 2.65)
        #expect(BolusCalculatorAdjustment.recommendation(
            base: 2.123, fullBolus: nil, scheduledBasal: nil,
            mode: .standard, settings: settings, maxBolus: 10
        ) == 2.123)
    }

    @Test("Apply percentage before final rounding, using the unrounded watch sum")
    func adjustmentBeforeRounding() {
        // Watch rounds 2.69 down to 2.65; 80% of the unrounded sum is 2.152,
        // giving 2.15. Applying 80% to 2.65 instead would incorrectly give 2.10.
        #expect(BolusCalculatorAdjustment.recommendation(
            base: 2.65, fullBolus: 2.69, scheduledBasal: 0.8,
            mode: .standard, settings: BolusCalculatorSettings(), maxBolus: 10
        ) == 2.15)
    }

    @Test("Raw 0.82 U gives 0.80 U at 100 percent and 0.65 U at the default 80 percent")
    func smallRecommendationPercentageBeforeRounding() {
        var settings = BolusCalculatorSettings()
        #expect(BolusCalculatorAdjustment.recommendation(
            base: 0.80, fullBolus: 0.82, scheduledBasal: nil,
            mode: .standard, settings: settings, maxBolus: 10
        ) == 0.65)

        settings.recommendedPercentage = 100
        #expect(BolusCalculatorAdjustment.recommendation(
            base: 0.80, fullBolus: 0.82, scheduledBasal: nil,
            mode: .standard, settings: settings, maxBolus: 10
        ) == 0.80)
    }

    @Test("Correction applies 80 percent to the raw sum before rounding, exactly once")
    func correctionPercentageBeforeRounding() {
        // Regression: the screenshot's 0.63 U full sum previously displayed
        // 0.60 U without applying 80%. Using the rounded 0.60 U instead of the
        // full sum would also be wrong: it would produce 0.45 U, not 0.50 U.
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 0.60, fullBolus: 0.63, settings: BolusCalculatorSettings()
        ) == 0.50)
    }

    @Test("Correction follows the configured percentage and preserves 100 percent passthrough")
    func correctionConfiguredPercentage() {
        var settings = BolusCalculatorSettings()
        settings.recommendedPercentage = 50
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 0.60, fullBolus: 0.63, settings: settings
        ) == 0.30)
        settings.recommendedPercentage = 95
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 0.60, fullBolus: 0.63, settings: settings
        ) == 0.60)
        settings.recommendedPercentage = 100
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 0.60, fullBolus: 0.63, settings: settings
        ) == 0.60)
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 2.123, fullBolus: nil, settings: settings
        ) == 2.123)
    }

    @Test("Correction uses only the standard percentage and needs no scheduled basal")
    func correctionIgnoresMealOptions() {
        var settings = BolusCalculatorSettings()
        settings.reducedPercentage = 5
        settings.superPercentage = 200
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 0.60, fullBolus: 0.63, settings: settings
        ) == 0.50)
        settings.reducedEnabled = false
        settings.superEnabled = false
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 0.60, fullBolus: 0.63, settings: settings
        ) == 0.50)
    }

    @Test("Correction clamps negative totals to zero and applies the percentage to a passthrough base")
    func correctionBoundaryInputs() {
        let settings = BolusCalculatorSettings()
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 0, fullBolus: -0.63, settings: settings
        ) == 0)
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 0, fullBolus: 0, settings: settings
        ) == 0)
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 0.63, fullBolus: nil, settings: settings
        ) == 0.50)
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: .nan, fullBolus: 0.63, settings: settings
        ) == nil)
    }

    @Test("Correction display stays uncapped so the existing selection limit remains separate")
    func correctionDisplayBeforeSelectionCap() {
        // For a configured maximum of 4.5 U, the display is still 8.0 U;
        // the existing selection handler, not this calculation, applies that cap.
        #expect(BolusCalculatorAdjustment.correctionRecommendation(
            base: 10, fullBolus: 10, settings: BolusCalculatorSettings()
        ) == 8)
    }

    @Test("A negative base is not percentage-reduced before Super adds basal")
    func negativeFullBolus() {
        #expect(BolusCalculatorAdjustment.recommendation(
            base: 0, fullBolus: -0.6, scheduledBasal: 0.8,
            mode: .superBolus, settings: BolusCalculatorSettings(), maxBolus: 10
        ) == 0.2)
        #expect(BolusCalculatorAdjustment.recommendation(
            base: 0, fullBolus: -2, scheduledBasal: 0.8,
            mode: .superBolus, settings: BolusCalculatorSettings(), maxBolus: 10
        ) == 0)
    }

    @Test("Super needs scheduled basal; a known zero basal remains valid")
    func missingBasal() {
        #expect(recommendation(mode: .superBolus, basal: nil) == nil)
        #expect(recommendation(mode: .superBolus, basal: 0) == 2.15)
        #expect(recommendation(mode: .superBolus, basal: .nan) == nil)
    }

    @Test("Disabling an option falls back to Standard and removes it from selection")
    func disabledModes() {
        var settings = BolusCalculatorSettings()
        settings.reducedEnabled = false
        settings.superEnabled = false
        #expect(settings.availableModes == [.standard])
        #expect(settings.validMode(.reduced) == .standard)
        #expect(settings.validMode(.superBolus) == .standard)
        #expect(recommendation(mode: .reduced, settings: settings) == 2.15)
        #expect(recommendation(mode: .superBolus, settings: settings, basal: nil) == 2.15)
    }

    @Test("Final adjusted recommendation respects the configured maximum")
    func maximumBolus() {
        #expect(BolusCalculatorAdjustment.recommendation(
            base: 10, fullBolus: 10, scheduledBasal: 1,
            mode: .superBolus, settings: BolusCalculatorSettings(), maxBolus: 3
        ) == 3)
    }

    @Test("Malformed percentages and non-finite amounts cannot produce a recommendation")
    func malformedInput() {
        var settings = BolusCalculatorSettings()
        settings.recommendedPercentage = .nan
        #expect(recommendation(mode: .standard, settings: settings) == nil)
        settings.recommendedPercentage = 0
        #expect(recommendation(mode: .standard, settings: settings) == nil)
        #expect(BolusCalculatorAdjustment.recommendation(
            base: .infinity, fullBolus: nil, scheduledBasal: 0.8,
            mode: .superBolus, settings: BolusCalculatorSettings(), maxBolus: 3
        ) == nil)
    }

    @Test("Settings survive persistence and the WatchConnectivity dictionary round trip")
    func settingsRoundTrip() throws {
        var settings = BolusCalculatorSettings()
        settings.recommendedPercentage = 95
        settings.reducedEnabled = false
        settings.reducedPercentage = 60
        settings.superEnabled = true
        settings.superPercentage = 150
        #expect(BolusCalculatorSettings(dictionary: settings.dictionary) == settings)
        #expect(try JSONDecoder().decode(BolusCalculatorSettings.self, from: JSONEncoder().encode(settings)) == settings)
        #expect(BolusCalculatorSettings(dictionary: [:]) == BolusCalculatorSettings())
    }

    private func recommendation(
        mode: BolusCalculatorMode,
        settings: BolusCalculatorSettings = BolusCalculatorSettings(),
        basal: Double? = 0.8
    ) -> Double? {
        BolusCalculatorAdjustment.recommendation(
            base: 2.7, fullBolus: 2.7, scheduledBasal: basal,
            mode: mode, settings: settings, maxBolus: 10
        )
    }
}
