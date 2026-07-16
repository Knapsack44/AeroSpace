@testable import AppBundle
import XCTest

@MainActor
final class LayoutMemoryRestorerTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        LayoutMemoryRuntime.shared.resetForTests()
    }

    func testRestoresTreeOrderLayoutAndFocus() async throws {
        let workspace = focus.workspace
        let oldRoot = workspace.rootTilingContainer
        let first = TestWindow.new(id: 10, parent: oldRoot)
        let second = TestWindow.new(id: 20, parent: oldRoot)
        first.nativeFocus()
        let profile = try currentLayoutMemoryMonitorProfile()
        let generation = LayoutMemoryRuntime.shared.layoutGeneration
        let plan = ResolvedLayoutMemoryPlan(
            expectedMonitorSignature: profile.signature,
            expectedLayoutGeneration: generation,
            sourceFingerprint: "snapshot",
            workspaces: [
                .init(
                    name: workspace.name,
                    monitorIdentity: profile.monitors[0].stableIdentity!,
                    isVisible: true,
                    root: .init(
                        orientation: .vertical,
                        layout: .accordion,
                        weight: 1,
                        activeChildIndex: 1,
                        children: [
                            .window(windowId: 20, weight: 0.7),
                            .window(windowId: 10, weight: 0.3),
                        ],
                    ),
                ),
            ],
            floatingWindows: [],
            visibility: .init(visibleWorkspaceByMonitorIdentity: [
                profile.monitors[0].stableIdentity!: workspace.name,
            ]),
            focus: .init(windowId: second.windowId, workspace: workspace.name),
            resultKind: .full,
        )

        let result = try await LayoutMemoryRestorer.restore(plan)

        assertEquals(result.kind, .full)
        assertEquals(result.mutated, true)
        assertEquals(workspace.rootTilingContainer.orientation, .v)
        assertEquals(workspace.rootTilingContainer.layout, .accordion)
        assertEquals(workspace.rootTilingContainer.children.compactMap { ($0 as? Window)?.windowId }, [20, 10])
        assertEquals(workspace.rootTilingContainer.mostRecentChild as? Window, second)
        assertEquals(focus.windowOrNil, second)
        assertEquals(LayoutMemoryRuntime.shared.phase, .idle)
    }

    func testRejectsChangedGenerationBeforeMutation() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        _ = TestWindow.new(id: 10, parent: root)
        let profile = try currentLayoutMemoryMonitorProfile()
        let plan = ResolvedLayoutMemoryPlan(
            expectedMonitorSignature: profile.signature,
            expectedLayoutGeneration: 999,
            sourceFingerprint: "snapshot",
            workspaces: [
                .init(
                    name: workspace.name,
                    monitorIdentity: profile.monitors[0].stableIdentity!,
                    isVisible: true,
                    root: .init(
                        orientation: .horizontal,
                        layout: .tiles,
                        weight: 1,
                        activeChildIndex: nil,
                        children: [.window(windowId: 10, weight: 1)],
                    ),
                ),
            ],
            floatingWindows: [],
            visibility: .init(visibleWorkspaceByMonitorIdentity: [:]),
            focus: .init(windowId: 10, workspace: workspace.name),
            resultKind: .full,
        )

        do {
            _ = try await LayoutMemoryRestorer.restore(plan)
            XCTFail("Expected generation mismatch")
        } catch let error as LayoutMemoryRestoreError {
            assertEquals(error, .layoutChanged)
        }

        assertEquals(workspace.rootTilingContainer, root)
        assertEquals(root.children.compactMap { ($0 as? Window)?.windowId }, [10])
    }
}
