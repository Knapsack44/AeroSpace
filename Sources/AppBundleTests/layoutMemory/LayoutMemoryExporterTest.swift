@testable import AppBundle
import XCTest

@MainActor
final class LayoutMemoryExporterTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
    }

    func testExportsNestedTreeWeightsAndAccordionActiveChild() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let left = TestWindow.new(id: 1, parent: root, adaptiveWeight: 2)
        let accordion = TilingContainer(parent: root, adaptiveWeight: 3, .v, .accordion, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 2, parent: accordion)
        let active = TestWindow.new(id: 3, parent: accordion)
        active.markAsMostRecentChild()
        left.markAsMostRecentChild()

        let snapshot = try await LayoutMemoryExporter(configuration: .init()).export()

        assertEquals(snapshot.workspaces.count, 1)
        let exportedRoot = snapshot.workspaces[0].root
        assertEquals(exportedRoot.children.count, 2)
        guard case .container(let exportedAccordion) = exportedRoot.children[1] else {
            return XCTFail("Expected nested accordion")
        }
        assertEquals(exportedAccordion.layout, .accordion)
        assertEquals(exportedAccordion.orientation, .vertical)
        assertEquals(exportedAccordion.activeChildIndex, 1)
        assertEquals(exportedRoot.children.map(\.weightForTest), [0.4, 0.6])
    }

    func testExportsFloatingGeometryWithoutMutatingWindow() async throws {
        let workspace = focus.workspace
        let rect = Rect(topLeftX: 100, topLeftY: 120, width: 800, height: 600)
        let window = TestWindow.new(id: 4, parent: workspace.floatingWindowsContainer, rect: rect)

        let snapshot = try await LayoutMemoryExporter(configuration: .init()).export()

        let exported = snapshot.windows.first { $0.reference.windowId == window.windowId }
        assertEquals(exported?.state, .floating)
        assertEquals(exported?.floatingGeometry?.absoluteFrame, CodableRect(rect))
        assertEquals(try await window.getAxRect(.nonCancellable).map(CodableRect.init), CodableRect(rect))
    }

    func testRejectsOccupiedExcludedWorkspace() async {
        var configuration = CustomLayoutMemoryConfig()
        configuration.excludedWorkspaces = ["WSRESTORETMP"]
        let staging = Workspace.get(byName: "WSRESTORETMP")
        _ = TestWindow.new(id: 5, parent: staging.rootTilingContainer)

        do {
            _ = try await LayoutMemoryExporter(configuration: configuration).export()
            XCTFail("Expected occupied staging workspace to block snapshot")
        } catch let error as LayoutMemoryExportError {
            assertEquals(error, .occupiedExcludedWorkspace("WSRESTORETMP"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConfiguredTemporaryTitleIsExcluded() async throws {
        var configuration = CustomLayoutMemoryConfig()
        configuration.temporaryWindowTitleRegexSubstrings = ["^TestWindow\\(6\\)$"]
        let workspace = focus.workspace
        _ = TestWindow.new(id: 6, parent: workspace.rootTilingContainer)

        let snapshot = try await LayoutMemoryExporter(configuration: configuration).export()

        assertEquals(snapshot.windows, [])
        assertEquals(snapshot.workspaces[0].root.children, [])
    }
}

extension LayoutMemoryTreeNodeSnapshot {
    fileprivate var weightForTest: Double {
        switch self {
            case .container(let container): container.weight
            case .window(_, let weight): weight
        }
    }
}
