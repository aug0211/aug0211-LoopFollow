// LoopFollow
// BGChartScrubAttachment.swift

import CoreGraphics

struct BGChartHorizontalScrubCandidate<Value> {
    let value: Value
    let plotX: CGFloat
}

func horizontallyAdvancedBGChartScrubSelection<Value>(
    current: BGChartHorizontalScrubCandidate<Value>,
    proposals: [BGChartHorizontalScrubCandidate<Value>],
    cursorX: CGFloat,
    captureRadius: CGFloat
) -> Value {
    var best = current
    var bestDistance = abs(current.plotX - cursorX)

    for proposal in proposals {
        let distance = abs(proposal.plotX - cursorX)
        guard distance <= captureRadius, distance < bestDistance else { continue }
        best = proposal
        bestDistance = distance
    }

    return best.value
}
