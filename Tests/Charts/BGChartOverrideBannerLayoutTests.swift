// LoopFollow
// BGChartOverrideBannerLayoutTests.swift

import CoreGraphics
@testable import LoopFollow
import Testing

struct BGChartOverrideBannerLayoutTests {
    private let plotFrame = CGRect(x: 0, y: 10, width: 1200, height: 200)

    @Test("Banner follows the actual canvas geometry and fits its text")
    func measuredGeometry() throws {
        let rect = try #require(layout(CGRect(x: 420, y: 30, width: 120, height: 10)))
        #expect(rect == CGRect(x: 120, y: 24, width: 120, height: 22))
        // The full drawn banner, including its expanded height, is the tap target.
        #expect(rect.contains(CGPoint(x: 150, y: 26)))
        #expect(!rect.contains(CGPoint(x: 150, y: 23)))
    }

    @Test("Pan shifts the interval without changing its height")
    func panning() throws {
        let canvasRect = CGRect(x: 420, y: 30, width: 120, height: 10)
        let before = try #require(layout(canvasRect))
        let after = try #require(layout(canvasRect, offset: 340))
        #expect(after.minX == before.minX - 40)
        #expect(after.size == before.size)
        #expect(after.midY == before.midY)
    }

    @Test("Live pinch moves time edges around the anchor without stretching text height")
    func livePinch() throws {
        let rect = try #require(layout(
            CGRect(x: 420, y: 30, width: 120, height: 10), scale: 1.25, anchor: 100
        ))
        #expect(rect == CGRect(x: 125, y: 24, width: 150, height: 22))
    }

    @Test("Viewport clipping happens after the live pinch transform")
    func clippedPinch() throws {
        let rect = try #require(layout(
            CGRect(x: 280, y: 30, width: 80, height: 10), scale: 2, anchor: 50
        ))
        #expect(rect == CGRect(x: 0, y: 24, width: 70, height: 22))
    }

    @Test("Partially visible and spanning overrides stay within the viewport")
    func visibleIntervals() throws {
        let left = try #require(layout(CGRect(x: 280, y: 30, width: 80, height: 10)))
        let right = try #require(layout(CGRect(x: 580, y: 30, width: 80, height: 10)))
        let spanning = try #require(layout(CGRect(x: 100, y: 30, width: 1000, height: 10)))
        #expect(left.minX == 0 && left.width == 60)
        #expect(right.minX == 280 && right.width == 20)
        #expect(spanning.minX == 0 && spanning.width == 300)
        #expect(layout(CGRect(x: 100, y: 30, width: 100, height: 10)) == nil)
        #expect(layout(CGRect(x: 650, y: 30, width: 100, height: 10)) == nil)
    }

    @Test("Readable banners remain inside the actual plot at both vertical edges")
    func verticalClipping() throws {
        let top = try #require(layout(CGRect(x: 420, y: 12, width: 120, height: 6)))
        let bottom = try #require(layout(CGRect(x: 420, y: 204, width: 120, height: 6)))
        #expect(top.minY == plotFrame.minY && top.height == 22)
        #expect(bottom.maxY == plotFrame.maxY && bottom.height == 22)
    }

    @Test("Larger text gets a taller banner while preserving the time interval")
    func dynamicType() throws {
        let rect = try #require(layout(
            CGRect(x: 420, y: 30, width: 120, height: 10), minimumHeight: 44
        ))
        #expect(rect == CGRect(x: 120, y: 13, width: 120, height: 44))
    }

    @Test("Invalid geometry cannot create a visible or tappable banner")
    func invalidGeometry() {
        #expect(layout(.zero) == nil)
        #expect(layout(CGRect(x: 420, y: 30, width: 120, height: 10), scale: 0) == nil)
        #expect(layout(CGRect(x: 420, y: 30, width: 120, height: 10), scale: .nan) == nil)
    }

    private func layout(
        _ canvasRect: CGRect,
        offset: CGFloat = 300,
        scale: CGFloat = 1,
        anchor: CGFloat = 0,
        minimumHeight: CGFloat = 22
    ) -> CGRect? {
        bgChartOverrideBannerRect(
            canvasRect: canvasRect,
            canvasOffsetX: offset,
            pinchScale: scale,
            pinchAnchorX: anchor,
            viewportWidth: 300,
            plotFrame: plotFrame,
            minimumHeight: minimumHeight
        )
    }
}
