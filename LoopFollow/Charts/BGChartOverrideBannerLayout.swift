// LoopFollow
// BGChartOverrideBannerLayout.swift

import Foundation

/// The visible banner and its hit region share this screen-space rectangle.
/// Apply the canvas's pan/pinch transform to its edges, keeping text unscaled.
func bgChartOverrideBannerRect(
    canvasRect: CGRect,
    canvasOffsetX: CGFloat,
    pinchScale: CGFloat,
    pinchAnchorX: CGFloat,
    viewportWidth: CGFloat,
    plotFrame: CGRect,
    minimumHeight: CGFloat
) -> CGRect? {
    let values = [canvasRect.minX, canvasRect.maxX, canvasRect.minY, canvasRect.maxY,
                  canvasOffsetX, pinchScale, pinchAnchorX, viewportWidth,
                  plotFrame.minY, plotFrame.maxY, minimumHeight]
    guard values.allSatisfy(\.isFinite), canvasRect.width > 0, canvasRect.height >= 0,
          pinchScale > 0, viewportWidth > 0, plotFrame.height > 0, minimumHeight > 0
    else { return nil }

    func viewportX(_ canvasX: CGFloat) -> CGFloat {
        (canvasX - canvasOffsetX - pinchAnchorX) * pinchScale + pinchAnchorX
    }
    let left = max(0, viewportX(canvasRect.minX))
    let right = min(viewportWidth, viewportX(canvasRect.maxX))
    guard right > left else { return nil }

    let height = min(max(canvasRect.height, minimumHeight), plotFrame.height)
    let top = min(max(canvasRect.midY - height / 2, plotFrame.minY), plotFrame.maxY - height)
    return CGRect(x: left, y: top, width: right - left, height: height)
}
