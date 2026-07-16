import Foundation

enum LayoutMemoryWindowState: String, Codable, Equatable, Sendable {
    case tiling
    case floating
    case hidden
    case minimized
    case nativeFullscreen
}

struct LayoutMemoryWindowReference: Codable, Equatable, Hashable, Sendable {
    let windowId: UInt32
    let bundleId: String
    let title: String
}

struct LayoutMemoryFloatingGeometry: Codable, Equatable, Sendable {
    let monitorIdentity: String
    let normalizedVisibleFrame: CodableRect
    let absoluteFrame: CodableRect
}

struct LayoutMemoryWindowSnapshot: Codable, Equatable, Sendable {
    let reference: LayoutMemoryWindowReference
    let workspace: String
    let state: LayoutMemoryWindowState
    // periphery:ignore - Serialized for future-safe restore compatibility
    let isAeroSpaceFullscreen: Bool
    // periphery:ignore - Serialized for future-safe restore compatibility
    let noOuterGapsInFullscreen: Bool
    let floatingGeometry: LayoutMemoryFloatingGeometry?
    let floatingZIndex: Int?
    // periphery:ignore - Serialized to preserve non-mutating visibility state
    let isHidden: Bool
    // periphery:ignore - Serialized to preserve non-mutating visibility state
    let isMinimized: Bool
    // periphery:ignore - Serialized to preserve non-mutating visibility state
    let isNativeFullscreen: Bool
}

enum LayoutMemoryOrientation: String, Codable, Equatable, Sendable {
    case horizontal
    case vertical
}

enum LayoutMemoryLayout: String, Codable, Equatable, Sendable {
    case tiles
    case accordion
}

indirect enum LayoutMemoryTreeNodeSnapshot: Codable, Equatable, Sendable {
    case container(LayoutMemoryContainerSnapshot)
    case window(LayoutMemoryWindowReference, weight: Double)
}

struct LayoutMemoryContainerSnapshot: Codable, Equatable, Sendable {
    let orientation: LayoutMemoryOrientation
    let layout: LayoutMemoryLayout
    let weight: Double
    let activeChildIndex: Int?
    let children: [LayoutMemoryTreeNodeSnapshot]
}

struct LayoutMemoryWorkspaceSnapshot: Codable, Equatable, Sendable {
    let name: String
    let monitorIdentity: String
    let isVisible: Bool
    let root: LayoutMemoryContainerSnapshot
}

struct LayoutMemoryFocusSnapshot: Codable, Equatable, Sendable {
    let focusedWindow: LayoutMemoryWindowReference?
    let focusedWorkspace: String
}

struct LayoutMemorySnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let snapshotId: UUID
    let createdAt: Date
    let appVersion: String
    let appBuildHash: String
    let monitorProfile: LayoutMemoryMonitorProfile
    let fingerprint: String
    let workspaces: [LayoutMemoryWorkspaceSnapshot]
    let windows: [LayoutMemoryWindowSnapshot]
    let focus: LayoutMemoryFocusSnapshot
    let label: String?
    let isPinned: Bool

    func copy(
        schemaVersion: Int? = nil,
        snapshotId: UUID? = nil,
        createdAt: Date? = nil,
        fingerprint: String? = nil,
        label: String? = nil,
        isPinned: Bool? = nil,
        windows: [LayoutMemoryWindowSnapshot]? = nil,
    ) -> Self {
        .init(
            schemaVersion: schemaVersion ?? self.schemaVersion,
            snapshotId: snapshotId ?? self.snapshotId,
            createdAt: createdAt ?? self.createdAt,
            appVersion: appVersion,
            appBuildHash: appBuildHash,
            monitorProfile: monitorProfile,
            fingerprint: fingerprint ?? self.fingerprint,
            workspaces: workspaces,
            windows: windows ?? self.windows,
            focus: focus,
            label: label ?? self.label,
            isPinned: isPinned ?? self.isPinned,
        )
    }

    func withMetadata(label: String?, isPinned: Bool) -> Self {
        .init(
            schemaVersion: schemaVersion,
            snapshotId: snapshotId,
            createdAt: createdAt,
            appVersion: appVersion,
            appBuildHash: appBuildHash,
            monitorProfile: monitorProfile,
            fingerprint: fingerprint,
            workspaces: workspaces,
            windows: windows,
            focus: focus,
            label: label,
            isPinned: isPinned,
        )
    }
}
