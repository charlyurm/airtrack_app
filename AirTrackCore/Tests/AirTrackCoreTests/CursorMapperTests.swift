import XCTest
@testable import AirTrackCore

final class CursorMapperTests: XCTestCase {
    func testCenterOfActiveAreaMapsToCenterOfScreen() {
        let mapper = CursorMapper()
        XCTAssertPointEqual(mapper.map(Point2D(x: 0.5, y: 0.5)), Point2D(x: 0.5, y: 0.5))
    }

    func testMirrorFlipsHorizontalAxisOnly() {
        let mapper = CursorMapper(mirrorHorizontally: true, activeArea: .unit)
        XCTAssertPointEqual(mapper.map(Point2D(x: 0.3, y: 0.4)), Point2D(x: 0.7, y: 0.4))
    }

    func testWithoutMirrorKeepsCameraOrientation() {
        let mapper = CursorMapper(mirrorHorizontally: false, activeArea: .unit)
        XCTAssertPointEqual(mapper.map(Point2D(x: 0.3, y: 0.4)), Point2D(x: 0.3, y: 0.4))
    }

    func testActiveAreaCornersMapToScreenCorners() {
        let mapper = CursorMapper(mirrorHorizontally: true, activeArea: Rect2D(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        // Mirrored x 0.2 == camera x 0.8.
        XCTAssertPointEqual(mapper.map(Point2D(x: 0.8, y: 0.2)), Point2D(x: 0, y: 0))
        XCTAssertPointEqual(mapper.map(Point2D(x: 0.2, y: 0.8)), Point2D(x: 1, y: 1))
    }

    func testSmallHandTravelCoversWholeScreen() {
        let mapper = CursorMapper(mirrorHorizontally: false, activeArea: Rect2D(x: 0.3, y: 0.3, width: 0.4, height: 0.4))
        XCTAssertPointEqual(mapper.map(Point2D(x: 0.3, y: 0.3)), Point2D(x: 0, y: 0))
        XCTAssertPointEqual(mapper.map(Point2D(x: 0.7, y: 0.7)), Point2D(x: 1, y: 1))
    }

    func testPointsOutsideActiveAreaAreClampedToScreenEdges() {
        let mapper = CursorMapper(mirrorHorizontally: false, activeArea: Rect2D(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        XCTAssertPointEqual(mapper.map(Point2D(x: 0.0, y: 0.0)), Point2D(x: 0, y: 0))
        XCTAssertPointEqual(mapper.map(Point2D(x: 1.0, y: 1.0)), Point2D(x: 1, y: 1))
        XCTAssertPointEqual(mapper.map(Point2D(x: -5, y: 0.5)), Point2D(x: 0, y: 0.5))
    }

    func testHigherSensitivityShrinksEffectiveArea() {
        let mapper = CursorMapper(mirrorHorizontally: false, activeArea: Rect2D(x: 0.2, y: 0.2, width: 0.6, height: 0.6), sensitivity: 2)
        let area = mapper.effectiveArea
        XCTAssertEqual(area.minX, 0.35, accuracy: 1e-9)
        XCTAssertEqual(area.width, 0.3, accuracy: 1e-9)
        XCTAssertPointEqual(mapper.map(Point2D(x: 0.35, y: 0.35)), Point2D(x: 0, y: 0))
        XCTAssertPointEqual(mapper.map(Point2D(x: 0.5, y: 0.5)), Point2D(x: 0.5, y: 0.5))
    }

    func testSensitivityIsClampedToSupportedRange() {
        let tooHigh = CursorMapper(sensitivity: 100)
        let atMax = CursorMapper(sensitivity: CursorMapper.sensitivityRange.upperBound)
        XCTAssertRectEqual(tooHigh.effectiveArea, atMax.effectiveArea)

        let nonFinite = CursorMapper(sensitivity: .nan)
        XCTAssertRectEqual(nonFinite.effectiveArea, CursorMapper(sensitivity: 1).effectiveArea)
    }

    func testNonFiniteInputProducesNoCursorPosition() {
        let mapper = CursorMapper()
        XCTAssertNil(mapper.map(Point2D(x: .nan, y: 0.5)))
        XCTAssertNil(mapper.map(Point2D(x: 0.5, y: .infinity)))
    }

    func testInvalidActiveAreaFallsBackToDefault() {
        let mapper = CursorMapper(activeArea: Rect2D(x: 0.5, y: 0.5, width: 0, height: 0.2))
        XCTAssertRectEqual(mapper.effectiveArea, CursorMapper.defaultActiveArea)
    }

    func testCalibrationBuildsActiveAreaFromTwoCorners() {
        let area = ActiveAreaCalibration.activeArea(topLeft: Point2D(x: 0.7, y: 0.2), bottomRight: Point2D(x: 0.25, y: 0.8))
        XCTAssertRectEqual(area, Rect2D(x: 0.25, y: 0.2, width: 0.45, height: 0.6))
    }

    func testCalibrationClipsToCameraFrameAndRejectsTinyAreas() {
        let clipped = ActiveAreaCalibration.activeArea(topLeft: Point2D(x: -0.2, y: 0.1), bottomRight: Point2D(x: 0.5, y: 0.6))
        XCTAssertRectEqual(clipped, Rect2D(x: 0, y: 0.1, width: 0.5, height: 0.5))

        XCTAssertNil(ActiveAreaCalibration.activeArea(topLeft: Point2D(x: 0.5, y: 0.5), bottomRight: Point2D(x: 0.55, y: 0.9)))
        XCTAssertNil(ActiveAreaCalibration.activeArea(topLeft: Point2D(x: .nan, y: 0.5), bottomRight: Point2D(x: 0.9, y: 0.9)))
    }
}
