import XCTest
@testable import KLYCKit

final class DisplayAdviceTests: XCTestCase {
    private let standard = DisplayInfo(pointWidth: 1920, pointHeight: 1080, backingScale: 1)
    private let retina = DisplayInfo(pointWidth: 1512, pointHeight: 982, backingScale: 2)

    func testPixelMathFollowsTheBackingScale() {
        XCTAssertFalse(standard.isRetina)
        XCTAssertEqual(standard.pixelWidth, 1920)
        XCTAssertTrue(retina.isRetina)
        XCTAssertEqual(retina.pixelWidth, 3024)
        XCTAssertEqual(retina.pixelHeight, 1964)
        XCTAssertEqual(retina.pixelMegapixels, 5.94, accuracy: 0.01)
        XCTAssertEqual(retina.pointMegapixels, 1.48, accuracy: 0.01)
    }

    func testAScaleBelowOneIsTreatedAsOne() {
        XCTAssertEqual(DisplayInfo(pointWidth: 100, pointHeight: 100, backingScale: 0).backingScale, 1)
    }

    func testStandardDisplayNeedsNothing() {
        let a = DisplayAdvice.advice(for: standard, retinaAt100: false)
        XCTAssertEqual(a.kind, .standard)
        XCTAssertNil(a.recommendedRetinaAt100)
        XCTAssertEqual(a.costFactor, 1)
    }

    func testRetinaOptionOnAStandardDisplayIsAdvisedOff() {
        let a = DisplayAdvice.advice(for: standard, retinaAt100: true)
        XCTAssertEqual(a.kind, .standardOptionOn)
        XCTAssertEqual(a.recommendedRetinaAt100, false)
    }

    func testRetinaLeavesTheChoiceToThePlayerButStatesTheCost() {
        for on in [false, true] {
            let a = DisplayAdvice.advice(for: retina, retinaAt100: on)
            XCTAssertEqual(a.kind, .retina)
            XCTAssertNil(a.recommendedRetinaAt100, "no one-size answer on Retina")
            XCTAssertEqual(a.costFactor, 4, accuracy: 0.05)
        }
    }
}
