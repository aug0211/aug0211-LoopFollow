// LoopFollow
// BGChartScrubAttachmentTests.swift

import CoreGraphics
@testable import LoopFollow
import Testing

struct BGChartScrubAttachmentTests {
    @Test("initial scrub uses the finger's full position")
    func unattachedProbeUsesFingerPosition() {
        let finger = CGPoint(x: 120, y: 280)

        #expect(bgChartScrubProbeLocation(fingerLocation: finger, trackedPlotY: nil) == finger)
    }

    @Test("attached scrub follows finger horizontally while ignoring vertical movement")
    func attachedProbeUsesTrackedPlotHeight() {
        let movedFinger = CGPoint(x: 175, y: 20)

        #expect(
            bgChartScrubProbeLocation(
                fingerLocation: movedFinger,
                trackedPlotY: 240
            ) == CGPoint(x: 175, y: 240)
        )
    }

    @Test("tracked height advances with the newly selected point")
    func probeFollowsUpdatedPlotHeight() {
        let finger = CGPoint(x: 210, y: 350)

        #expect(
            bgChartScrubProbeLocation(
                fingerLocation: finger,
                trackedPlotY: 195
            ) == CGPoint(x: 210, y: 195)
        )
        #expect(
            bgChartScrubProbeLocation(
                fingerLocation: finger,
                trackedPlotY: 170
            ) == CGPoint(x: 210, y: 170)
        )
    }

    @Test("temporary misses retain the attached selection")
    func missRetainsCurrentSelection() {
        #expect(
            retainedBGChartScrubSelection(
                current: "current SMB",
                proposed: nil
            ) == "current SMB"
        )
    }

    @Test("a newly resolved point advances the selection")
    func proposalReplacesCurrentSelection() {
        #expect(
            retainedBGChartScrubSelection(
                current: "current BG",
                proposed: "next BG"
            ) == "next BG"
        )
    }
}
