import XCTest
@testable import AirTrackCore

/// HandState → on-screen overlay coordinates (top-left origin, y down).
final class PreviewGeometryTests: XCTestCase {
    private let aspect = 16.0 / 9.0

    private func view(_ p: Point2D, width: Double = 1600, height: Double = 900, mirrored: Bool = false) -> Point2D? {
        PreviewGeometry.viewPoint(for: p, imageAspectRatio: aspect, viewWidth: width, viewHeight: height, mirrored: mirrored)
    }

    // MARK: Vertical orientation (the reported bug)

    func testTopOfImageIsTopOfViewAndBottomIsBottom() {
        XCTAssertEqual(view(Point2D(x: 0.5, y: 0))?.y ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(view(Point2D(x: 0.5, y: 1))?.y ?? -1, 900, accuracy: 1e-6)
    }

    func testMovingTheHandUpMovesTheOverlayUp() {
        // Provider space (Vision): y grows UP. Hand moves from low to high in the real image.
        var viewYs: [Double] = []
        for visionY in [0.2, 0.4, 0.6, 0.8] {
            let hand = LandmarkCoordinateConversion.handState(
                fromBottomLeftOrigin: [.indexTip: .init(x: 0.5, y: visionY, confidence: 1)],
                timestamp: 0, imageAspectRatio: aspect
            )
            viewYs.append(view(hand.position(of: .indexTip)!)!.y)
        }
        // View space: y grows DOWN, so an upward movement must DECREASE y at every step.
        XCTAssertEqual(viewYs, viewYs.sorted(by: >))
        XCTAssertEqual(viewYs.first!, 720, accuracy: 1e-9)
        XCTAssertEqual(viewYs.last!, 180, accuracy: 1e-9)
    }

    // MARK: Horizontal orientation and mirroring

    func testUnmirroredHorizontalMatchesTheImage() {
        XCTAssertEqual(view(Point2D(x: 0, y: 0.5))?.x ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(view(Point2D(x: 1, y: 0.5))?.x ?? -1, 1600, accuracy: 1e-6)
        XCTAssertEqual(view(Point2D(x: 0.25, y: 0.5))?.x ?? -1, 400, accuracy: 1e-6)
    }

    func testMirroringFlipsHorizontalOnly() {
        let raw = Point2D(x: 0.25, y: 0.3)
        XCTAssertPointEqual(view(raw, mirrored: true), Point2D(x: 1200, y: 270))
        XCTAssertPointEqual(view(raw, mirrored: false), Point2D(x: 400, y: 270))
    }

    func testMovingRightInTheImageMovesLeftInAMirroredPreview() {
        let a = view(Point2D(x: 0.3, y: 0.5), mirrored: true)!
        let b = view(Point2D(x: 0.6, y: 0.5), mirrored: true)!
        XCTAssertLessThan(b.x, a.x)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
    }

    // MARK: Aspect ratio and letterboxing

    func testWideViewGetsSideBars() {
        // 16:9 image in a 2000×900 view: content is 1600 wide, centered → 200 pt bars.
        let rect = PreviewGeometry.aspectFitRect(imageAspectRatio: aspect, viewWidth: 2000, viewHeight: 900)
        XCTAssertRectEqual(rect, Rect2D(x: 200, y: 0, width: 1600, height: 900))
        XCTAssertPointEqual(view(Point2D(x: 0, y: 0), width: 2000), Point2D(x: 200, y: 0))
    }

    func testTallViewGetsTopAndBottomBars() {
        // 16:9 image in a 1600×1200 view: content is 900 tall, centered → 150 pt bars.
        let rect = PreviewGeometry.aspectFitRect(imageAspectRatio: aspect, viewWidth: 1600, viewHeight: 1200)
        XCTAssertRectEqual(rect, Rect2D(x: 0, y: 150, width: 1600, height: 900))
        XCTAssertPointEqual(view(Point2D(x: 1, y: 1), height: 1200), Point2D(x: 1600, y: 1050))
    }

    func testCornersAndEdgesLandOnTheContentRect() {
        let w = 2000.0, h = 900.0 // side bars of 200
        XCTAssertPointEqual(view(Point2D(x: 0, y: 0), width: w, height: h), Point2D(x: 200, y: 0))
        XCTAssertPointEqual(view(Point2D(x: 1, y: 0), width: w, height: h), Point2D(x: 1800, y: 0))
        XCTAssertPointEqual(view(Point2D(x: 0, y: 1), width: w, height: h), Point2D(x: 200, y: 900))
        XCTAssertPointEqual(view(Point2D(x: 1, y: 1), width: w, height: h), Point2D(x: 1800, y: 900))
        XCTAssertPointEqual(view(Point2D(x: 0.5, y: 0.5), width: w, height: h), Point2D(x: 1000, y: 450))
    }

    func testDegenerateInputsProduceNoPoint() {
        XCTAssertNil(view(Point2D(x: .nan, y: 0.5)))
        XCTAssertNil(PreviewGeometry.viewPoint(for: Point2D(x: 0.5, y: 0.5), imageAspectRatio: 0, viewWidth: 100, viewHeight: 100, mirrored: false))
        XCTAssertNil(PreviewGeometry.viewPoint(for: Point2D(x: 0.5, y: 0.5), imageAspectRatio: aspect, viewWidth: 0, viewHeight: 100, mirrored: false))
    }

    // MARK: Distance stability

    func testHandSizeDoesNotShiftItsAnchor() {
        // Same wrist position, hand at three sizes (near → far). The wrist must stay put on
        // screen and the fingertip must move along the same line, proportionally.
        let wrist = Point2D(x: 0.4, y: 0.6)
        var wristViews: [Point2D] = []
        var tipOffsets: [Point2D] = []
        for scale in [1.0, 0.5, 0.25] {
            let hand = TestHands.openHand(center: wrist - TestHands.openHandOffsets[.wrist]! * scale, scale: scale)
            let w = view(hand.position(of: .wrist)!, mirrored: true)!
            let t = view(hand.position(of: .indexTip)!, mirrored: true)!
            wristViews.append(w)
            tipOffsets.append((t - w) * (1 / scale))
        }
        for w in wristViews { XCTAssertPointEqual(w, wristViews[0], accuracy: 1e-9) }
        for o in tipOffsets { XCTAssertPointEqual(o, tipOffsets[0], accuracy: 1e-9) }
    }

    func testMappingIsAffineSoHandShapeIsPreserved() {
        let a = Point2D(x: 0.2, y: 0.3), b = Point2D(x: 0.6, y: 0.7)
        let mid = (a + b) * 0.5
        let va = view(a, width: 2000)!, vb = view(b, width: 2000)!
        XCTAssertPointEqual(view(mid, width: 2000), (va + vb) * 0.5)
    }
}
