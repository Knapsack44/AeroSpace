import AppBundle
import XCTest

final class AxFrameUpdateDecisionTest: XCTestCase {
    func testSkipsChangesWithinTolerance() {
        let decision = AxFrameUpdateDecision(
            currentTopLeft: CGPoint(x: 100, y: 200),
            targetTopLeft: CGPoint(x: 100.5, y: 199.5),
            currentSize: CGSize(width: 800, height: 600),
            targetSize: CGSize(width: 799.5, height: 600.5),
        )

        XCTAssertFalse(decision.hasUpdates)
    }

    func testUpdatesOnlyDimensionsOutsideTolerance() {
        let decision = AxFrameUpdateDecision(
            currentTopLeft: CGPoint(x: 100, y: 200),
            targetTopLeft: CGPoint(x: 100.51, y: 200),
            currentSize: CGSize(width: 800, height: 600),
            targetSize: CGSize(width: 800, height: 600),
        )

        XCTAssertTrue(decision.shouldUpdateTopLeft)
        XCTAssertFalse(decision.shouldUpdateSize)
    }

    func testMissingCurrentValueRequiresUpdate() {
        let decision = AxFrameUpdateDecision(
            currentTopLeft: nil,
            targetTopLeft: CGPoint(x: 100, y: 200),
            currentSize: nil,
            targetSize: CGSize(width: 800, height: 600),
        )

        XCTAssertTrue(decision.shouldUpdateTopLeft)
        XCTAssertTrue(decision.shouldUpdateSize)
    }

    func testMissingTargetDoesNotRequireUpdate() {
        let decision = AxFrameUpdateDecision(
            currentTopLeft: CGPoint(x: 100, y: 200),
            targetTopLeft: nil,
            currentSize: CGSize(width: 800, height: 600),
            targetSize: nil,
        )

        XCTAssertFalse(decision.hasUpdates)
    }
}
