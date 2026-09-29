import XCTest
@testable import AirTrackCore

final class ScreenMapperTests: XCTestCase {
    private let main = Rect2D(x: 0, y: 0, width: 1440, height: 900)

    func testCornersAndCenterOfPrimaryDisplay() {
        XCTAssertPointEqual(ScreenMapper.map(Point2D(x: 0, y: 0), to: main), Point2D(x: 0, y: 0))
        XCTAssertPointEqual(ScreenMapper.map(Point2D(x: 0.5, y: 0.5), to: main), Point2D(x: 720, y: 450))
        // Last addressable point stays on this display.
        XCTAssertPointEqual(ScreenMapper.map(Point2D(x: 1, y: 1), to: main), Point2D(x: 1439, y: 899))
    }

    func testSecondaryDisplayToTheRight() {
        let external = Rect2D(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertPointEqual(ScreenMapper.map(Point2D(x: 0.5, y: 0.5), to: external), Point2D(x: 2400, y: 540))
        XCTAssertPointEqual(ScreenMapper.map(Point2D(x: 0, y: 0), to: external), Point2D(x: 1440, y: 0))
    }

    func testDisplayWithNegativeOrigin() {
        let left = Rect2D(x: -1920, y: -200, width: 1920, height: 1080)
        XCTAssertPointEqual(ScreenMapper.map(Point2D(x: 0, y: 0), to: left), Point2D(x: -1920, y: -200))
        XCTAssertPointEqual(ScreenMapper.map(Point2D(x: 1, y: 1), to: left), Point2D(x: -1, y: 879))
    }

    func testOutOfRangeInputIsClampedToTheDisplay() {
        XCTAssertPointEqual(ScreenMapper.map(Point2D(x: -1, y: 2), to: main), Point2D(x: 0, y: 899))
    }

    func testInvalidInputProducesNil() {
        XCTAssertNil(ScreenMapper.map(Point2D(x: .nan, y: 0), to: main))
        XCTAssertNil(ScreenMapper.map(Point2D(x: 0.5, y: 0.5), to: Rect2D(x: 0, y: 0, width: 0, height: 900)))
    }

    func testAppKitToGlobalConversionForPrimaryDisplay() {
        let global = ScreenMapper.globalFrame(fromAppKitFrame: main, primaryDisplayHeight: 900)
        XCTAssertEqual(global, main)
    }

    func testAppKitToGlobalConversionForDisplayAbovePrimary() {
        // AppKit: y grows up, so a display above the primary has minY == primary height.
        let appKitFrame = Rect2D(x: 0, y: 900, width: 1920, height: 1080)
        let global = ScreenMapper.globalFrame(fromAppKitFrame: appKitFrame, primaryDisplayHeight: 900)
        XCTAssertEqual(global, Rect2D(x: 0, y: -1080, width: 1920, height: 1080))
    }

    func testAppKitToGlobalConversionForDisplayBelowPrimary() {
        let appKitFrame = Rect2D(x: 200, y: -768, width: 1024, height: 768)
        let global = ScreenMapper.globalFrame(fromAppKitFrame: appKitFrame, primaryDisplayHeight: 900)
        XCTAssertEqual(global, Rect2D(x: 200, y: 900, width: 1024, height: 768))
    }

    func testDisplayContainingPointUsesHalfOpenEdges() {
        let external = Rect2D(x: 1440, y: 0, width: 1920, height: 1080)
        let displays = [main, external]
        XCTAssertEqual(ScreenMapper.display(containing: Point2D(x: 1439.5, y: 10), in: displays), main)
        XCTAssertEqual(ScreenMapper.display(containing: Point2D(x: 1440, y: 10), in: displays), external)
        XCTAssertNil(ScreenMapper.display(containing: Point2D(x: 5000, y: 10), in: displays))
    }
}
