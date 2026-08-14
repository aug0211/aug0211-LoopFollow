// LoopFollow
// BGChartScrubAttachment.swift

import CoreGraphics

func bgChartScrubProbeLocation(
    fingerLocation: CGPoint,
    trackedPlotY: CGFloat?
) -> CGPoint {
    guard let trackedPlotY, trackedPlotY.isFinite else { return fingerLocation }
    return CGPoint(x: fingerLocation.x, y: trackedPlotY)
}

func retainedBGChartScrubSelection<Value>(
    current: Value?,
    proposed: Value?
) -> Value? {
    proposed ?? current
}
