@testable import AppBundle
import XCTest

final class LayoutMemoryRestorePlannerTest: XCTestCase {
    func testPrunesMissingWindowsCollapsesContainersAndNormalizesWeights() throws {
        let one = reference(1)
        let missing = reference(2)
        let snapshot = makeSnapshot(
            root: .init(
                orientation: .horizontal,
                layout: .tiles,
                weight: 1,
                activeChildIndex: nil,
                children: [
                    .container(.init(
                        orientation: .vertical,
                        layout: .accordion,
                        weight: 0.8,
                        activeChildIndex: 1,
                        children: [
                            .window(one, weight: 0.2),
                            .window(missing, weight: 0.8),
                        ],
                    )),
                ],
            ),
            references: [one, missing],
        )
        let matches = LayoutMemoryWindowMatchResult(
            matches: [one: .init(windowId: 10, strategy: .exactTitle)],
            missing: [missing],
            ambiguous: [],
            untouchedLiveWindowIds: [],
        )

        let plan = try LayoutMemoryRestorePlanner.plan(
            snapshot: snapshot,
            currentMonitorSignature: snapshot.monitorProfile.signature,
            expectedLayoutGeneration: 7,
            matches: matches,
            liveWindows: [.init(windowId: 10, workspace: "1", state: .tiling, isNativeFullscreen: false)],
            automatic: false,
        )

        assertEquals(plan.resultKind, .partial)
        assertEquals(plan.workspaces[0].root.children.count, 1)
        guard case .window(let id, let weight) = plan.workspaces[0].root.children[0] else {
            return XCTFail("Expected collapsed window")
        }
        assertEquals(id, 10)
        assertEquals(weight, 1)
    }

    func testAppendsUnmatchedTilingWindowsInSeparateAccordion() throws {
        let one = reference(1)
        let snapshot = makeSnapshot(
            root: .init(
                orientation: .horizontal,
                layout: .tiles,
                weight: 1,
                activeChildIndex: nil,
                children: [.window(one, weight: 1)],
            ),
            references: [one],
        )
        let matches = LayoutMemoryWindowMatchResult(
            matches: [one: .init(windowId: 10, strategy: .windowId)],
            missing: [],
            ambiguous: [],
            untouchedLiveWindowIds: [99],
        )

        let plan = try LayoutMemoryRestorePlanner.plan(
            snapshot: snapshot,
            currentMonitorSignature: snapshot.monitorProfile.signature,
            expectedLayoutGeneration: 1,
            matches: matches,
            liveWindows: [
                .init(windowId: 10, workspace: "1", state: .tiling, isNativeFullscreen: false),
                .init(windowId: 99, workspace: "1", state: .tiling, isNativeFullscreen: false),
            ],
            automatic: false,
        )

        assertEquals(plan.workspaces[0].root.children.count, 2)
        guard case .container(let accordion) = plan.workspaces[0].root.children[1] else {
            return XCTFail("Expected unmatched accordion")
        }
        assertEquals(accordion.layout, .accordion)
        assertEquals(accordion.children, [.window(windowId: 99, weight: 1)])
    }

    func testAutomaticRestoreDefersForNativeFullscreen() {
        let one = reference(1)
        let snapshot = makeSnapshot(
            root: .init(
                orientation: .horizontal,
                layout: .tiles,
                weight: 1,
                activeChildIndex: nil,
                children: [.window(one, weight: 1)],
            ),
            references: [one],
        )
        let matches = LayoutMemoryWindowMatchResult(
            matches: [one: .init(windowId: 10, strategy: .windowId)],
            missing: [],
            ambiguous: [],
            untouchedLiveWindowIds: [],
        )

        XCTAssertThrowsError(try LayoutMemoryRestorePlanner.plan(
            snapshot: snapshot,
            currentMonitorSignature: snapshot.monitorProfile.signature,
            expectedLayoutGeneration: 1,
            matches: matches,
            liveWindows: [.init(windowId: 10, workspace: "1", state: .nativeFullscreen, isNativeFullscreen: true)],
            automatic: true,
        )) { error in
            assertEquals(error as? LayoutMemoryRestorePlanningError, .nativeFullscreenActive)
        }
    }

    private func reference(_ id: UInt32) -> LayoutMemoryWindowReference {
        .init(windowId: id, bundleId: "app", title: "Window \(id)")
    }

    private func makeSnapshot(
        root: LayoutMemoryContainerSnapshot,
        references: [LayoutMemoryWindowReference],
    ) -> LayoutMemorySnapshot {
        let monitor = LayoutMemoryMonitorSnapshot(
            displayUuid: "main",
            vendorNumber: 1,
            modelNumber: 1,
            serialNumber: 1,
            normalizedName: "Main",
            frame: .init(x: 0, y: 0, width: 100, height: 100),
            visibleFrame: .init(x: 0, y: 0, width: 100, height: 100),
            backingScale: 1,
            rotationDegrees: 0,
            isMain: true,
        )
        let profile = try! LayoutMemoryMonitorProfile.make(snapshots: [monitor])
        let windows = references.map {
            LayoutMemoryWindowSnapshot(
                reference: $0,
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
        return .init(
            schemaVersion: 1,
            snapshotId: UUID(),
            createdAt: Date(),
            appVersion: "test",
            appBuildHash: "test",
            monitorProfile: profile,
            fingerprint: "test",
            workspaces: [.init(name: "1", monitorIdentity: "uuid:main", isVisible: true, root: root)],
            windows: windows,
            focus: .init(focusedWindow: references.first, focusedWorkspace: "1"),
            label: nil,
            isPinned: false,
        )
    }
}
