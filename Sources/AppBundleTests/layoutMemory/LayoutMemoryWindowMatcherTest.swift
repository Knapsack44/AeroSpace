@testable import AppBundle
import XCTest

final class LayoutMemoryWindowMatcherTest: XCTestCase {
    func testUsesOrderedMatchingStrategies() {
        let stored = [
            storedWindow(id: 1, bundle: "app.a", title: "Exact"),
            storedWindow(id: 2, bundle: "app.a", title: "Project — Details"),
            storedWindow(id: 3, bundle: "app.b", title: "Only"),
        ]
        let live = [
            LayoutMemoryLiveWindow(windowId: 1, bundleId: "app.a", title: "Changed"),
            LayoutMemoryLiveWindow(windowId: 20, bundleId: "app.a", title: "Project — Other"),
            LayoutMemoryLiveWindow(windowId: 30, bundleId: "app.b", title: "Replacement"),
        ]

        let result = LayoutMemoryWindowMatcher.match(stored: stored, live: live)

        assertEquals(result.matches[stored[0].reference]?.windowId, 1)
        assertEquals(result.matches[stored[0].reference]?.strategy, .windowId)
        assertEquals(result.matches[stored[1].reference]?.windowId, 20)
        assertEquals(result.matches[stored[1].reference]?.strategy, .titlePrefix)
        assertEquals(result.matches[stored[2].reference]?.windowId, 30)
        assertEquals(result.matches[stored[2].reference]?.strategy, .uniqueAppWindow)
    }

    func testDuplicateExactTitlesRemainAmbiguous() {
        let stored = [storedWindow(id: 1, bundle: "app.a", title: "Dialog")]
        let live = [
            LayoutMemoryLiveWindow(windowId: 2, bundleId: "app.a", title: "Dialog"),
            LayoutMemoryLiveWindow(windowId: 3, bundleId: "app.a", title: "Dialog"),
        ]

        let result = LayoutMemoryWindowMatcher.match(stored: stored, live: live)

        assertEquals(result.matches, [:])
        assertEquals(result.ambiguous.count, 1)
        assertEquals(result.untouchedLiveWindowIds, [2, 3])
    }

    func testDoesNotMatchByAppIdAloneWhenSeveralCandidatesRemain() {
        let stored = [
            storedWindow(id: 1, bundle: "app.a", title: "One"),
            storedWindow(id: 2, bundle: "app.a", title: "Two"),
        ]
        let live = [
            LayoutMemoryLiveWindow(windowId: 10, bundleId: "app.a", title: "Other A"),
            LayoutMemoryLiveWindow(windowId: 11, bundleId: "app.a", title: "Other B"),
        ]

        let result = LayoutMemoryWindowMatcher.match(stored: stored, live: live)

        assertEquals(result.matches, [:])
        assertEquals(result.ambiguous.count, 2)
    }

    private func storedWindow(id: UInt32, bundle: String, title: String) -> LayoutMemoryWindowSnapshot {
        .init(
            reference: .init(windowId: id, bundleId: bundle, title: title),
            workspace: "1",
            state: .tiling,
            isAeroSpaceFullscreen: false,
            noOuterGapsInFullscreen: false,
            floatingGeometry: nil,
            floatingZIndex: nil,
            isHidden: false,
            isMinimized: false,
            isNativeFullscreen: false,
        )
    }
}
