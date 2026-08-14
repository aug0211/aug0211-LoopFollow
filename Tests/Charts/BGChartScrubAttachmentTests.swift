// LoopFollow
// BGChartScrubAttachmentTests.swift

import CoreGraphics
@testable import LoopFollow
import Testing

struct BGChartScrubAttachmentTests {
    private enum Event: Equatable {
        case smb(Int)
        case carb(Int)
        case bolus(Int)
        case bg(Int)
        case cob(Int)
        case composite
    }

    @Test("closer BG wins while an SMB remains inside the capture radius")
    func closerBGBeatsNearbySMB() {
        let selected = resolve(
            current: candidate(.smb(1), x: 125),
            proposals: [candidate(.smb(1), x: 125), candidate(.bg(140), x: 140)],
            cursorX: 140
        )

        #expect(selected == .bg(140))
    }

    @Test("scrub visits the BG entries between two SMBs")
    func visitsBGsBetweenSMBs() {
        let candidates = [
            candidate(.smb(1), x: 100),
            candidate(.bg(120), x: 120),
            candidate(.bg(140), x: 140),
            candidate(.bg(160), x: 160),
            candidate(.smb(2), x: 180),
        ]
        var current = candidates[0]
        var selected: [Event] = []

        for cursorX in [100, 120, 140, 160, 180] as [CGFloat] {
            let value = resolve(current: current, proposals: candidates, cursorX: cursorX)
            selected.append(value)
            current = candidates.first(where: { $0.value == value })!
        }

        #expect(selected == [.smb(1), .bg(120), .bg(140), .bg(160), .smb(2)])
    }

    @Test("scrub visits the same entries in reverse")
    func visitsBGsInReverse() {
        let candidates = [
            candidate(.smb(1), x: 100),
            candidate(.bg(120), x: 120),
            candidate(.bg(140), x: 140),
            candidate(.bg(160), x: 160),
            candidate(.smb(2), x: 180),
        ]
        var current = candidates[4]
        var selected: [Event] = []

        for cursorX in [180, 160, 140, 120, 100] as [CGFloat] {
            let value = resolve(current: current, proposals: candidates, cursorX: cursorX)
            selected.append(value)
            current = candidates.first(where: { $0.value == value })!
        }

        #expect(selected == [.smb(2), .bg(160), .bg(140), .bg(120), .smb(1)])
    }

    @Test("candidate order cannot hide the closest entry")
    func candidateOrderDoesNotMatter() {
        let current = candidate(.smb(1), x: 100)
        let proposals = [candidate(.smb(2), x: 145), candidate(.bg(140), x: 140)]

        #expect(resolve(current: current, proposals: proposals, cursorX: 140) == .bg(140))
        #expect(resolve(current: current, proposals: Array(proposals.reversed()), cursorX: 140) == .bg(140))
    }

    @Test("an explicit treatment wins a same-position composite proposal")
    func explicitTreatmentWinsCompositeTie() {
        let current = candidate(.bg(100), x: 100)
        let proposals = [
            candidate(.bolus(2), x: 140),
            candidate(.composite, x: 140),
        ]

        #expect(resolve(current: current, proposals: proposals, cursorX: 140) == .bolus(2))
    }

    @Test("an exact horizontal tie preserves the attached event type")
    func tiePreservesCurrentEvent() {
        let current = candidate(.cob(20), x: 140)

        #expect(
            resolve(
                current: current,
                proposals: [candidate(.bg(140), x: 140)],
                cursorX: 140
            ) == .cob(20)
        )
    }

    @Test("a true horizontal gap retains the attached entry")
    func gapRetainsCurrentEvent() {
        #expect(
            resolve(
                current: candidate(.bg(100), x: 100),
                proposals: [candidate(.bg(160), x: 160)],
                cursorX: 200
            ) == .bg(100)
        )
    }

    @Test("each sparse treatment kind remains reachable by horizontal position")
    func treatmentKindsRemainReachable() {
        let candidates = [
            candidate(.smb(1), x: 100),
            candidate(.carb(20), x: 130),
            candidate(.bolus(2), x: 160),
        ]

        #expect(nearest(in: candidates, cursorX: 100)?.value == .smb(1))
        #expect(nearest(in: candidates, cursorX: 130)?.value == .carb(20))
        #expect(nearest(in: candidates, cursorX: 160)?.value == .bolus(2))
    }

    @Test("a treatment outside the horizontal capture radius is ignored")
    func distantTreatmentIsIgnored() {
        let candidates = [candidate(.bolus(1), x: 100)]

        #expect(nearest(in: candidates, cursorX: 131) == nil)
        #expect(nearest(in: candidates, cursorX: 130)?.value == .bolus(1))
    }

    private func candidate(_ value: Event, x: CGFloat) -> BGChartHorizontalScrubCandidate<Event> {
        BGChartHorizontalScrubCandidate(value: value, plotX: x)
    }

    private func resolve(
        current: BGChartHorizontalScrubCandidate<Event>,
        proposals: [BGChartHorizontalScrubCandidate<Event>],
        cursorX: CGFloat,
        radius: CGFloat = 30
    ) -> Event {
        horizontallyAdvancedBGChartScrubSelection(
            current: current,
            proposals: proposals,
            cursorX: cursorX,
            captureRadius: radius
        )
    }

    private func nearest(
        in candidates: [BGChartHorizontalScrubCandidate<Event>],
        cursorX: CGFloat,
        radius: CGFloat = 30
    ) -> BGChartHorizontalScrubCandidate<Event>? {
        nearestBGChartHorizontalScrubCandidate(
            in: candidates,
            to: cursorX,
            captureRadius: radius
        )
    }
}
