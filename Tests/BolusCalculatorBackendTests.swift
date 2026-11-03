// LoopFollow
// BolusCalculatorBackendTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct BolusCalculatorBackendTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(bg: Int = 160, delta: Int? = 2, isf: Double? = 50,
                       cr: Double? = 10, target: Double? = 100,
                       iob: Double? = 1.3, cob: Double? = 10) -> PhoneMealCalculationState {
        let state = PhoneMealCalculationState()
        state.currentBG = .init(bgValue: bg, timestamp: now, delta: delta)
        state.bgHistory = [state.currentBG!, .init(bgValue: 145, timestamp: now.addingTimeInterval(-900), delta: nil)]
        state.loopStatus = .init(iob: iob, cob: cob, recommendedBolus: nil, isf: isf, carbRatio: cr, currentTarget: target)
        return state
    }

    @Test("Watch baseline includes entered carbs and pending insulin with the 15-minute delta")
    func watchBaseline() throws {
        let state = state()
        state.pendingCarbs = 30
        state.pendingInsulin = 0.25
        state.updateRecommendedBolus()
        let calc = try #require(state.bolusCalc)
        #expect(calc.delta == 15)
        #expect(calc.glucoseEffect == 1.2)
        #expect(calc.cobEffect == 4)
        #expect(calc.iobEffect == -1.55)
        #expect(calc.deltaEffect == 0.3)
        #expect(state.recommendedBolus == 3.95)
    }

    @Test("Watch division floors each term before flooring the final recommendation")
    func floorEveryDivision() throws {
        let state = state(bg: 130, isf: 75, cr: 9, iob: 0.719, cob: 0)
        state.bgHistory = [state.currentBG!]
        state.pendingCarbs = 21
        state.updateRecommendedBolus()
        let calc = try #require(state.bolusCalc)
        #expect(calc.cobEffect == 2.33)
        #expect(calc.deltaEffect == 0.02)
        #expect(abs(calc.fullBolus - 2.031) < 0.000001)
        #expect(state.recommendedBolus == 2)
    }

    @Test("Exactly 7.5 minutes from the 15-minute mark uses the current-reading delta")
    func strictDeltaTolerance() throws {
        let state = state()
        state.bgHistory = [state.currentBG!, .init(bgValue: 100, timestamp: now.addingTimeInterval(-1350), delta: nil)]
        state.updateRecommendedBolus()
        #expect(try #require(state.bolusCalc).delta == 2)
        state.bgHistory[1] = .init(bgValue: 100, timestamp: now.addingTimeInterval(-1349), delta: nil)
        state.updateRecommendedBolus()
        #expect(try #require(state.bolusCalc).delta == 60)
    }

    @Test("Zero device-status ISF blocks calculation even if a profile ISF exists")
    func zeroISFIsNotMissing() {
        let state = state(isf: 0)
        state.isfSchedule = [(0, 50)]
        state.updateRecommendedBolus()
        #expect(state.recommendedBolus == 0)
        #expect(state.bolusCalc == nil)
    }

    @Test("Missing CR omits carb contribution, and missing target falls back to 100")
    func missingCRAndTarget() throws {
        let state = state(cr: nil, target: nil, iob: 0, cob: 50)
        state.pendingCarbs = 40
        state.updateRecommendedBolus()
        let calc = try #require(state.bolusCalc)
        #expect(calc.cobEffect == 0)
        #expect(calc.target == 100)
        #expect(state.recommendedBolus == 1.5)
    }

    @Test("Loop upstream recommendation bypasses local math and its rounding")
    func loopPassthrough() {
        let state = PhoneMealCalculationState()
        state.loopStatus = .init(iob: nil, cob: nil, recommendedBolus: 1.2345, isf: nil, carbRatio: nil, currentTarget: nil)
        state.pendingInsulin = 0.1
        state.pendingCarbs = 999
        state.updateRecommendedBolus()
        #expect(abs(state.recommendedBolus - 1.1345) < 0.0000001)
        #expect(state.bolusCalc == nil)
        state.pendingInsulin = 5
        state.updateRecommendedBolus()
        #expect(state.recommendedBolus == 0)
    }

    @Test("OpenAPS selects the whole suggested block and ignores structured CR")
    func suggestedAndCRSelection() throws {
        let state = PhoneMealCalculationState()
        let data = Data(#"[{"openaps":{"iob":{"iob":1.25},"suggested":{"COB":9,"CR":99,"reason":"CR: 7.5; COB: 20"},"enacted":{"ISF":50,"current_target":110,"COB":15,"reason":"CR: 10"}}}]"#.utf8)
        state.pendingInsulin = 0.5
        #expect(state.parseDeviceStatus(data: data))
        let status = try #require(state.loopStatus)
        #expect(status.iob == 1.25)
        #expect(status.cob == 9)
        #expect(status.carbRatio == 7.5)
        #expect(status.isf == nil)
        #expect(status.currentTarget == nil)
        #expect(state.pendingInsulin == 0)
    }

    @Test("OpenAPS enacted fallback and reason COB match watch decoding")
    func enactedReasonFallback() throws {
        let state = PhoneMealCalculationState()
        #expect(state.parseDeviceStatus(data: Data(#"[{"openaps":{"enacted":{"ISF":48,"current_target":105,"reason":"COB: 12.5; CR: 8"}}}]"#.utf8)))
        let status = try #require(state.loopStatus)
        #expect(status.cob == 12.5)
        #expect(status.carbRatio == 8)
        #expect(status.isf == 48)
        #expect(status.currentTarget == 105)
    }

    @Test("Nightscout entry ordering and immediate-entry delta preserve watch behavior")
    func entryOrderAndDelta() throws {
        let state = PhoneMealCalculationState()
        let data = Data(#"[{"sgv":153.5,"date":1800000000000},{"date":1799999700000},{"mbg":140.4,"date":1799999400000}]"#.utf8)
        #expect(state.parseNightscoutResponse(data: data))
        #expect(state.bgHistory.map(\.bgValue) == [154, 140])
        #expect(try #require(state.currentBG).delta == nil)
        #expect(try #require(state.currentBG).timestamp == now)
    }

    @Test("Profile uses target_low, timeAsSeconds, default store and profile timezone")
    func profileRules() throws {
        let state = PhoneMealCalculationState()
        let data = Data(#"{"defaultProfile":"missing","store":{"Default":{"timezone":"Pacific/Honolulu","sens":[{"timeAsSeconds":3600,"value":75},{"timeAsSeconds":0,"value":50}],"carbratio":[{"value":10,"time":"12:00"}],"basal":[{"value":0.8}],"target_low":[{"value":95}],"target_high":[{"value":120}]}}}"#.utf8)
        #expect(state.parseProfile(data: data))
        #expect(state.profileTimezone.identifier == "Pacific/Honolulu")
        #expect(state.isfSchedule.map(\.timeAsSeconds) == [0, 3600])
        #expect(state.carbRatioSchedule[0].timeAsSeconds == 0)
        #expect(state.lookupScheduleValue(state.targetSchedule) == 95)
        #expect(state.lookupScheduleValue(state.basalSchedule) == 0.8)
    }

    @Test("Lookup before the first entry wraps to the final profile value")
    func profileWrap() {
        let state = PhoneMealCalculationState()
        #expect(state.lookupScheduleValue([(86400, 5), (90000, 8)]) == 8)
        #expect(state.lookupScheduleValue([]) == nil)
    }

    @Test("Missing BG clears a prior local result")
    func missingBG() {
        let state = state()
        state.updateRecommendedBolus()
        #expect(state.bolusCalc != nil)
        state.currentBG = nil
        state.updateRecommendedBolus()
        #expect(state.recommendedBolus == 0)
        #expect(state.bolusCalc == nil)
    }
}
