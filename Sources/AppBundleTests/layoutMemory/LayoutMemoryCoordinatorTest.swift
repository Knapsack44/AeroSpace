@testable import AppBundle
import Foundation
import XCTest

final class LayoutMemoryCoordinatorTest: XCTestCase {
    func testMatchingEventsCoalesceWithoutRestartingTransition() {
        let start = Date(timeIntervalSince1970: 100)
        var gate = LayoutMemoryTransitionGate()

        assertTrue(gate.request(signature: "three-monitors", at: start))
        assertFalse(gate.request(signature: "three-monitors", at: start.addingTimeInterval(2)))
        assertEquals(gate.startedAt, start)
    }

    func testTopologyChangeStartsAReplacementTransition() {
        let start = Date(timeIntervalSince1970: 100)
        let changedAt = start.addingTimeInterval(2)
        var gate = LayoutMemoryTransitionGate()

        assertTrue(gate.request(signature: "three-monitors", at: start))
        assertTrue(gate.request(signature: "one-monitor", at: changedAt))
        assertEquals(gate.candidateSignature, "one-monitor")
        assertEquals(gate.startedAt, changedAt)
    }

    func testNativeFullscreenDeferralKeepsOriginalStartTime() {
        let start = Date(timeIntervalSince1970: 100)
        var gate = LayoutMemoryTransitionGate()
        _ = gate.request(signature: "three-monitors", at: start)

        gate.clearCandidate()
        assertTrue(gate.request(signature: "three-monitors", at: start.addingTimeInterval(10)))
        assertFalse(gate.hasExceededDeferral(at: start.addingTimeInterval(299), seconds: 300))
        assertTrue(gate.hasExceededDeferral(at: start.addingTimeInterval(300), seconds: 300))
    }

    func testResetClearsPendingTransition() {
        var gate = LayoutMemoryTransitionGate()
        _ = gate.request(signature: "three-monitors", at: Date())

        gate.reset()

        assertEquals(gate, LayoutMemoryTransitionGate())
    }
}
