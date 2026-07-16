@testable import AppBundle
import Foundation
import XCTest

final class LayoutMemoryStoreTest: XCTestCase {
    func testSnapshotRoundTripAndPermissions() throws {
        let root = temporaryDirectory()
        let store = LayoutMemoryStore(rootUrl: root, historyLimit: 5)
        let snapshot = makeSnapshot()

        let saved = try store.save(snapshot)
        let loaded = try store.loadSnapshot(at: saved.url)

        assertEquals(loaded, snapshot)
        let directoryMode = try fileMode(root)
        let fileMode = try fileMode(saved.url)
        assertEquals(directoryMode & 0o777, 0o700)
        assertEquals(fileMode & 0o777, 0o600)
    }

    func testIdenticalRegularSnapshotIsNotDuplicated() throws {
        let store = LayoutMemoryStore(rootUrl: temporaryDirectory(), historyLimit: 5)
        let snapshot = makeSnapshot()

        let first = try store.save(snapshot)
        let second = try store.save(snapshot.copy(snapshotId: UUID(), createdAt: Date().addingTimeInterval(1)))

        assertEquals(first.url.standardizedFileURL.path, second.url.standardizedFileURL.path)
        assertEquals(try store.list(signature: snapshot.monitorProfile.signature).count, 1)
    }

    func testRegularHistoryRotatesButPinnedSnapshotsRemain() throws {
        let store = LayoutMemoryStore(rootUrl: temporaryDirectory(), historyLimit: 2)
        let base = makeSnapshot()
        _ = try store.save(base.copy(fingerprint: "pinned", label: "baseline", isPinned: true))
        _ = try store.save(base.copy(createdAt: Date(timeIntervalSince1970: 1), fingerprint: "one"))
        _ = try store.save(base.copy(createdAt: Date(timeIntervalSince1970: 2), fingerprint: "two"))
        _ = try store.save(base.copy(createdAt: Date(timeIntervalSince1970: 3), fingerprint: "three"))

        let versions = try store.list(signature: base.monitorProfile.signature)
        assertEquals(versions.count, 3)
        assertEquals(versions.filter(\.isPinned).count, 1)
        assertEquals(Set(versions.filter { !$0.isPinned }.map(\.fingerprint)), ["two", "three"])
    }

    func testRejectsUnsupportedSchemaAndWindowLimit() throws {
        let store = LayoutMemoryStore(rootUrl: temporaryDirectory(), historyLimit: 5)
        let base = makeSnapshot()

        XCTAssertThrowsError(try store.save(base.copy(schemaVersion: LayoutMemorySnapshot.currentSchemaVersion + 1)))
        XCTAssertThrowsError(try store.save(base.copy(windows: Array(repeating: base.windows[0], count: 501))))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(component: "aerospace-layout-memory-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func fileMode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func makeSnapshot() -> LayoutMemorySnapshot {
        let monitor = LayoutMemoryMonitorSnapshot(
            displayUuid: "main",
            vendorNumber: 1,
            modelNumber: 2,
            serialNumber: 3,
            normalizedName: "Built-in Retina Display",
            frame: .init(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: .init(x: 0, y: 24, width: 1920, height: 1056),
            backingScale: 2,
            rotationDegrees: 0,
            isMain: true,
        )
        let profile = try! LayoutMemoryMonitorProfile.make(snapshots: [monitor])
        let window = LayoutMemoryWindowSnapshot(
            reference: .init(windowId: 42, bundleId: "com.example", title: "Example"),
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
        return LayoutMemorySnapshot(
            schemaVersion: LayoutMemorySnapshot.currentSchemaVersion,
            snapshotId: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            appVersion: "test",
            appBuildHash: "hash",
            monitorProfile: profile,
            fingerprint: "fingerprint",
            workspaces: [],
            windows: [window],
            focus: .init(focusedWindow: window.reference, focusedWorkspace: "1"),
            label: nil,
            isPinned: false,
        )
    }
}
