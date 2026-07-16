@testable import AppBundle
import XCTest

final class LayoutMemoryMonitorProfileTest: XCTestCase {
    func testEnumerationOrderDoesNotChangeSignature() throws {
        let left = monitor(uuid: "left", name: "DELL", x: -1920, main: false)
        let main = monitor(uuid: "main", name: "Built-in Retina Display", x: 0, main: true)

        let first = try LayoutMemoryMonitorProfile.make(snapshots: [left, main])
        let second = try LayoutMemoryMonitorProfile.make(snapshots: [main, left])

        assertEquals(first.signature, second.signature)
        assertEquals(first.monitors, second.monitors)
    }

    func testSmallCoordinateNoiseIsRoundedAway() throws {
        let first = try LayoutMemoryMonitorProfile.make(snapshots: [
            monitor(uuid: "main", name: "Built-in", x: 0.1, main: true),
        ])
        let second = try LayoutMemoryMonitorProfile.make(snapshots: [
            monitor(uuid: "main", name: "Built-in", x: 0.4, main: true),
        ])

        assertEquals(first.signature, second.signature)
    }

    func testDifferentRelativeArrangementChangesSignature() throws {
        let main = monitor(uuid: "main", name: "Built-in", x: 0, main: true)
        let left = monitor(uuid: "external", name: "DELL", x: -1920, main: false)
        let right = monitor(uuid: "external", name: "DELL", x: 1920, main: false)

        let first = try LayoutMemoryMonitorProfile.make(snapshots: [main, left])
        let second = try LayoutMemoryMonitorProfile.make(snapshots: [main, right])

        assertNotEquals(first.signature, second.signature)
    }

    func testMainMonitorIsPartOfSignature() throws {
        let first = try LayoutMemoryMonitorProfile.make(snapshots: [
            monitor(uuid: "a", name: "A", x: 0, main: true),
            monitor(uuid: "b", name: "B", x: 1920, main: false),
        ])
        let second = try LayoutMemoryMonitorProfile.make(snapshots: [
            monitor(uuid: "a", name: "A", x: 0, main: false),
            monitor(uuid: "b", name: "B", x: 1920, main: true),
        ])

        assertNotEquals(first.signature, second.signature)
    }

    func testRejectsMonitorWithoutStableIdentity() {
        let snapshot = monitor(uuid: nil, name: "  ", x: 0, main: true)

        XCTAssertThrowsError(try LayoutMemoryMonitorProfile.make(snapshots: [snapshot]))
    }

    private func monitor(
        uuid: String?,
        name: String,
        x: Double,
        main: Bool,
    ) -> LayoutMemoryMonitorSnapshot {
        LayoutMemoryMonitorSnapshot(
            displayUuid: uuid,
            vendorNumber: 1,
            modelNumber: 2,
            serialNumber: uuid == nil ? 0 : 3,
            normalizedName: name,
            frame: .init(x: x, y: 0, width: 1920, height: 1080),
            visibleFrame: .init(x: x, y: 24, width: 1920, height: 1056),
            backingScale: 2,
            rotationDegrees: 0,
            isMain: main,
        )
    }
}
