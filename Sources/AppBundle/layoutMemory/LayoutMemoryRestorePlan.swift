import Foundation

struct LayoutMemoryLiveWindowState: Equatable, Sendable {
    let windowId: UInt32
    let workspace: String
    let state: LayoutMemoryWindowState
    let isNativeFullscreen: Bool
}

enum LayoutMemoryRestoreResultKind: String, Equatable, Sendable {
    case full
    case partial
    case noOp
}

indirect enum ResolvedLayoutMemoryNode: Equatable, Sendable {
    case container(ResolvedLayoutMemoryContainer)
    case window(windowId: UInt32, weight: Double)

    var weight: Double {
        switch self {
            case .container(let container): container.weight
            case .window(_, let weight): weight
        }
    }

    func withWeight(_ weight: Double) -> Self {
        switch self {
            case .container(let container): .container(container.copy(weight: weight))
            case .window(let windowId, _): .window(windowId: windowId, weight: weight)
        }
    }
}

struct ResolvedLayoutMemoryContainer: Equatable, Sendable {
    let orientation: LayoutMemoryOrientation
    let layout: LayoutMemoryLayout
    let weight: Double
    let activeChildIndex: Int?
    let children: [ResolvedLayoutMemoryNode]

    func copy(weight: Double? = nil, children: [ResolvedLayoutMemoryNode]? = nil) -> Self {
        .init(
            orientation: orientation,
            layout: layout,
            weight: weight ?? self.weight,
            activeChildIndex: activeChildIndex,
            children: children ?? self.children,
        )
    }
}

struct ResolvedWorkspacePlan: Equatable, Sendable {
    let name: String
    let monitorIdentity: String
    let isVisible: Bool
    let root: ResolvedLayoutMemoryContainer
}

struct ResolvedFloatingWindowPlan: Equatable, Sendable {
    let windowId: UInt32
    let workspace: String
    let geometry: LayoutMemoryFloatingGeometry?
    let zIndex: Int?
}

struct ResolvedVisibilityPlan: Equatable, Sendable {
    let visibleWorkspaceByMonitorIdentity: [String: String]
}

struct ResolvedFocusPlan: Equatable, Sendable {
    let windowId: UInt32?
    let workspace: String
}

struct ResolvedLayoutMemoryPlan: Equatable, Sendable {
    let expectedMonitorSignature: String
    let expectedLayoutGeneration: UInt64
    let sourceFingerprint: String
    let workspaces: [ResolvedWorkspacePlan]
    let floatingWindows: [ResolvedFloatingWindowPlan]
    let visibility: ResolvedVisibilityPlan
    let focus: ResolvedFocusPlan
    let resultKind: LayoutMemoryRestoreResultKind
}
